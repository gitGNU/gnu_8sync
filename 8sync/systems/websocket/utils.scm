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
;; WebSocket utilities.
;;
;;; Code:

(define-module (8sync systems websocket utils)
  #:use-module (rnrs bytevectors)
  #:use-module (8sync contrib base64)
  #:use-module (8sync contrib sha-1)
  #:export (%handshake-guid
            make-accept-key))

;; See section 1.3 - Opening Handshake
(define %handshake-guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")

(define (make-accept-key client-key)
  "Return a WebSocket accept key based on CLIENT-KEY, a base64 encoded
string."
  (base64-encode
   (sha-1->bytevector
    (sha-1
     (string->utf8
      (string-append client-key %handshake-guid))))))
