#!/usr/bin/guile \
-s
!#

(define-module (tests test-core)
  #:use-module (srfi srfi-64)
  #:use-module (ice-9 q)
  #:use-module (ice-9 receive)
  #:use-module (eightsync agenda))

(test-begin "tests")



;;; Helpers
;;; =======

(define (speak-it)
  (let ((messages '()))
    (lambda* (#:optional message)
      (if message (set! messages (append messages (list message))))
      messages)))


;; Timer tests
;; ===========

(test-assert (time= '(1 . 1) '(1 . 1)))
(test-assert (not (time= '(1 . 1) '(1 . 0))))
(test-assert (not (time= '(0 . 1) '(1 . 1))))

(test-assert (time< '(1 . 1) '(1 . 2)))
(test-assert (time< '(7 . 2) '(8 . 2)))
(test-assert (not (time< '(7 . 2) '(7 . 2))))
(test-assert (not (time< '(7 . 8) '(7 . 2))))
(test-assert (not (time< '(8 . 2) '(7 . 2))))

(let ((tdelta (make-time-delta 8)))
  (test-assert (time-delta? tdelta))
  (test-eqv (time-delta-sec tdelta) 8)
  (test-eqv (time-delta-usec tdelta) 0)
  (test-equal
      (time-delta+ '(2 . 3) tdelta)
    '(10 . 3)))

(let ((tdelta (make-time-delta 10 1)))
  (test-assert (time-delta? tdelta))
  (test-eqv (time-delta-sec tdelta) 10)
  (test-eqv (time-delta-usec tdelta) 1)
  (test-equal
      (time-delta+ '(2 . 3) tdelta)
    '(12 . 4)))



;;; Schedule tests
;;; ==============

;; helpers
(define (assert-times-expected time-segments expected-times)
  (test-equal (map time-segment-time time-segments)
    expected-times))

(define a-proc (const 'a))
(define b-proc (const 'b))
(define c-proc (const 'c))
(define d-proc (const 'd))
(define e-proc (const 'e))
(define f-proc (const 'f))

(define sched (make-schedule))
(test-assert (schedule-empty? sched))

;; Add a segment at (10 . 0)
(schedule-add! sched 10 a-proc)
(test-assert (not (schedule-empty? sched)))
(test-equal (length (schedule-segments sched)) 1)
(test-equal (time-segment-time (car (schedule-segments sched)))
  '(10 . 0))
(test-equal (q-length (time-segment-queue (car (schedule-segments sched))))
  1)
(test-eq (q-front (time-segment-queue (car (schedule-segments sched))))
  a-proc)
(test-eq (q-rear (time-segment-queue (car (schedule-segments sched))))
  a-proc)
(test-eq ((q-front (time-segment-queue (car (schedule-segments sched)))))
  'a) ;; why not
(assert-times-expected (schedule-segments sched)
                       '((10 . 0)))

;; Add another segment at (10 . 0)
(schedule-add! sched '(10 . 0) b-proc)
(test-assert (not (schedule-empty? sched)))
(test-equal (length (schedule-segments sched)) 1)
(test-equal (time-segment-time (car (schedule-segments sched)))
  '(10 . 0))
(test-equal (q-length (time-segment-queue (car (schedule-segments sched))))
  2)
(test-eq (q-front (time-segment-queue (car (schedule-segments sched))))
  a-proc)
(test-eq (q-rear (time-segment-queue (car (schedule-segments sched))))
  b-proc)
(assert-times-expected (schedule-segments sched)
                       '((10 . 0)))

;; Add a segment to (11 . 0), (8 . 1) and (10 . 10)
(schedule-add! sched 11 c-proc)
(schedule-add! sched '(8 . 1) d-proc)
(schedule-add! sched '(10 . 10) e-proc)
(test-assert (not (schedule-empty? sched)))
(test-equal (length (schedule-segments sched)) 4)
(assert-times-expected (schedule-segments sched)
                       '((8 . 1) (10 . 0) (10 . 10) (11 . 0)))

;; Splitting 
(define (test-split-at schedule time expected-before expected-after)
  (receive (segments-before segments-after)
      (schedule-segments-split schedule time)
    (assert-times-expected segments-before expected-before)
    (assert-times-expected segments-after expected-after)))

(test-split-at sched 0
               '()
               '((8 . 1) (10 . 0) (10 . 10) (11 . 0)))
(test-split-at sched '(8 . 0)
               '()
               '((8 . 1) (10 . 0) (10 . 10) (11 . 0)))
(test-split-at sched '(8 . 1)
               '((8 . 1))
               '((10 . 0) (10 . 10) (11 . 0)))
(test-split-at sched 9
               '((8 . 1))
               '((10 . 0) (10 . 10) (11 . 0)))
(test-split-at sched 10
               '((8 . 1) (10 . 0))
               '((10 . 10) (11 . 0)))
(test-split-at sched 9000
               '((8 . 1) (10 . 0) (10 . 10) (11 . 0))
               '())
(test-split-at sched '(9000 . 1)    ; over nine thousaaaaaaand
               '((8 . 1) (10 . 0) (10 . 10) (11 . 0))
               '())

;; Break off half of those and do some tests on them
(define some-extracted
  (schedule-extract-until! sched 10))
(assert-times-expected some-extracted '((8 . 1) (10 . 0)))
(assert-times-expected (schedule-segments sched) '((10 . 10) (11 . 0)))
(define first-extracted-queue
  (time-segment-queue (car some-extracted)))
(define second-extracted-queue
  (time-segment-queue (cadr some-extracted)))
(test-assert (not (q-empty? first-extracted-queue)))
(test-equal ((deq! first-extracted-queue)) 'd)
(test-assert (q-empty? first-extracted-queue))

(test-assert (not (q-empty? second-extracted-queue)))
(test-equal ((deq! second-extracted-queue)) 'a)
(test-equal ((deq! second-extracted-queue)) 'b)
(test-assert (q-empty? second-extracted-queue))

;; Add one more and test flattening to a queue
(test-assert (not (schedule-empty? sched)))
(schedule-add! sched '(10 . 10) f-proc)
(define remaining-segments
  (schedule-extract-until! sched '(9000 . 1)))
(test-assert (schedule-empty? sched))
(define some-queue (make-q))
(enq! some-queue (const 'ho-ho))
(enq! some-queue (const 'ha-ha))
(add-segments-contents-to-queue! remaining-segments some-queue)
(test-assert (not (q-empty? some-queue)))
(test-equal 'ho-ho ((deq! some-queue)))
(test-equal 'ha-ha ((deq! some-queue)))
(test-equal 'e ((deq! some-queue)))
(test-equal 'f ((deq! some-queue)))
(test-equal 'c ((deq! some-queue)))
(test-assert (q-empty? some-queue))

;; ... whew!

;; Run/wrap request stuff
;; ----------------------

(let ((wrapped (wrap (+ 1 2))))
  (test-assert (procedure? wrapped))
  (test-equal (wrapped) 3))

(let ((run-two-squared (run-it (lambda () (* 2 2)))))
  (test-assert (run-request? run-two-squared))
  (test-assert (procedure? (run-request-proc run-two-squared)))
  (test-equal ((run-request-proc run-two-squared)) 4)
  (test-eq (run-request-when run-two-squared) #f))

(let ((run-two-squared (run-it (lambda () (* 2 2)) '(88 . 0))))
  (test-assert (run-request? run-two-squared))
  (test-assert (procedure? (run-request-proc run-two-squared)))
  (test-equal ((run-request-proc run-two-squared)) 4)
  (test-equal (run-request-when run-two-squared) '(88 . 0)))

(let ((run-two-squared (run (* 2 2))))
  (test-assert (run-request? run-two-squared))
  (test-assert (procedure? (run-request-proc run-two-squared)))
  (test-equal ((run-request-proc run-two-squared)) 4)
  (test-eq (run-request-when run-two-squared) #f))

(let ((run-two-squared (run-at (* 2 2) '(88 . 0))))
  (test-assert (run-request? run-two-squared))
  (test-assert (procedure? (run-request-proc run-two-squared)))
  (test-equal ((run-request-proc run-two-squared)) 4)
  (test-equal (run-request-when run-two-squared) '(88 . 0)))


;;; %run, %sync and friends tests
;;; -----------------------------

(define (test-%run-and-friends async-request expected-when)
  (let* ((fake-kont (speak-it))
         (run-request ((@@ (eightsync agenda) setup-async-request)
                       fake-kont async-request)))
    (test-equal (car async-request) '*async-request*)
    (test-equal (run-request-when run-request) expected-when)
    ;; we're using speaker as a fake continuation ;p
    ((run-request-proc run-request))
    (test-equal (fake-kont)
                '("applesauce"))))

(test-%run-and-friends (%run (string-concatenate '("apple" "sauce")))
                       #f)

(test-%run-and-friends (%run-at (string-concatenate '("apple" "sauce"))
                                '(8 . 0))
                       '(8 . 0))

(test-%run-and-friends (%run-delay (string-concatenate '("apple" "sauce"))
                                   8)
                       ;; whoa, I'm surprised equal? can
                       ;; compare records like this
                       (tdelta 8 0))

;; TODO: test %port-request
;; TODO: test %sync and friends!


;;; Agenda tests
;;; ------------

;; helpers

(define (true-after-n-times n)
  (let ((count 0))
    (lambda _
      (set! count (+ count 1))
      (if (>= count n) #t #f))))

;; the dummy test

(define speaker (speak-it))

(define (dummy-func)
  (speaker "I'm a dummy\n"))

(define (run-dummy)
  (speaker "I bet I can make you say you're a dummy!\n")
  (run-it dummy-func))

(let ((q (make-q)))
  (set! speaker (speak-it))  ; reset the speaker
  (enq! q run-dummy)
  (start-agenda (make-agenda #:queue q)
                #:stop-condition (true-after-n-times 2))
  (test-equal (speaker)
    '("I bet I can make you say you're a dummy!\n"
      "I'm a dummy\n")))

;; should only do the first one after one round though
(let ((q (make-q)))
  (set! speaker (speak-it))  ; reset the speaker
  (enq! q run-dummy)
  (start-agenda (make-agenda #:queue q)
                #:stop-condition (true-after-n-times 1))
  (test-equal (speaker)
    '("I bet I can make you say you're a dummy!\n")))

;; delimited continuation tests

(define (return-monkey)
  (speaker "(Hint, it's a monkey...)\n")
  'monkey)

(define (talk-about-the-zoo)
  (speaker "Today I went to the zoo and I saw...\n")
  (speaker
   (string-concatenate
    `("A " ,(symbol->string (%sync (%run (return-monkey)))) "!\n"))))

(let ((q (make-q)))
  (set! speaker (speak-it))
  (enq! q talk-about-the-zoo)
  ;; (enq! q talk-about-the-zoo-but-wait)
  (start-agenda (make-agenda #:queue q)
                #:stop-condition (true-after-n-times 10))
  (test-equal (speaker)
              '("Today I went to the zoo and I saw...\n"
                "(Hint, it's a monkey...)\n"
                "A monkey!\n")))

;; End tests

(test-end "tests")
;; (test-exit)

