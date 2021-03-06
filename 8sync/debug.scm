;;; 8sync --- Asynchronous programming for Guile
;;; Copyright © 2016, 2017 Christopher Allan Webber <cwebber@dustycloud.org>
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

(define-module (8sync debug)
  #:use-module (oop goops)
  #:use-module (8sync actors)
  #:export (hive-resolve-local-actor
            actor-hive

            bootstrap-actor-gimmie
            bootstrap-actor-gimmie*))


;;; Expose not normally exposed methods
;;; ===================================

;; "private" kind of a misnomer
(define-syntax-rule (expose private-var)
  (define private-var
    (@@ (8sync actors) private-var)))

(expose hive-resolve-local-actor)
(expose actor-hive)



;;; Some utilities
;;; =============

(define (bootstrap-actor-gimmie hive actor-class . init)
  "Create an actor on the hive, and give us that actor.
Uses bootstrap-actor* arguments."
  (let ((actor-id (apply bootstrap-actor hive actor-class init)))
    (hive-resolve-local-actor hive actor-id)))

(define (bootstrap-actor-gimmie* hive actor-class id-cookie . init)
  "Create an actor on the hive, and give us that actor.
Uses bootstrap-actor* arguments."
  (let ((actor-id (apply bootstrap-actor*
                         hive actor-class id-cookie init)))
    (hive-resolve-local-actor hive actor-id)))


