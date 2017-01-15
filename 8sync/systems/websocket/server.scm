;;; guile-websocket --- WebSocket client/server
;;; Copyright © 2015 David Thompson <davet@gnu.org>
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
;; WebSocket server.
;;
;;; Code:

(define-module (8sync systems websocket server)
  #:use-module (ice-9 match)
  #:use-module (rnrs bytevectors)
  #:use-module (rnrs io ports)
  #:use-module (web request)
  #:use-module (web response)
  #:use-module (web uri)
  #:use-module (oop goops)
  #:use-module (8sync)
  #:use-module (8sync ports)
  #:use-module (8sync systems web)
  #:use-module (8sync systems websocket frame)
  #:use-module (8sync systems websocket utils)
  #:export (<websocket-server>))

;; See section 4.2 for explanation of the handshake.
(define (read-handshake-request client-socket)
  "Read HTTP request from CLIENT-SOCKET that should contain the
headers required for a WebSocket handshake."
  ;; See section 4.2.1.
  (read-request client-socket))

(define (make-handshake-response client-key)
  "Return an HTTP response object for upgrading to a WebSocket
connection for the client whose key is CLIENT-KEY, a base64 encoded
string."
  ;; See section 4.2.2.
  (let ((accept-key (make-accept-key (string-trim-both client-key))))
    (build-response #:code 101
                    #:headers `((upgrade . ("websocket"))
                                (connection . (upgrade))
                                (sec-websocket-accept . ,accept-key)))))

(define-actor <websocket-server> (<web-server>)
  ((new-client websocket-client-loop))
  (websocket-handler #:init-keyword #:websocket-handler
                     #:getter .websocket-handler))

(define (websocket-client-loop websocket-server message client)
  "Serve client connected via CLIENT by performing the HTTP
handshake and listening for control and data frames.  HANDLER is
called for each complete message that is received."
  (define (handle-data-frame type data)
    (let* ((result   ((.websocket-handler websocket-server)
                      (match type
                        ('text   (utf8->string data))
                        ('binary data))))
           (response (cond
                      ((string? result)
                       (make-text-frame result))
                      ((bytevector? result)
                       (make-binary-frame result))
                      ((not result)
                       #f))))

      (when response
        (write-frame response client))))

  (define (read-frame-maybe)
    (and (not (eof-object? (lookahead-u8 client)))
         (read-frame client)))

  ;; Disable buffering for websockets
  (setvbuf client 'none)

  ;; Perform the HTTP handshake and upgrade to WebSocket protocol.
  (let* ((request (read-handshake-request client))
         (client-key (assoc-ref (request-headers request) 'sec-websocket-key))
         (response (make-handshake-response client-key)))
    (write-response response client)
    (let loop ((fragments '())
               (type #f))
      (let ((frame (read-frame-maybe)))
        (cond
         ;; EOF - port is closed.
         ((not frame)
          (close-port client))
         ;; Per section 5.4, control frames may appear interspersed
         ;; along with a fragmented message.
         ((close-frame? frame)
          ;; Per section 5.5.1, echo the close frame back to the
          ;; client before closing the socket.  The client may no
          ;; longer be listening.
          (false-if-exception
           (write-frame (make-close-frame (frame-data frame)) client))
          (close-port client))
         ((ping-frame? frame)
          ;; Per section 5.5.3, a pong frame must include the exact
          ;; same data as the ping frame.
          (write-frame (make-pong-frame (frame-data frame)) client)
          (loop fragments type))
         ((pong-frame? frame) ; silently ignore pongs
          (loop fragments type))
         ((first-fragment-frame? frame) ; begin accumulating fragments
          (loop (list frame) (frame-type frame)))
         ((final-fragment-frame? frame) ; concatenate all fragments
          (handle-data-frame type (frame-concatenate (reverse fragments)))
          (loop '() #f))
         ((fragment-frame? frame) ; add a fragment
          (loop (cons frame fragments) type))
         ((data-frame? frame) ; unfragmented data frame
          (handle-data-frame (frame-type frame) (frame-data frame))
          (loop '() #f)))))))
