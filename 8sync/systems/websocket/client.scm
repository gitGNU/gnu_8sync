;;; guile-websocket --- WebSocket client/server
;;; Copyright © 2016 David Thompson <davet@gnu.org>
;;;
;;; This file is part of guile-websocket.
;;;
;;; Guile-websocket is free software; you can redistribute it and/or modify
;;; it under the terms of the GNU Lesser General Public License as
;;; published by the Free Software Foundation; either version 3 of the
;;; License, or (at your option) any later version.
;;;
;;; Guile-websocket is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Lesser General Public License for more details.
;;;
;;; You should have received a copy of the GNU Lesser General Public
;;; License along with guile-websocket.  If not, see
;;; <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; WebSocket client.
;;
;;; Code:

(define-module (8sync systems websocket client)
  #:use-module (ice-9 match)
  #:use-module (rnrs bytevectors)
  #:use-module (rnrs io ports)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-9 gnu)
  #:use-module (web request)
  #:use-module (web response)
  #:use-module (web uri)
  #:use-module (8sync contrib base64)
  #:use-module (8sync systems websocket frame)
  #:use-module (8sync systems websocket utils)
  #:export (make-websocket
            websocket?
            websocket-uri
            websocket-state
            websocket-connecting?
            websocket-open?
            websocket-closing?
            websocket-closed?
            close-websocket
            websocket-send
            websocket-receive))

;; See Section 3 - WebSocket URIs
(define (encrypted-websocket-scheme? uri)
  "Return #t if the scheme for URI is 'wss', the secure WebSocket
scheme."
  (eq? (uri-scheme uri) 'wss))

(define (unencrypted-websocket-scheme? uri)
  "Return #t if the scheme for URI is 'ws', the insecure WebSocket
scheme."
  (eq? (uri-scheme uri) 'ws))

(define (websocket-uri? uri)
  "Return #t if URI is a valid WebSocket URI."
  (and (or (encrypted-websocket-scheme? uri)
           (unencrypted-websocket-scheme? uri))
       (not (uri-fragment uri))))

(define (make-client-socket uri)
  "Connect a socket to the remote resource described by URI."
  (let* ((port (uri-port uri))
         (info (car (getaddrinfo (uri-host uri)
                                 (if port
                                     (number->string port)
                                     (symbol->string (uri-scheme uri)))
                                 (if port
                                     AI_NUMERICSERV
                                     0))))
         (s (with-fluids ((%default-port-encoding #f))
              (socket (addrinfo:fam info) SOCK_STREAM IPPROTO_IP))))
    ;; TODO: Configure I/O buffering?
    (connect s (addrinfo:addr info))
    s))

(define-record-type <websocket>
  (%make-websocket uri socket entropy-port state)
  websocket?
  (uri websocket-uri)
  (socket websocket-socket)
  (entropy-port websocket-entropy-port)
  (state websocket-state set-websocket-state!))

(define (display-websocket ws port)
  (format port "#<websocket ~a ~a>"
          (uri->string (websocket-uri ws))
          (websocket-state ws)))

(set-record-type-printer! <websocket> display-websocket)

(define (websocket-connecting? ws)
  "Return #t if the WebSocket WS is in the connecting state."
  (eq? (websocket-state ws) 'connecting))

(define (websocket-open? ws)
  "Return #t if the WebSocket WS is in the open state."
  (eq? (websocket-state ws) 'open))

(define (websocket-closing? ws)
  "Return #t if the WebSocket WS is in the closing state."
  (eq? (websocket-state ws) 'closing))

(define (websocket-closed? ws)
  "Return #t if the WebSocket WS is in the closed state."
  (eq? (websocket-state ws) 'closed))

(define (generate-client-key ws)
  "Return a random, base64 encoded nonce using the entropy source of
WS."
  (base64-encode
   (get-bytevector-n (websocket-entropy-port ws) 16)))

;; See Section 4.1 - Client Requirements
(define (make-handshake-request uri key)
  "Create an HTTP request for initiating a WebSocket connection with
the remote resource described by URI, using a randomly generated nonce
KEY."
  (let ((headers `((host . (,(uri-host uri) . #f))
                   (upgrade . ("WebSocket"))
                   (connection . (upgrade))
                   (sec-websocket-key . ,key)
                   (sec-websocket-version . "13"))))
    (build-request uri #:method 'GET #:headers headers)))

(define (handshake ws)
  "Perform the WebSocket handshake for the client WS."
  (let ((key (generate-client-key ws)))
    (write-request (make-handshake-request (websocket-uri ws) key)
                   (websocket-socket ws))
    (let* ((response (read-response (websocket-socket ws)))
           (headers (response-headers response))
           (upgrade (assoc-ref headers 'upgrade))
           (connection (assoc-ref headers 'connection))
           (accept (assoc-ref headers 'sec-websocket-accept)))
      ;; Validate the handshake.
      (if (and (= (response-code response) 101)
               (string-ci=? (car upgrade) "websocket")
               (equal? connection '(upgrade))
               (string=? (string-trim-both accept) (make-accept-key key)))
          (set-websocket-state! ws 'open)
          (begin
            (close-websocket ws)
            (error "websocket handshake failed" (websocket-uri ws)))))))

(define (open-entropy-port)
  "Return an open input port to a reliable source of entropy for the
current system."
  ;; XXX: This works on GNU/Linux and OS X systems, but this isn't
  ;; exactly portable.
  (open-input-file "/dev/urandom"))

(define (make-websocket uri-or-string)
  "Create and establish a new WebSocket connection for the remote
resource described by URI-OR-STRING."
  (let ((uri (match uri-or-string
               ((? uri? uri) uri)
               ((? string? str) (string->uri str)))))
    (if (websocket-uri? uri)
        (let ((ws (%make-websocket uri
                                   (make-client-socket uri)
                                   (open-entropy-port)
                                   'connecting)))
          (handshake ws)
          ws)
        (error "not a websocket uri" uri))))

(define (close-websocket ws)
  "Close the WebSocket connection for the client WS."
  (let ((socket (websocket-socket ws)))
    (set-websocket-state! ws 'closing)
    (write-frame (make-close-frame (make-bytevector 0)) socket)
    ;; Per section 5.5.1 , wait for the server to close the connection
    ;; for a reasonable amount of time.
    (let loop ()
      (match (select #() (vector socket) #() 1) ; 1 second timeout
        ((#() #(socket) #()) ; there is output to read
         (unless (port-eof? socket)
           (read-frame socket) ; throw it away
           (loop)))))
    (close-port socket)
    (close-port (websocket-entropy-port ws))
    (set-websocket-state! ws 'closed)
    *unspecified*))

(define (generate-masking-key ws)
  "Create a new masking key using the entropy source of WS."
  ;; Masking keys are 32 bits long.
  (get-bytevector-n (websocket-entropy-port ws) 4))

(define (websocket-send ws data)
  "Send DATA, a string or bytevector, to the server that WS is
connected to."
  ;; TODO: Send frames over some threshold in fragments.
  (write-frame (make-text-frame data (generate-masking-key ws))
               (websocket-socket ws)))

(define (websocket-receive ws)
  "Read a response from the server that WS is connected to."
  ;; TODO: Handle fragmented frames and control frames.
  (let ((frame (read-frame (websocket-socket ws))))
    (if (binary-frame? frame)
        (frame-data frame)
        (text-frame->string frame))))
