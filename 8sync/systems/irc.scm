#!/usr/bin/guile \
-e main -s
!#

;;; 8sync --- Asynchronous programming for Guile
;;; Copyright (C) 2015 Christopher Allan Webber <cwebber@dustycloud.org>
;;;
;;; This file is part of 8sync.
;;;
;;; 8sync is free software: you can redistribute it and/or modify it
;;; under the terms of the GNU Lesser General Public License as
;;; published by the Free Software Foundation, either version 3 of the
;;; License, or (at your option) any later version.
;;;
;;; 8sync is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU Lesser General Public License for more details.
;;;
;;; You should have received a copy of the GNU Lesser General Public
;;; License along with 8sync.  If not, see <http://www.gnu.org/licenses/>.

(define-module (8sync systems irc)
  #:use-module (8sync repl)
  #:use-module (8sync agenda)
  #:use-module (8sync actors)
  #:use-module (srfi srfi-9)
  #:use-module (ice-9 getopt-long)
  #:use-module (ice-9 format)
  #:use-module (ice-9 receive)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 q)
  #:use-module (ice-9 match)
  #:use-module (oop goops)
  #:export (<irc-bot>
            irc-bot-username irc-bot-server irc-bot-channels
            irc-bot-port irc-bot-handler

            default-irc-port))


;;; Network stuff
;;; =============

(define default-irc-port 6665)

