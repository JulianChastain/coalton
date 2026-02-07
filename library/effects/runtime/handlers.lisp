;;;; Effect Handler Integration
;;;;
;;;; This module bridges the existing condition/restart-based effect handlers
;;;; with the fiber-based runtime. It allows handler composition and provides
;;;; a uniform interface for effect handling.

(in-package #:coalton-library/effects/runtime)

;;;
;;; Handler Type (CL structure defined before Coalton readtable)
;;;

(cl:defstruct effect-handler-internal
  "Internal structure for an effect handler."
  (tag cl:nil :type cl:symbol)
  (handler-fn cl:nil :type cl:t))  ; Can be nil or a Coalton FUNCTION-ENTRY

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel

  (repr :native effect-handler-internal)
  (define-type EffectHandler
    "An effect handler that interprets operations and produces steps.

Handlers are functions that receive:
1. The effect operation value
2. A resume continuation
And return a Step that may or may not invoke the continuation.")

  (declare handler-tag (EffectHandler -> Symbol))
  (define (handler-tag h)
    "Get the effect tag that this handler handles."
    (lisp Symbol (h)
      (effect-handler-internal-tag h)))

  (declare make-effect-handler (Symbol -> (:a -> (:b -> (Step :c)) -> (Step :c)) -> EffectHandler))
  (define (make-effect-handler tag f)
    "Create an effect handler for the given tag."
    (lisp EffectHandler (tag f)
      (make-effect-handler-internal :tag tag :handler-fn f)))

  (declare apply-handler (EffectHandler -> :a -> (:b -> (Step :c)) -> (Step :c)))
  (define (apply-handler h value resume)
    "Apply a handler to a value and resume continuation."
    (lisp (Step :c) (h value resume)
      (cl:let ((handler-fn (effect-handler-internal-handler-fn h)))
        (cl:cond
          ((cl:null handler-fn)
           (StepFail "Handler function is nil"))
          ((cl:typep handler-fn 'coalton-impl/runtime/function-entry:function-entry)
           ;; Coalton function: curried application
           (call-coalton-function
            (call-coalton-function handler-fn value)
            resume))
          (cl:t
           ;; Plain CL function (e.g. from run-state-step): direct call
           (cl:funcall handler-fn value resume)))))))


;;;
;;; Handler Constructors
;;;

(coalton-toplevel

  (declare make-handler (Symbol -> (:b -> (:c -> (Step :a)) -> (Step :a)) -> EffectHandler))
  (define (make-handler tag f)
    "Create an effect handler for operations with the given tag."
    (make-effect-handler tag f))

  (declare make-resuming-handler (Symbol -> (:b -> :c) -> EffectHandler))
  (define (make-resuming-handler tag f)
    "Create a handler that always resumes with the result of applying f.
This is the common case for simple effect interpretation."
    (make-effect-handler tag
                         (fn (value resume)
                           ;; Call f with the operation value, resume with result
                           (StepContinue (fn () (resume (f value)))))))

  (declare make-state-handler (Symbol -> (cell:Cell :s) -> EffectHandler))
  (define (make-state-handler tag state-cell)
    "Create a handler for state-like effects using a mutable cell.
Assumes the effect operations are:
- 'get': returns current state
- 'put': sets new state, returns Unit"
    (make-effect-handler tag
                         (fn (op-value resume)
                           ;; op-value is either 'get or (put new-value)
                           (lisp (Step :a) (op-value resume state-cell)
                             (cl:cond
                               ((cl:eq op-value 'get)
                                ;; Return current state
                                (call-coalton-function
                                 resume
                                 (coalton-library/cell::cell-internal-inner state-cell)))
                               ((cl:consp op-value)
                                ;; Put operation: (put . new-value)
                                (cl:setf (coalton-library/cell::cell-internal-inner state-cell) (cl:cdr op-value))
                                (call-coalton-function resume 'coalton::unit/unit))
                               (cl:t
                                (StepFail "Unknown state operation"))))))))


;;;
;;; Running with Handlers
;;;

(coalton-toplevel

  (declare with-handler (EffectHandler -> (Step :a) -> (Step :a)))
  (define (with-handler handler step)
    "Run a step with an effect handler installed.
The handler will intercept matching effect operations."
    (let ((tag (handler-tag handler)))
      (match step
        ;; Trampoline through
        ((StepContinue thunk)
         (StepContinue (fn () (with-handler handler (thunk)))))

        ;; Yield through
        ((StepYield thunk)
         (StepYield (fn () (with-handler handler (thunk)))))

        ;; Check if we handle this effect
        ((StepPerform data)
         (let ((op (step-perform-op data)))
           (if (lisp Boolean (tag op)
                 (cl:eq tag (effect-op-internal-tag op)))
               ;; We handle it - invoke handler
               (let ((value (effect-op-value op)))
                 ;; Wrap the continuation to re-install handler
                 (let ((wrapped-k
                        (fn (result)
                          (with-handler handler (step-perform-resume data result)))))
                   (apply-handler handler value wrapped-k)))
               ;; Not our effect - propagate with wrapped continuation
               (lisp (Step :a) (data handler)
                 (StepPerform
                  (make-step-perform-internal
                   :op (step-perform-internal-op data)
                   :continuation (cl:lambda (result)
                                   (with-handler handler
                                                 (cl:funcall (step-perform-internal-continuation data) result)))))))))

        ;; Terminal states pass through
        ((StepDone v) (StepDone v))
        ((StepFail msg) (StepFail msg))

        ;; Async passes through with handler re-installed
        ((StepAsync data)
         (lisp (Step :a) (data handler)
           (StepAsync
            (make-step-async-internal
             :register (step-async-internal-register data)
             :continuation (cl:lambda (result)
                             (with-handler handler
                                           (cl:funcall (step-async-internal-continuation data) result))))))))))

  (declare with-handlers ((List EffectHandler) -> (Step :a) -> (Step :a)))
  (define (with-handlers handlers step)
    "Run a step with multiple handlers installed.
Handlers are tried in order (first in list = outermost)."
    (match handlers
      ((Nil) step)
      ((Cons h rest)
       (with-handler h (with-handlers rest step))))))


;;;
;;; Common Effect Patterns
;;;

(coalton-toplevel

  ;; State effect operations
  (declare state-get-op EffectOp)
  (define state-get-op
    "Effect operation for getting state."
    (lisp EffectOp ()
      (make-effect-op-internal :tag 'state :value 'get)))

  (declare state-put-op (:s -> EffectOp))
  (define (state-put-op new-state)
    "Effect operation for putting state."
    (lisp EffectOp (new-state)
      (make-effect-op-internal :tag 'state :value (cl:cons 'put new-state))))

  ;; Reader effect operations
  (declare reader-ask-op EffectOp)
  (define reader-ask-op
    "Effect operation for asking the environment."
    (lisp EffectOp ()
      (make-effect-op-internal :tag 'reader :value 'ask)))

  ;; Writer effect operations
  (declare writer-tell-op (:w -> EffectOp))
  (define (writer-tell-op output)
    "Effect operation for telling output."
    (lisp EffectOp (output)
      (make-effect-op-internal :tag 'writer :value output))))


;;;
;;; Convenience: Run with State
;;;

(coalton-toplevel

  (declare run-state-step (:s -> (Step :a) -> (Step (Tuple :a :s))))
  (define (run-state-step initial step)
    "Run a step with state effect handling.
Returns a tuple of (result, final-state)."
    (let ((state-cell (cell:new initial)))
      (let ((handled
             (with-handler
              (lisp EffectHandler (state-cell)
                (make-effect-handler-internal
                 :tag 'state
                 :handler-fn (cl:lambda (op-value resume)
                               (cl:cond
                                 ((cl:eq op-value 'get)
                                  (call-coalton-function
                                   resume
                                   (coalton-library/cell::cell-internal-inner state-cell)))
                                 ((cl:and (cl:consp op-value) (cl:eq (cl:car op-value) 'put))
                                  (cl:setf (coalton-library/cell::cell-internal-inner state-cell) (cl:cdr op-value))
                                  (call-coalton-function resume 'coalton::unit/unit))
                                 (cl:t
                                  (StepFail "Unknown state operation"))))))
              step)))
        ;; After step completes, pair result with final state
        (cont-bind handled
                   (fn (result)
                     (StepDone (Tuple result (cell:read state-cell))))))))

  (declare run-reader-step (:r -> (Step :a) -> (Step :a)))
  (define (run-reader-step env step)
    "Run a step with reader effect handling."
    (with-handler
     (lisp EffectHandler (env)
       (make-effect-handler-internal
        :tag 'reader
        :handler-fn (cl:lambda (op-value resume)
                      (cl:if (cl:eq op-value 'ask)
                             (call-coalton-function resume env)
                             (StepFail "Unknown reader operation")))))
     step))

  (declare run-writer-step ((Step :a) -> (Step (Tuple :a (List :w)))))
  (define (run-writer-step step)
    "Run a step with writer effect handling.
Returns a tuple of (result, collected-output)."
    (let ((output-cell (cell:new (the (List :w) Nil))))
      (let ((handled
             (with-handler
              (lisp EffectHandler (output-cell)
                (make-effect-handler-internal
                 :tag 'writer
                 :handler-fn (cl:lambda (value resume)
                               (cl:progn
                                 (cell:push! output-cell value)
                                 (call-coalton-function resume 'coalton::unit/unit)))))
              step)))
        (cont-bind handled
                   (fn (result)
                     (let ((output (list:reverse (cell:read output-cell))))
                       (StepDone (Tuple result output)))))))))


;;;
;;; Exception-like Effect
;;;

(coalton-toplevel

  (declare fail-op (String -> EffectOp))
  (define (fail-op msg)
    "Effect operation for failure/exception."
    (lisp EffectOp (msg)
      (make-effect-op-internal :tag 'fail :value msg)))

  (declare catch-step ((Step :a) -> (:a -> (Step :b)) -> (String -> (Step :b)) -> (Step :b)))
  (define (catch-step step on-success on-error)
    "Run a step with error catching.
If the step fails, invoke on-error with the message.
If it succeeds, invoke on-success with the result."
    (match step
      ((StepContinue thunk)
       (StepContinue (fn () (catch-step (thunk) on-success on-error))))

      ((StepYield thunk)
       (StepYield (fn () (catch-step (thunk) on-success on-error))))

      ((StepPerform data)
       (let ((op (step-perform-op data)))
         (if (lisp Boolean (op) (cl:eq 'fail (effect-op-internal-tag op)))
             ;; Caught a fail effect
             (on-error (effect-op-value op))
             ;; Not a fail - propagate with wrapped continuation
             (lisp (Step :b) (data on-success on-error)
               (StepPerform
                (make-step-perform-internal
                 :op (step-perform-internal-op data)
                 :continuation (cl:lambda (result)
                                 (catch-step
                                  (cl:funcall (step-perform-internal-continuation data) result)
                                  on-success
                                  on-error))))))))

      ((StepDone v)
       (on-success v))

      ((StepFail msg)
       (on-error msg))

      ((StepAsync data)
       (lisp (Step :b) (data on-success on-error)
         (StepAsync
          (make-step-async-internal
           :register (step-async-internal-register data)
           :continuation (cl:lambda (result)
                           (catch-step
                            (cl:funcall (step-async-internal-continuation data) result)
                            on-success
                            on-error))))))))

  (declare try-step ((Step :a) -> (Step (Result String :a))))
  (define (try-step step)
    "Run a step and convert failures to Err results."
    (catch-step step
                (fn (v) (StepDone (Ok v)))
                (fn (msg) (StepDone (Err msg))))))
