;;;; Continuation types for trampoline-based execution
;;;;
;;;; This module defines the core continuation types that enable
;;;; stack-safe execution through trampolining. Each step of computation
;;;; returns a Step value that the trampoline interprets.

(in-package #:coalton-library/effects/runtime)

;;;
;;; CL Structures (defined before coalton readtable)
;;;
;;; These structures hold the existential type data for perform and async steps.
;;;

(cl:defstruct effect-op-internal
  "Internal structure for effect operations."
  (tag cl:nil :type cl:symbol)
  (value cl:nil :type cl:t))

(cl:defstruct step-perform-internal
  "Internal structure for perform steps."
  (op cl:nil :type (cl:or cl:null effect-op-internal))
  (continuation cl:nil :type (cl:or cl:null cl:function)))

(cl:defstruct step-async-internal
  "Internal structure for async steps."
  (register cl:nil :type (cl:or cl:null cl:function))
  (continuation cl:nil :type (cl:or cl:null cl:function)))

;;;
;;; Now switch to Coalton mode
;;;

(named-readtables:in-readtable coalton:coalton)

;;;
;;; Effect Operation Type
;;;
;;; Represents an effect operation that needs to be handled.
;;; The tag identifies the effect type, and value carries the operation data.
;;;

(coalton-toplevel

  ;; Effect operation - represents an effect to be performed
  (repr :native effect-op-internal)
  (define-type EffectOp
    "An effect operation with a tag identifying the effect type and a value.")

  (declare make-effect-op (Symbol -> :a -> EffectOp))
  (define (make-effect-op tag value)
    "Create an effect operation with a tag and value."
    (lisp EffectOp (tag value)
      (make-effect-op-internal :tag tag :value value)))

  (declare effect-op-tag (EffectOp -> Symbol))
  (define (effect-op-tag op)
    "Get the tag of an effect operation."
    (lisp Symbol (op)
      (effect-op-internal-tag op)))

  (declare effect-op-value (EffectOp -> :a))
  (define (effect-op-value op)
    "Get the value of an effect operation. Caller must ensure type safety."
    (lisp :a (op)
      (effect-op-internal-value op))))


;;;
;;; Step Type
;;;
;;; Represents one step of a trampolined computation.
;;; The trampoline loop interprets these steps until reaching Done or Fail.
;;;
;;; Note: StepPerform and StepAsync involve existential types (the type of the
;;; handler result is hidden). We handle this by storing the continuation as
;;; an opaque function and using LISP FFI for application.
;;;

(coalton-toplevel

  ;; Wrapper types for existential steps
  (repr :native step-perform-internal)
  (define-type StepPerformData
    "Internal: data for a perform step")

  (repr :native step-async-internal)
  (define-type StepAsyncData
    "Internal: data for an async step")

  (define-type (Step :a)
    "A single step in a trampolined computation.

StepContinue: Continue with the next thunk (enables trampolining)
StepYield: Yield control to scheduler, continue with thunk later
StepPerform: Perform an effect operation, resume with handler result
StepDone: Computation completed successfully with value
StepFail: Computation failed with error message
StepAsync: Suspend for async I/O, resume when callback fires"

    ;; Continue execution with next step (core trampoline mechanism)
    (StepContinue (Unit -> (Step :a)))

    ;; Yield control to scheduler
    (StepYield (Unit -> (Step :a)))

    ;; Perform an effect operation (existential type hidden in StepPerformData)
    (StepPerform StepPerformData)

    ;; Computation completed with value
    (StepDone :a)

    ;; Computation failed with error
    (StepFail String)

    ;; Suspend for async I/O (existential type hidden in StepAsyncData)
    (StepAsync StepAsyncData)))


;;;
;;; Continuation Constructors
;;;
;;; Smart constructors for creating Step values.
;;;

(coalton-toplevel

  (declare cont-pure (:a -> (Step :a)))
  (define (cont-pure value)
    "Create a completed step with a value."
    (StepDone value))

  (declare cont-fail (String -> (Step :a)))
  (define (cont-fail message)
    "Create a failed step with an error message."
    (StepFail message))

  (declare cont-yield ((Unit -> (Step :a)) -> (Step :a)))
  (define (cont-yield thunk)
    "Create a yield step that will continue with thunk."
    (StepYield thunk))

  (declare cont-perform (EffectOp -> (:b -> (Step :a)) -> (Step :a)))
  (define (cont-perform op k)
    "Create a step that performs an effect and continues with k."
    (lisp (Step :a) (op k)
      (StepPerform
       (make-step-perform-internal
        :op op
        :continuation (cl:lambda (result)
                        (call-coalton-function k result))))))

  (declare cont-async (((:b -> Unit) -> Unit) -> (:b -> (Step :a)) -> (Step :a)))
  (define (cont-async register k)
    "Create an async step that suspends until callback fires."
    (lisp (Step :a) (register k)
      (StepAsync
       (make-step-async-internal
        :register (cl:lambda (callback)
                    (call-coalton-function
                     register
                     (cl:lambda (result)
                       (cl:funcall callback result))))
        :continuation (cl:lambda (result)
                        (call-coalton-function k result)))))))


;;;
;;; Accessors for existential step data
;;;

(coalton-toplevel

  (declare step-perform-op (StepPerformData -> EffectOp))
  (define (step-perform-op data)
    "Get the effect operation from perform data."
    (lisp EffectOp (data)
      (step-perform-internal-op data)))

  (declare step-perform-resume (StepPerformData -> :a -> (Step :b)))
  (define (step-perform-resume data value)
    "Resume a perform step with a value."
    (lisp (Step :b) (data value)
      (cl:funcall (step-perform-internal-continuation data) value)))

  (declare step-async-register (StepAsyncData -> (:a -> Unit) -> Unit))
  (define (step-async-register data callback)
    "Register a callback for async completion."
    (progn
      (lisp :a (data callback)
        (cl:funcall (step-async-internal-register data)
                    (cl:lambda (result)
                      (call-coalton-function callback result))))
      Unit))

  (declare step-async-resume (StepAsyncData -> :a -> (Step :b)))
  (define (step-async-resume data value)
    "Resume an async step with a value."
    (lisp (Step :b) (data value)
      (cl:funcall (step-async-internal-continuation data) value))))


;;;
;;; Continuation Combinators
;;;
;;; Monadic operations for sequencing Steps.
;;;

(coalton-toplevel

  (declare cont-bind ((Step :a) -> (:a -> (Step :b)) -> (Step :b)))
  (define (cont-bind step f)
    "Sequence two steps: run first step, then pass result to f.
This is the monadic bind for continuations."
    (match step
      ;; Trampoline: wrap in StepContinue to avoid deep recursion
      ((StepContinue thunk)
       (StepContinue
        (fn () (cont-bind (thunk) f))))

      ;; Propagate yield, then bind
      ((StepYield thunk)
       (StepYield
        (fn () (cont-bind (thunk) f))))

      ;; Propagate perform, wrapping continuation
      ((StepPerform data)
       (lisp (Step :b) (data f)
         (StepPerform
          (make-step-perform-internal
           :op (step-perform-internal-op data)
           :continuation (cl:lambda (result)
                           (cont-bind
                            (cl:funcall (step-perform-internal-continuation data) result)
                            f))))))

      ;; Apply f to completed value
      ((StepDone value)
       ;; Wrap in StepContinue for trampolining
       (StepContinue (fn () (f value))))

      ;; Propagate failure
      ((StepFail msg)
       (StepFail msg))

      ;; Propagate async, wrapping continuation
      ((StepAsync data)
       (lisp (Step :b) (data f)
         (StepAsync
          (make-step-async-internal
           :register (step-async-internal-register data)
           :continuation (cl:lambda (result)
                           (cont-bind
                            (cl:funcall (step-async-internal-continuation data) result)
                            f))))))))

  (declare cont-map ((:a -> :b) -> (Step :a) -> (Step :b)))
  (define (cont-map f step)
    "Map a function over a step's result."
    (cont-bind step (fn (x) (cont-pure (f x)))))

  (declare cont-ap ((Step (:a -> :b)) -> (Step :a) -> (Step :b)))
  (define (cont-ap sf sa)
    "Apply a step containing a function to a step containing a value."
    (cont-bind sf (fn (f) (cont-map f sa)))))


;;;
;;; Trampoline Runner
;;;
;;; Executes a computation synchronously by trampolining.
;;; Does not handle effects or async - those require the full scheduler.
;;;

(coalton-toplevel

  (declare run-sync ((Step :a) -> (Result String :a)))
  (define (run-sync step)
    "Run a step synchronously, trampolining to avoid stack overflow.
Returns Err if the step fails or attempts async/effects."
    (match step
      ;; Trampoline: tail-call with thunk result
      ((StepContinue thunk)
       (run-sync (thunk)))

      ;; Yield just continues in sync mode
      ((StepYield thunk)
       (run-sync (thunk)))

      ;; Effects not handled in sync mode
      ((StepPerform _)
       (Err "Cannot perform effects in synchronous mode"))

      ;; Success
      ((StepDone value)
       (Ok value))

      ;; Failure
      ((StepFail msg)
       (Err msg))

      ;; Async not handled in sync mode
      ((StepAsync _)
       (Err "Cannot perform async operations in synchronous mode")))))


;;;
;;; Step Monad Instance
;;;
;;; Allows using Step with standard monadic combinators.
;;;

(coalton-toplevel

  (define-instance (Functor Step)
    (define (map f step)
      (cont-map f step)))

  (define-instance (Applicative Step)
    (define (pure x)
      (cont-pure x))
    (define (liftA2 f a b)
      (cont-bind a (fn (x) (cont-map (f x) b)))))

  (define-instance (Monad Step)
    (define (>>= step f)
      (cont-bind step f))))