(define* (irc-socket-setup hostname #:optional (inet-port default-irc-port))
  (let* ((s (socket PF_INET SOCK_STREAM 0))
         (flags (fcntl s F_GETFL))
         (ip-address (inet-ntop AF_INET (car (hostent:addr-list (gethost hostname))))))
    (fcntl s F_SETFL (logior O_NONBLOCK flags))
    (connect s AF_INET
             (inet-pton AF_INET ip-address)
             inet-port)
    s))

(define irc-eol "\r\n")

(define (startswith-colon? str)
  (and (> (string-length str) 0)
       (eq? (string-ref str 0)
            #\:)))

;; TODO: This needs a cleanup.  Maybe even just using a regex is fine.
(define (parse-line line)
  (define (parse-params pre-params)
    ;; This is stupid and imperative but I can't wrap my brain around
    ;; the right way to do it in a functional way :\
    (let ((param-list '())
          (currently-building '()))
      (for-each
       (lambda (param-item)
         (cond
          ((startswith-colon? param-item)
           (if (not (eq? currently-building '()))
               (set! param-list
                     (cons
                      (reverse currently-building)
                      param-list)))
           (set! currently-building (list param-item)))
          (else
           (set! currently-building (cons param-item currently-building)))))
       pre-params)
      ;; We're still building something, so tack that on there
      (if (not (eq? currently-building '()))
          (set! param-list
                (cons (reverse currently-building) param-list)))
      ;; return the reverse of the param list
      (reverse param-list)))

  (match (string-split line #\space)
    (((? startswith-colon? prefix)
      command
      pre-params ...)
     (values prefix command
             (parse-params pre-params)))
    ((command pre-params ...)
     (values #f command
             (parse-params pre-params)))))

(define (strip-colon-if-necessary string)
  (if (and (> (string-length string) 0)
           (string-ref string 0))
      (substring/copy string 1)
      string))

;; @@: Not sure if this works in all cases, like what about in a non-privmsg one?
(define (irc-line-username irc-line-prefix)
  (let* ((prefix-name (strip-colon-if-necessary irc-line-prefix))
         (exclaim-index (string-index prefix-name #\!)))
    (if exclaim-index
        (substring/copy prefix-name 0 exclaim-index)
        prefix-name)))

(define (condense-privmsg-line line)
  "Condense message line and do multiple value return of
  (channel message emote?)"
  (define (strip-last-char string)
    (substring/copy string 0 (- (string-length string) 1)))
  (let* ((channel-name (caar line))
         (rest-params (apply append (cdr line))))
    (match rest-params
      (((or "\x01ACTION" ":\x01ACTION") middle-words ... (= strip-last-char last-word))
       (values channel-name
               (string-join
                (append middle-words (list last-word))
                " ")
               #t))
      (((= strip-colon-if-necessary first-word) rest-message ...)
       (values channel-name
               (string-join (cons first-word rest-message) " ")
               #f)))))

;;; A goofy default
(define (echo-message irc-bot speaker channel-name
                      line-text emote?)
  "Simply echoes the message to the current-output-port."
  (if emote?
      (format #t "~a emoted ~s in channel ~a\n"
              speaker line-text channel-name)
      (format #t "~a said ~s in channel ~a\n"
              speaker line-text channel-name)))


;;; Bot
;;; ===

(define-class <irc-bot> (<actor>)
  (username #:init-keyword #:username
            #:getter irc-bot-username)
  (realname #:init-keyword #:realname
            #:init-value #f)
  (server #:init-keyword #:server
          #:getter irc-bot-server)
  (channels #:init-keyword #:channels
            #:getter irc-bot-channels)
  (port #:init-keyword #:port
        #:init-value default-irc-port
        #:getter irc-bot-port)
  (line-handler #:init-keyword #:line-handler
                #:init-value (wrap-apply echo-message)
                #:getter irc-bot-line-handler)
  (socket #:accessor irc-bot-socket)
  (actions #:allocation #:each-subclass
           #:init-value (build-actions
                         (init irc-bot-init)
                         (main-loop irc-bot-main-loop)
                         (send-line irc-bot-send-line))))

(define (irc-bot-realname irc-bot)
  (or (slot-ref irc-bot 'realname)
      (irc-bot-username irc-bot)))

(define (irc-bot-init irc-bot message)
  "Initialize the IRC bot"
  (define socket
    (irc-socket-setup (irc-bot-server irc-bot)
                      (irc-bot-port irc-bot)))
  (set! (irc-bot-socket irc-bot) socket)
  (format socket "USER ~a ~a ~a :~a~a"
          (irc-bot-username irc-bot)
          "*" "*"  ; hostname and servername
          (irc-bot-realname irc-bot) irc-eol)
  (format socket "NICK ~a~a" (irc-bot-username irc-bot) irc-eol)

  (for-each
   (lambda (channel)
     (format socket "JOIN ~a~a" channel irc-eol))
   (irc-bot-channels irc-bot))

  (<- irc-bot (actor-id irc-bot) 'main-loop))

(define (irc-bot-main-loop irc-bot message)
  (define socket (irc-bot-socket irc-bot))
  (define line (string-trim-right (read-line socket) #\return))
  (irc-bot-dispatch-line irc-bot line)
  (cond
   ;; The port's been closed for some reason, so stop looping
   ((port-closed? socket)
    'done)
   ;; We've reached the EOF object, which means we should close
   ;; the port ourselves and stop looping
   ((eof-object? (peek-char socket))
    (close socket)
    'done)
   ;; ;; Looks like we've been killed somehow... well, stop running
   ;; ;; then!
   ;; ((actor-am-i-dead? irc-bot)
   ;;  (if (not (port-closed? socket))
   ;;      (close socket))
   ;;  'done)
   ;; Otherwise, let's read till the next line!
   (else
    (<- irc-bot (actor-id irc-bot) 'main-loop))))

(define-method (irc-bot-dispatch-line (irc-bot <irc-bot>) line)
  (receive (line-prefix line-command line-params)
      (parse-line line)
    (match line-command
      ("PING"
       (display "PONG" (irc-bot-socket irc-bot)))
      ("PRIVMSG"
       (receive (channel-name line-text emote?)
           (condense-privmsg-line line-params)
         (let ((username (irc-line-username line-prefix)))
           ((irc-bot-line-handler irc-bot) irc-bot username
            channel-name line-text emote?))))
      (_
       (display line)
       (newline)))))

(define* (irc-bot-send-line irc-bot message
                            channel line #:key emote?)
  ;; TODO: emote? handling
  (format (irc-bot-socket irc-bot) "PRIVMSG ~a :~a~a"
          channel line irc-eol))
