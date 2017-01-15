;;; 8sync --- Asynchronous programming for Guile
;;; Copyright © 2015 David Thompson <davet@gnu.org>
;;; Copyright © 2017 Christopher Allan Webber <cwebber@dustycloud.org>
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

;;; Commentary:
;;
;; WebSocket server.
;; Adapted from guile-websocket.
;;
;;; Code:

(define-module (8sync systems websocket)
  #:use-module (8sync systems websocket client)
  #:use-module (8sync systems websocket server)
  #:export (<websocket-server>
            <websocket-client>))
