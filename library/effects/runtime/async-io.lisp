;;;; Async I/O integration with cl-async/libuv
;;;;
;;;; This module provides integration between the fiber scheduler
;;;; and the cl-async event loop for non-blocking I/O operations.

(in-package #:coalton-library/effects/runtime)

(named-readtables:in-readtable coalton:coalton)

;;;
;;; Event Loop Integration
;;;
;;; We integrate with cl-async's event loop to handle:
;;; - Timers (delay, interval)
;;; - Idle processing (fiber scheduling)
;;; - Async callbacks
;;;

(coalton-toplevel

  (declare with-async-runtime ((Scheduler -> :a) -> :a))
  (define (with-async-runtime body)
    "Run a function with an async runtime environment.
Sets up the cl-async event loop and integrates it with the fiber scheduler.
The body function receives the scheduler and should spawn fibers."
    (lisp :a (body)
      (cl:let ((scheduler (make-scheduler-internal)))
        ;; Check if cl-async is available
        (cl:if (cl:find-package :cl-async)
               ;; cl-async available - use event loop
               (cl:let ((as-pkg (cl:find-package :cl-async)))
                 (cl:funcall
                  (cl:symbol-function (cl:intern "START-EVENT-LOOP" as-pkg))
                  (cl:lambda ()
                    ;; Set up idle handler to run scheduler steps
                    (cl:labels ((schedule-next ()
                                  (cl:funcall
                                   (cl:symbol-function (cl:intern "DELAY" as-pkg))
                                   (cl:lambda ()
                                     (cl:let ((did-work (scheduler-step! scheduler)))
                                       (cl:if (cl:or did-work
                                                     (scheduler-internal-ready-queue scheduler)
                                                     (scheduler-internal-suspended scheduler))
                                              (schedule-next)
                                              ;; Exit event loop when done
                                              (cl:funcall
                                               (cl:symbol-function (cl:intern "EXIT-EVENT-LOOP" as-pkg))))))
                                   :time 0)))
                      ;; Run the body
                      (cl:let ((result (call-coalton-function body scheduler)))
                        ;; Start scheduling
                        (schedule-next)
                        result)))))
               ;; cl-async not available - run synchronously
               (cl:progn
                 (cl:warn "cl-async not available, running synchronously")
                 (cl:let ((result (call-coalton-function body scheduler)))
                   (scheduler-run! scheduler)
                   result)))))))


;;;
;;; Timer Operations
;;;

(coalton-toplevel

  (declare delay (UFix -> (Step Unit)))
  (define (delay ms)
    "Create a step that suspends for the given number of milliseconds.
Resumes when the timer fires."
    (cont-async
     ;; Registration function - receives callback to call when timer fires
     (fn (callback)
       (lisp Unit (ms callback)
         (cl:let ((as-pkg (cl:find-package :cl-async)))
           (cl:if as-pkg
                  (cl:funcall
                   (cl:symbol-function (cl:intern "DELAY" as-pkg))
                   (cl:lambda ()
                     (call-coalton-function callback 'coalton::unit/unit))
                   :time (cl:/ ms 1000.0))
                  ;; Fallback: sleep (blocking)
                  (cl:progn
                    (cl:sleep (cl:/ ms 1000.0))
                    (call-coalton-function callback 'coalton::unit/unit))))
         'coalton::unit/unit))
     ;; Continuation after timer fires
     (fn (_) (StepDone Unit))))

  (declare delay-seconds (UFix -> (Step Unit)))
  (define (delay-seconds secs)
    "Create a step that suspends for the given number of seconds."
    (delay (* secs 1000))))


;;;
;;; Async Callback Bridge
;;;

(coalton-toplevel

  (declare async-callback (((:a -> Unit) -> Unit) -> (Step :a)))
  (define (async-callback register)
    "Create a step that suspends until an async callback is invoked.
The register function should set up whatever async operation is needed
and call the provided callback when the operation completes."
    (cont-async register (fn (result) (StepDone result))))

  (declare async-callback-with-error
           ((((Result String :a) -> Unit) -> Unit) -> (Step (Result String :a))))
  (define (async-callback-with-error register)
    "Create a step that suspends until an async callback is invoked.
The register function receives a callback that should be called with
either (Ok value) on success or (Err msg) on failure."
    (cont-async register (fn (result) (StepDone result)))))


;;;
;;; Polling Support
;;;

(coalton-toplevel

  (declare poll-until (UFix -> (Unit -> Boolean) -> (Step Unit)))
  (define (poll-until interval-ms condition)
    "Poll a condition at regular intervals until it returns True.
Yields between polls to allow other fibers to run."
    (let ((check-and-continue
           (fn ()
             (if (condition)
                 (StepDone Unit)
                 ;; Not ready yet - delay then check again
                 (cont-bind (delay interval-ms)
                            (fn (_) (poll-until interval-ms condition)))))))
      ;; Start with a yield to be fair
      (StepYield check-and-continue)))

  (declare with-timeout (UFix -> (Step :a) -> (Step (Optional :a))))
  (define (with-timeout _ms step)
    "Run a step with a timeout.
Returns None if the timeout expires before completion.
Note: This requires the full scheduler with proper cancellation support."
    ;; Simple implementation: just run the step
    ;; Full implementation would need fiber cancellation
    (cont-map Some step)))


;;;
;;; Event Loop Helpers
;;;

(coalton-toplevel

  (declare yield-now (Unit -> (Step Unit)))
  (define (yield-now)
    "Explicitly yield control to the scheduler.
Allows other fibers to run."
    (StepYield (fn () (StepDone Unit))))

  (declare yield-loop (UFix -> (Unit -> (Step :a)) -> (Step :a)))
  (define (yield-loop n body)
    "Execute body, yielding every n iterations."
    (if (<= n 0)
        (body)
        (cont-bind (yield-now)
                   (fn (_) (yield-loop (- n 1) body))))))


;;;
;;; Stream/Iterator Support
;;;

(coalton-toplevel

  (declare async-for-each ((:a -> (Step Unit)) -> (List :a) -> (Step Unit)))
  (define (async-for-each f items)
    "Apply an async function to each item in a list.
Yields between items to allow other fibers to run."
    (match items
      ((Nil) (StepDone Unit))
      ((Cons x xs)
       (cont-bind (f x)
                  (fn (_)
                    (cont-bind (yield-now)
                               (fn (_) (async-for-each f xs))))))))

  (declare async-map ((:a -> (Step :b)) -> (List :a) -> (Step (List :b))))
  (define (async-map f items)
    "Map an async function over a list, collecting results.
Yields between items."
    (match items
      ((Nil) (StepDone Nil))
      ((Cons x xs)
       (cont-bind (f x)
                  (fn (y)
                    (cont-bind (yield-now)
                               (fn (_)
                                 (cont-bind (async-map f xs)
                                            (fn (ys) (StepDone (Cons y ys))))))))))))
