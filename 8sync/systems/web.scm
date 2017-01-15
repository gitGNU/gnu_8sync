;;; 8sync --- Asynchronous programming for Guile
;;; Copyright © 2017 Christopher Allan Webber <cwebber@dustycloud.org>
;;;
;;; Code (also under the LGPL) borrowed from fibers:
;;;   Copyright © 2016 Andy Wingo <wingo@pobox.com>
;;; and Guile:
;;;   Copyright © 2010, 2011, 2012, 2015 Free Software Foundation, Inc.
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


(define-module (8sync systems web)
  #:use-module (oop goops)
  #:use-module (ice-9 match)
  #:use-module (ice-9 receive)
  #:use-module (web http)
  #:use-module (web request)
  #:use-module (web response)
  #:use-module (web server)
  #:use-module (rnrs io ports)
  #:use-module (8sync)
  #:export (<web-server>
            ;; @@: If we don't want to import these because of
            ;;   "conflicts" with other objects, we could just
            ;;   select <web-server> only.
            ;;   Alternately we could move the crux of this into
            ;;   another module and just export <web-server>, though
            ;;   that does feel a bit like overkill.
            .host .family .port-num .addr .socket
            .upgrade-paths .http-handler))

(define-actor <web-server> (<actor>)
  ((*init* web-server-socket-loop)
   (*cleanup* web-server-cleanup)
   (shutdown web-server-shutdown)
   (new-client web-server-client-loop)
   (handle-request web-server-handle-request))

  (host #:init-value #f
        #:init-keyword #:host
        #:getter .host)
  (family #:init-value AF_INET
          #:init-keyword #:family
          #:getter .family)
  (port-num #:init-value 8080
            #:init-keyword #:port
            #:getter .port-num)
  (addr #:init-keyword #:addr
        #:accessor .addr)
  (socket #:init-value #f
          #:accessor .socket)
  (upgrade-paths #:init-value '()
                 #:allocation #:each-subclass)
  (http-handler #:init-keyword #:http-handler
                #:getter .http-handler))

;; Define getter externally so it works even if we subclass
(define-method (.upgrade-paths (web-server <web-server>))
  (slot-ref web-server 'upgrade-paths))

(define-method (initialize (web-server <web-server>) init-args)
  (next-method)
  ;; Make sure the addr is set up
  (when (not (slot-bound? web-server 'addr))
    (set! (.addr web-server)
          (if (.host web-server)
              (inet-pton (.family web-server)
                         (.host web-server))
              INADDR_LOOPBACK)))

  ;; Set up the socket
  (set! (.socket web-server)
        (make-default-socket (.family web-server)
                             (.addr web-server)
                             (.port-num web-server)))

  ;; This is borrowed from Guile's web server.
  ;; Andy Wingo added the line with this commit:
  ;; * module/web/server/http.scm (http-open): Ignore SIGPIPE. Keeps the
  ;;   server from dying in some circumstances.
  (sigaction SIGPIPE SIG_IGN))

;; @@: Borrowed from Guile itself / Fibers

(define (set-nonblocking! port)
  (fcntl port F_SETFL (logior O_NONBLOCK (fcntl port F_GETFL)))
  (setvbuf port 'block 1024))

(define (make-default-socket family addr port)
  (let ((sock (socket PF_INET SOCK_STREAM 0)))
    (setsockopt sock SOL_SOCKET SO_REUSEADDR 1)
    (fcntl sock F_SETFD FD_CLOEXEC)
    (bind sock family addr port)
    (set-nonblocking! sock)
    ;; We use a large backlog by default.  If the server is suddenly hit
    ;; with a number of connections on a small backlog, clients won't
    ;; receive confirmation for their SYN, leading them to retry --
    ;; probably successfully, but with a large latency.
    (listen sock 1024)
    sock))

(define (web-server-socket-loop web-server message)
  "The main loop on our socket.  Keep accepting new clients as long
as we're alive."
  (while #t
    (match (accept (.socket web-server))
      ((client . sockaddr)
       ;; From "HOP, A Fast Server for the Diffuse Web", Serrano.
       (setsockopt client SOL_SOCKET SO_SNDBUF (* 12 1024))
       (set-nonblocking! client)
       ;; Always disable Nagle's algorithm, as we handle buffering
       ;; ourselves.  Ignore exceptions if it's not a TCP port, or
       ;; TCP_NODELAY is not defined on this platform.
       (false-if-exception
        (setsockopt client IPPROTO_TCP TCP_NODELAY 0))
       (<- (actor-id web-server) 'new-client client)))))

(define (keep-alive? response)
  (let ((v (response-version response)))
    (and (or (< (response-code response) 400)
             (= (response-code response) 404))
         (case (car v)
           ((1)
            (case (cdr v)
              ((1) (not (memq 'close (response-connection response))))
              ((0) (memq 'keep-alive (response-connection response)))))
           (else #f)))))

(define (maybe-upgrade-request web-server request body)
  (define upgrade-paths (.upgrade-paths web-server))
  ;; A request can specify multiple values to the "Upgrade"
  ;; field, so we slook to see if we have an applicable option,
  ;; in order.
  ;; Note that we'll only handle one... we *don't* "compose"
  ;; upgrades.
  (let loop ((upgrades (request-upgrade request)))
    (if (eq? upgrades '())
        #f ; Shouldn't upgrade
        (match (assoc (car upgrades) upgrade-paths)
          ;; Yes, upgrade with this method
          ((_ . upgrade-proc)
           upgrade-proc)
          ;; Keep looking...
          (#f (loop (cdr upgrades)))))))

(define (web-server-client-loop web-server message client)
  "Read request(s) from a client and pass off to the handler."
  (with-throw-handler #t
    (lambda ()
      (let loop ()
        (define (respond-and-maybe-continue _ response body)
          (write-response response client)
          (when body
            (put-bytevector client body))
          (force-output client)
          (if (and (keep-alive? response)
                   (not (eof-object? (peek-char client))))
              (loop)
              (close-port client)))
        (cond
         ((eof-object? (lookahead-u8 client))
          (close-port client))
         (else
          (catch #t
            (lambda ()
              (let* ((request (read-request client))
                     (body (read-request-body request)))
                (cond
                 ;; Should we "upgrade" the protocol?
                 ;; Doing so "breaks out" of this loop, possibly into a new one
                 ((maybe-upgrade-request web-server request body) =>
                  (lambda (upgrade)
                    ;; TODO: this isn't great because we're in this catch,
                    ;;   which doesn't make sense once we've "upgraded"
                    ;;   since we might not "respond" in the same way anymore.
                    (upgrade web-server client request body)))
                 (else
                  (call-with-message
                   ;; TODO: Add error handling in case we get an error
                   ;;   response
                   (<-wait (actor-id web-server) 'handle-request
                           request body)
                   respond-and-maybe-continue)))))
            (lambda (key . args)
              (display "While reading request:\n" (current-error-port))
              (print-exception (current-error-port) #f key args)
              (respond-and-maybe-continue
               #f ;; ignored, there is no message
               (build-response #:version '(1 . 0) #:code 400
                               #:headers '((content-length . 0)))
               #vu8())))))))
    (lambda (k . args)
      (catch #t
        (lambda () (close-port client))
        (lambda (k . args)
          (display "While closing port:\n" (current-error-port))
          (print-exception (current-error-port) #f k args))))))

(define (web-server-handle-request web-server message
                                   request body)
  (receive (response body)
      ((.http-handler web-server) request body)
    (receive (response body)
        (sanitize-response request response body)
      (<-reply message response body))))

(define (web-server-cleanup web-server message)
  ;; @@: Should we close any pending requests too?
  (close (.socket web-server)))

(define (web-server-shutdown web-server message)
  (self-destruct web-server))
