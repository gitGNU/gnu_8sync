(define-module (loopy agenda)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-9 gnu)
  #:use-module (ice-9 q)
  #:use-module (ice-9 match)
  #:use-module (ice-9 receive)
  #:export (make-agenda
            agenda?
            agenda-queue agenda-prompt-tag
            agenda-port-pmapping agenda-schedule
            
            make-async-prompt-tag

            make-time-segment
            time-segment?
            time-segment-time time-segment-queue

            time-< time-= time-<=

            make-schedule
            schedule-add! schedule-empty?
            schedule-segments

            schedule-segments-until schedule-extract-until!

            make-port-mapping
            port-mapping-set! port-mapping-remove!
            port-mapping-empty? port-mapping-non-empty?

            %current-agenda
            start-agenda agenda-run-once))

;; @@: Using immutable agendas here, so wouldn't it make sense to
;;   replace this queue stuff with using pfds based immutable queues?


;;; Agenda definition
;;; =================

;;; The agenda consists of:
;;;  - a queue of immediate items to handle
;;;  - sheduled future events to be added to a future queue
;;;  - a tag by which running processes can escape for some asynchronous
;;;    operation (from which they can be returned later)
;;;  - a mapping of ports to various handler procedures
;;;
;;; The goal, eventually, is for this all to be immutable and functional.
;;; However, we aren't there yet.  Some tricky things:
;;;  - The schedule needs to be immutable, yet reasonably efficient.
;;;  - Need to use immutable queues (ijp's pfds library?)
;;;  - Modeling reading from ports as something repeatable,
;;;    and with reasonable separation from functional components?

(define-immutable-record-type <agenda>
  (make-agenda-intern queue prompt-tag port-mapping schedule)
  agenda?
  (queue agenda-queue)
  (prompt-tag agenda-prompt-tag)
  (port-mapping agenda-port-mapping)
  (schedule agenda-schedule))

(define (make-async-prompt-tag)
  (make-prompt-tag "prompt"))

(define* (make-agenda #:key
                      (queue (make-q))
                      (prompt (make-prompt-tag))
                      (port-mapping (make-port-mapping))
                      (schedule (make-schedule)))
  (make-agenda-intern queue prompt port-mapping schedule))



;;; Schedule
;;; ========

;;; This is where we handle timed events for the future

;; This section totally borrows from SICP
;; <3 <3 <3

;; NOTE: time is a cons of (seconds . microseconds)

(define-record-type <time-segment>
  (make-time-segment-intern time queue)
  time-segment?
  (time time-segment-time)
  (queue time-segment-queue))

(define (time-segment-right-format time)
  (match time
    ;; time is already a cons of second and microsecnd
    (((? integer? s) . (? integer? u)) time)
    ;; time was just an integer (just the second)
    ((? integer? _) (cons time 0))
    (_ (throw 'invalid-time "Invalid time" time))))

(define* (make-time-segment time #:optional (queue (make-q)))
  (make-time-segment-intern time queue))

(define (time-< time1 time2)
  (cond ((< (car time1)
            (car time2))
         #t)
        ((and (= (car time1)
                 (car time2))
              (< (cdr time1)
                 (cdr time2)))
         #t)
        (else #f)))

(define (time-= time1 time2)
  (and (= (car time1) (car time2))
       (= (cdr time1) (cdr time2))))

(define (time-<= time1 time2)
  (or (time-< time1 time2)
      (time-= time1 time2)))

(define-record-type <schedule>
  (make-schedule-intern segments)
  schedule?
  (segments schedule-segments set-schedule-segments!))

(define* (make-schedule #:optional segments)
  (make-schedule-intern (or segments '())))

;; TODO: This code is reasonably easy to read but it
;;   mutates AND is worst case of O(n) in both space and time :(
;;   but at least it'll be reasonably easy to refactor to
;;   a more functional setup?
(define (schedule-add! time proc schedule)
  (let ((time (time-segment-right-format time)))
    (define (new-time-segment)
      (let ((new-segment
             (make-time-segment time)))
        (enq! (time-segment-queue new-segment) proc)
        new-segment))
    (define (loop segments)
      (define (segment-equals-time? segment)
        (time-= time (time-segment-time segment)))

      (define (segment-more-than-time? segment)
        (time-< time (time-segment-time segment)))

      ;; We could switch this out to be more mutate'y
      ;; and avoid the O(n) of space... is that over-optimizing?
      (match segments
        ;; If we're at the end of the list, time to make a new
        ;; segment...
        ('() (cons (new-time-segment) '()))
        ;; If the segment's time is exactly our time, good news
        ;; everyone!  Let's append our stuff to its queue
        (((? segment-equals-time? first) rest ...)
         (enq! (time-segment-queue first) proc)
         segments)
        ;; If the first segment is more than our time,
        ;; ours belongs before this one, so add it and
        ;; start consing our way back
        (((? segment-more-than-time? first) rest ...)
         (cons (new-time-segment) segments))
        ;; Otherwise, build up recursive result
        ((first rest ... )
         (cons first (loop rest)))))
    (set-schedule-segments!
     schedule
     (loop (schedule-segments schedule)))))

(define (schedule-empty? schedule)
  (eq? (schedule-segments schedule) '()))

(define (schedule-segments-until schedule time)
  "Does a multiple value return of time segments before/at and after TIME"
  (let ((time (time-segment-right-format time)))
    (define (segment-is-now? segment)
      (time-= (time-segment-time segment) time))
    (define (segment-is-before-now? segment)
      (time-< (time-segment-time segment) time))

    (let loop ((segments-before '())
               (segments-left (schedule-segments schedule)))
      (match segments-left
        ;; end of the line, return
        ('()
         (values (reverse segments-before) '()))

        ;; It's right now, so time to stop, but include this one in before
        ;; but otherwise return
        (((? segment-is-now? first) rest ...)
         (values (reverse (cons first segments-before)) rest))

        ;; This is prior or at now, so add it and keep going
        (((? segment-is-before-now? first) rest ...)
         (loop (cons first segments-before) rest))

        ;; Otherwise it's past now, just return what we have
        (segments-after
         (values segments-before segments-after))))))

(define (schedule-extract-until! schedule time)
  "Extract all segments until TIME from SCHEDULE, and pop old segments off"
  (receive (segments-before segments-after)
      (schedule-split-segments-until schedule time)
    (set-schedule-segments! schedule segments-after)
    segments-before))



;;; Port handling
;;; =============

(define (make-port-mapping)
  (make-hash-table))

(define* (port-mapping-set! port-mapping port #:optional read write except)
  "Sets port-mapping for reader / writer / exception handlers"
  (if (not (or read write except))
      (throw 'no-handlers-given "No handlers given for port" port))
  (hashq-set! port-mapping port
              `#(,read ,write ,except)))

(define (port-mapping-remove! port-mapping port)
  (hashq-remove! port-mapping port))

;; TODO: This is O(n), I'm pretty sure :\
;; ... it might be worthwhile for us to have a
;;   port-mapping record that keeps a count of how many
;;   handlers (maybe via a promise?)
(define (port-mapping-empty? port-mapping)
  "Is this port mapping empty?"
  (eq? (hash-count (const #t) port-mapping) 0))

(define (port-mapping-non-empty? port-mapping)
  "Whether this port-mapping contains any elements"
  (not (port-mapping-empty? port-mapping)))



;;; Execution of agenda, and current agenda
;;; =======================================

(define %current-agenda (make-parameter #f))

(define* (start-agenda agenda #:optional stop-condition)
  (let loop ((agenda agenda))
    (let ((new-agenda   
           ;; @@: Hm, maybe here would be a great place to handle
           ;;   select'ing on ports.
           ;;   We could compose over agenda-run-once and agenda-read-ports
           (parameterize ((%current-agenda agenda))
             (agenda-run-once agenda))))
      (if (and stop-condition (stop-condition agenda))
          'done
          (loop new-agenda)))))

(define (agenda-run-once agenda)
  "Run once through the agenda, and produce a new agenda
based on the results"
  (define (call-proc proc)
    (call-with-prompt
        (agenda-prompt-tag agenda)
      (lambda ()
        (proc))
      ;; TODO
      (lambda (k) k)))

  (let ((queue (agenda-queue agenda))
        (next-queue (make-q)))
    (while (not (q-empty? queue))
      (let* ((proc (q-pop! queue))
             (proc-result (call-proc proc))
             (enqueue
              (lambda (new-proc)
                (enq! next-queue new-proc))))
        ;; @@: We might support delay-wrapped procedures here
        (match proc-result
          ((? procedure? new-proc)
           (enqueue new-proc))
          (((? procedure? new-procs) ...)
           (for-each
            (lambda (new-proc)
              (enqueue new-proc))
            new-procs))
          ;; do nothing
          (_ #f))))
    ;; TODO: Selecting on ports would happen here?
    ;; Return new agenda, with next queue set
    (set-field agenda (agenda-queue) next-queue)))
