;;;; Main Trampoline Module - tying everything together
;;;;
;;;; This module provides the top-level entry points for the
;;;; trampoline-based async effect runtime.

(in-package #:coalton-library/effects/runtime)

(named-readtables:in-readtable coalton:coalton)

;;;
;;; Top-Level Runners
;;;
;;; These are the main entry points for running effectful computations.
;;;

(coalton-toplevel

  (declare run ((Step :a) -> (Result String :a)))
  (define (run step)
    "Run a step computation to completion.
Uses a scheduler internally for proper trampoline execution.
Returns Ok with the result or Err with an error message."
    (run-with-scheduler step))

  (declare run! ((Step :a) -> :a))
  (define (run! step)
    "Run a step computation to completion, erroring on failure.
Unwraps the result, signaling an error if the computation failed."
    (match (run step)
      ((Ok v) v)
      ((Err msg) (error msg))))

  (declare run-async ((Scheduler -> (Step Unit)) -> (Result String Unit)))
  (define (run-async body)
    "Run an async computation that needs the scheduler.
The body receives a scheduler for spawning fibers.
Integrates with cl-async event loop if available.
Note: This is a simplified implementation that returns Unit."
    (progn
      (with-async-runtime
       (fn (sched)
         (let ((step (body sched)))
           (let ((_fiber (scheduler-spawn! sched step)))
             ;; Return fiber for later result extraction
             Unit))))
      ;; After event loop completes, extract result
      ;; This is a simplification - real implementation would
      ;; need to return the fiber and have caller extract result
      (Ok Unit))))


;;;
;;; Step Builders
;;;
;;; Convenience functions for building step computations.
;;;

(coalton-toplevel

  (declare step ((:a -> (Step :b)) -> :a -> (Step :b)))
  (define (step f x)
    "Apply a step-returning function to a value.
Wraps the call in StepContinue for trampolining."
    (StepContinue (fn () (f x))))

  (declare step-lift ((:a -> :b) -> :a -> (Step :b)))
  (define (step-lift f x)
    "Lift a pure function into a step."
    (StepDone (f x)))

  (declare step-when (Boolean -> (Step Unit) -> (Step Unit)))
  (define (step-when condition step)
    "Execute step only if condition is true."
    (if condition
        step
        (StepDone Unit)))

  (declare step-unless (Boolean -> (Step Unit) -> (Step Unit)))
  (define (step-unless condition step)
    "Execute step only if condition is false."
    (if condition
        (StepDone Unit)
        step))

  (declare step-repeat (UFix -> (Step Unit) -> (Step Unit)))
  (define (step-repeat n step)
    "Repeat a step n times."
    (if (<= n 0)
        (StepDone Unit)
        (>>= step (fn (_) (step-repeat (- n 1) step)))))

  (declare step-while ((Unit -> Boolean) -> (Step Unit) -> (Step Unit)))
  (define (step-while condition body)
    "Execute body while condition returns true.
Yields between iterations for fairness."
    (if (condition)
        (>>= body
             (fn (_)
               (>>= (yield-now)
                    (fn (_)
                      (step-while condition body)))))
        (StepDone Unit)))

  (declare step-for-each ((:a -> (Step Unit)) -> (List :a) -> (Step Unit)))
  (define (step-for-each f items)
    "Apply f to each item in sequence."
    (match items
      ((Nil) (StepDone Unit))
      ((Cons x xs)
       (>>= (f x)
            (fn (_) (step-for-each f xs))))))

  (declare step-fold ((:b -> :a -> (Step :b)) -> :b -> (List :a) -> (Step :b)))
  (define (step-fold f init items)
    "Fold over items with a step-returning function."
    (match items
      ((Nil) (StepDone init))
      ((Cons x xs)
       (>>= (f init x)
            (fn (acc) (step-fold f acc xs)))))))


;;;
;;; Effect Performers
;;;
;;; Functions to perform effects within step computations.
;;;

(coalton-toplevel

  (declare perform-state-get (Unit -> (Step :s)))
  (define (perform-state-get)
    "Perform a state get effect."
    (cont-perform state-get-op StepDone))

  (declare perform-state-put (:s -> (Step Unit)))
  (define (perform-state-put new-state)
    "Perform a state put effect."
    (cont-perform (state-put-op new-state) (fn (_) (StepDone Unit))))

  (declare perform-reader-ask (Unit -> (Step :r)))
  (define (perform-reader-ask)
    "Perform a reader ask effect."
    (cont-perform reader-ask-op StepDone))

  (declare perform-writer-tell (:w -> (Step Unit)))
  (define (perform-writer-tell output)
    "Perform a writer tell effect."
    (cont-perform (writer-tell-op output) (fn (_) (StepDone Unit))))

  (declare perform-fail (String -> (Step :a)))
  (define (perform-fail msg)
    "Perform a failure effect."
    (cont-perform (fail-op msg) StepDone)))


;;;
;;; Debug Utilities
;;;

(coalton-toplevel

  (declare step-trace (String -> (Step Unit)))
  (define (step-trace msg)
    "Print a trace message (for debugging)."
    (StepContinue
     (fn ()
       (progn
         (lisp Unit (msg) (cl:format cl:t "~A~%" msg) 'coalton::unit/unit)
         (StepDone Unit)))))

  (declare step-trace-value (String -> :a -> (Step :a)))
  (define (step-trace-value label value)
    "Print a traced value and return it."
    (StepContinue
     (fn ()
       (progn
         (lisp Unit (label value) (cl:format cl:t "~A: ~S~%" label value) 'coalton::unit/unit)
         (StepDone value))))))


;;;
;;; Integration with Existing Effects
;;;
;;; Utilities for converting between the trampoline runtime
;;; and the existing condition/restart-based effects.
;;;

(coalton-toplevel

  (declare step-from-thunk ((Unit -> :a) -> (Step :a)))
  (define (step-from-thunk thunk)
    "Create a step from a thunk.
Catches CL errors and converts them to StepFail."
    (StepContinue
     (fn ()
       (lisp (Step :a) (thunk)
         (cl:handler-case
             (StepDone (call-coalton-function thunk 'coalton::unit/unit))
           (cl:error (e)
             (StepFail (cl:princ-to-string e))))))))

  (declare step-protect ((Step :a) -> (Unit -> (Step Unit)) -> (Step :a)))
  (define (step-protect body cleanup)
    "Run body with cleanup guaranteed to run.
Like unwind-protect for steps."
    (catch-step body
                ;; Success: run cleanup then return result
                (fn (v)
                  (>>= (cleanup Unit)
                       (fn (_) (StepDone v))))
                ;; Error: run cleanup then re-fail
                (fn (msg)
                  (>>= (cleanup Unit)
                       (fn (_) (StepFail msg)))))))
