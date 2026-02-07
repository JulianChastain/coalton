;;;; Fiber implementation - lightweight virtual threads
;;;;
;;;; Fibers are the unit of concurrent execution in the runtime.
;;;; Each fiber has its own continuation and can be suspended/resumed.
;;;; Fibers form a parent-child hierarchy for structured concurrency.

(in-package #:coalton-library/effects/runtime)

(named-readtables:in-readtable coalton:coalton)

;;;
;;; Fiber Status
;;;

(coalton-toplevel

  (define-type FiberStatus
    "The execution status of a fiber."
    ;; Fiber is created but not yet started
    FiberPending
    ;; Fiber is currently executing
    FiberRunning
    ;; Fiber is suspended (waiting on I/O, effect, etc.)
    FiberSuspended
    ;; Fiber completed successfully
    FiberDone
    ;; Fiber failed with an error
    FiberFailed
    ;; Fiber was interrupted
    FiberInterrupted)

  (define-instance (Eq FiberStatus)
    (define (== a b)
      (match (Tuple a b)
        ((Tuple (FiberPending) (FiberPending)) True)
        ((Tuple (FiberRunning) (FiberRunning)) True)
        ((Tuple (FiberSuspended) (FiberSuspended)) True)
        ((Tuple (FiberDone) (FiberDone)) True)
        ((Tuple (FiberFailed) (FiberFailed)) True)
        ((Tuple (FiberInterrupted) (FiberInterrupted)) True)
        (_ False)))))


;;;
;;; Fiber Internal Structure
;;;
;;; Uses CL structs for mutable state.
;;;

(cl:defstruct fiber-internal
  "Internal mutable structure for a fiber."
  ;; Unique identifier
  (id 0 :type cl:fixnum)
  ;; Current continuation (Step value)
  (continuation nil :type cl:t)
  ;; Current status
  (status 'pending :type cl:symbol)
  ;; Result value (when done)
  (result nil :type cl:t)
  ;; Error message (when failed)
  (error-msg nil :type (cl:or cl:null cl:string))
  ;; Parent fiber (nil for root fibers)
  (parent nil :type (cl:or cl:null fiber-internal))
  ;; Child fibers (list of fiber-internal)
  (children nil :type cl:list)
  ;; Interruption flag
  (interrupted-p nil :type cl:boolean)
  ;; Effect handlers stack (list of (tag . handler-fn))
  (handlers nil :type cl:list))

(cl:defvar *fiber-id-counter* 0
  "Global counter for generating unique fiber IDs.")

(cl:defun next-fiber-id ()
  "Generate the next unique fiber ID."
  (cl:incf *fiber-id-counter*))

;; Helper functions that bypass SBCL's overly strict type checking
(cl:declaim (cl:ftype (cl:function (cl:t) cl:t) fiber-status-from-symbol))
(cl:defun fiber-status-from-symbol (fiber)
  "Convert internal status symbol to FiberStatus value."
  (cl:declare (cl:optimize (cl:speed 0) (cl:safety 0) (cl:debug 3)))
  (cl:case (fiber-internal-status fiber)
    (pending (FiberPending))
    (running (FiberRunning))
    (suspended (FiberSuspended))
    (done (FiberDone))
    (failed (FiberFailed))
    (interrupted (FiberInterrupted))
    (cl:otherwise (FiberPending))))

(cl:defun fiber-status-to-symbol (status)
  "Convert FiberStatus value to internal status symbol."
  (cl:cond
    ((cl:typep status 'FiberStatus/FiberPending) 'pending)
    ((cl:typep status 'FiberStatus/FiberRunning) 'running)
    ((cl:typep status 'FiberStatus/FiberSuspended) 'suspended)
    ((cl:typep status 'FiberStatus/FiberDone) 'done)
    ((cl:typep status 'FiberStatus/FiberFailed) 'failed)
    ((cl:typep status 'FiberStatus/FiberInterrupted) 'interrupted)
    (cl:t 'pending)))


;;;
;;; Fiber Type and Operations
;;;

(coalton-toplevel

  (repr :native fiber-internal)
  (define-type (Fiber :a)
    "A lightweight virtual thread that executes a computation.

Fibers are the unit of concurrent execution. They:
- Have their own continuation (suspended computation)
- Can be suspended and resumed
- Form parent-child relationships for structured concurrency
- Can be interrupted (checked at yield points)")

  (declare make-fiber ((Step :a) -> (Fiber :a)))
  (define (make-fiber step)
    "Create a new fiber from a step computation."
    (lisp (Fiber :a) (step)
      (make-fiber-internal
       :id (next-fiber-id)
       :continuation step
       :status 'pending)))

  (declare make-child-fiber ((Fiber :b) -> (Step :a) -> (Fiber :a)))
  (define (make-child-fiber parent step)
    "Create a new fiber as a child of an existing fiber."
    (lisp (Fiber :a) (parent step)
      (cl:let ((child (make-fiber-internal
                       :id (next-fiber-id)
                       :continuation step
                       :status 'pending
                       :parent parent)))
        ;; Add child to parent's children list
        (cl:push child (fiber-internal-children parent))
        child)))

  (declare fiber-id ((Fiber :a) -> IFix))
  (define (fiber-id fiber)
    "Get the unique ID of a fiber."
    (lisp IFix (fiber)
      (fiber-internal-id fiber)))

  (declare fiber-status ((Fiber :a) -> FiberStatus))
  (define (fiber-status fiber)
    "Get the current status of a fiber."
    (lisp FiberStatus (fiber)
      (fiber-status-from-symbol fiber)))

  (declare fiber-set-status! ((Fiber :a) -> FiberStatus -> Unit))
  (define (fiber-set-status! fiber status)
    "Set the status of a fiber."
    (progn
      (lisp :a (fiber status)
        (cl:setf (fiber-internal-status fiber)
                 (fiber-status-to-symbol status)))
      Unit))

  (declare fiber-continuation ((Fiber :a) -> (Step :a)))
  (define (fiber-continuation fiber)
    "Get the current continuation of a fiber."
    (lisp (Step :a) (fiber)
      (fiber-internal-continuation fiber)))

  (declare fiber-set-continuation! ((Fiber :a) -> (Step :a) -> Unit))
  (define (fiber-set-continuation! fiber step)
    "Set the current continuation of a fiber."
    (lisp Unit (fiber step)
      (cl:setf (fiber-internal-continuation fiber) step)
      'coalton::unit/unit))

  (declare fiber-result ((Fiber :a) -> (Optional :a)))
  (define (fiber-result fiber)
    "Get the result of a completed fiber, if available."
    (lisp (Optional :a) (fiber)
      (cl:if (cl:eq (fiber-internal-status fiber) 'done)
             (Some (fiber-internal-result fiber))
             None)))

  (declare fiber-set-result! ((Fiber :a) -> :a -> Unit))
  (define (fiber-set-result! fiber result)
    "Set the result of a fiber."
    (lisp Unit (fiber result)
      (cl:setf (fiber-internal-result fiber) result)
      'coalton::unit/unit))

  (declare fiber-error ((Fiber :a) -> (Optional String)))
  (define (fiber-error fiber)
    "Get the error message of a failed fiber, if any."
    (lisp (Optional String) (fiber)
      (cl:let ((msg (fiber-internal-error-msg fiber)))
        (cl:if msg
               (Some msg)
               None))))

  (declare fiber-set-error! ((Fiber :a) -> String -> Unit))
  (define (fiber-set-error! fiber msg)
    "Set the error message of a fiber."
    (lisp Unit (fiber msg)
      (cl:setf (fiber-internal-error-msg fiber) msg)
      'coalton::unit/unit))

  (declare fiber-interrupt! ((Fiber :a) -> Unit))
  (define (fiber-interrupt! fiber)
    "Mark a fiber for interruption.
The fiber will be interrupted at the next yield point."
    (lisp Unit (fiber)
      (cl:setf (fiber-internal-interrupted-p fiber) cl:t)
      ;; Also interrupt all children (structured concurrency)
      (cl:dolist (child (fiber-internal-children fiber))
        (cl:setf (fiber-internal-interrupted-p child) cl:t))
      'coalton::unit/unit))

  (declare fiber-interrupted? ((Fiber :a) -> Boolean))
  (define (fiber-interrupted? fiber)
    "Check if a fiber has been marked for interruption."
    (lisp Boolean (fiber)
      (fiber-internal-interrupted-p fiber)))

  (declare fiber-done? ((Fiber :a) -> Boolean))
  (define (fiber-done? fiber)
    "Check if a fiber has completed (done, failed, or interrupted)."
    (let ((status (fiber-status fiber)))
      (or (== status FiberDone)
          (or (== status FiberFailed)
              (== status FiberInterrupted)))))

  (declare fiber-parent ((Fiber :a) -> (Optional (Fiber :b))))
  (define (fiber-parent fiber)
    "Get the parent fiber, if any."
    (lisp (Optional (Fiber :b)) (fiber)
      (cl:let ((parent (fiber-internal-parent fiber)))
        (cl:if parent
               (Some parent)
               None))))

  (declare fiber-children ((Fiber :a) -> (List (Fiber :b))))
  (define (fiber-children fiber)
    "Get the list of child fibers."
    (lisp (List (Fiber :b)) (fiber)
      (fiber-internal-children fiber)))

  (declare fiber-add-handler! ((Fiber :a) -> Symbol -> (:b -> (:c -> (Step :a)) -> (Step :a)) -> Unit))
  (define (fiber-add-handler! fiber tag handler)
    "Add an effect handler to a fiber's handler stack."
    (lisp Unit (fiber tag handler)
      (cl:push (cl:cons tag handler) (fiber-internal-handlers fiber))
      'coalton::unit/unit))

  (declare fiber-remove-handler! ((Fiber :a) -> Symbol -> Unit))
  (define (fiber-remove-handler! fiber tag)
    "Remove the topmost handler for a given effect tag."
    (lisp Unit (fiber tag)
      (cl:setf (fiber-internal-handlers fiber)
               (cl:remove tag (fiber-internal-handlers fiber)
                          :key #'cl:car :count 1))
      'coalton::unit/unit))

  (declare fiber-find-handler ((Fiber :a) -> Symbol -> (Optional (:b -> (:c -> (Step :a)) -> (Step :a)))))
  (define (fiber-find-handler fiber tag)
    "Find the handler for an effect tag in the fiber's handler stack."
    (lisp (Optional (:b -> (:c -> (Step :a)) -> (Step :a))) (fiber tag)
      (cl:let ((entry (cl:assoc tag (fiber-internal-handlers fiber))))
        (cl:if entry
               (Some (cl:cdr entry))
               None)))))


;;;
;;; Fiber Execution
;;;
;;; Single-step execution of a fiber's continuation.
;;;

(coalton-toplevel

  (define-type (FiberStepResult :a)
    "Result of stepping a fiber once."
    ;; Fiber completed with value
    (FiberCompleted :a)
    ;; Fiber failed with error
    (FiberErrored String)
    ;; Fiber yielded, needs to be re-queued
    FiberYielded
    ;; Fiber suspended on async I/O
    FiberSuspendedAsync
    ;; Fiber needs effect handling
    (FiberNeedsHandler EffectOp)
    ;; Fiber was interrupted
    FiberWasInterrupted
    ;; Fiber needs more steps (for batch execution)
    FiberContinuing)

  (declare fiber-step! ((Fiber :a) -> (FiberStepResult :a)))
  (define (fiber-step! fiber)
    "Execute one step of a fiber's continuation.
Returns the result indicating what happened."
    ;; Check for interruption first
    (if (fiber-interrupted? fiber)
        (progn
          (fiber-set-status! fiber FiberInterrupted)
          FiberWasInterrupted)
        (let ((step (fiber-continuation fiber)))
          (match step
            ;; Continue: execute thunk and store result
            ((StepContinue thunk)
             (fiber-set-continuation! fiber (thunk))
             FiberContinuing)

            ;; Yield: mark as needing re-queue
            ((StepYield thunk)
             (fiber-set-continuation! fiber (thunk))
             FiberYielded)

            ;; Perform: check for handler
            ((StepPerform data)
             (let ((op (step-perform-op data)))
               (match (fiber-find-handler fiber (effect-op-tag op))
                 ((Some handler)
                  ;; Handler found - apply it
                  (let ((value (effect-op-value op)))
                    (fiber-set-continuation! fiber
                      ;; Handler receives the operation value and a resume function
                      (lisp (Step :a) (handler value data)
                        (call-coalton-function
                         (call-coalton-function handler value)
                         (cl:lambda (result)
                           (cl:funcall (step-perform-internal-continuation data) result)))))
                    FiberContinuing))
                 ((None)
                  ;; No handler - signal need for one
                  (FiberNeedsHandler op)))))

            ;; Done: mark fiber complete
            ((StepDone value)
             (progn
               (fiber-set-result! fiber value)
               (fiber-set-status! fiber FiberDone)
               (FiberCompleted value)))

            ;; Fail: mark fiber failed
            ((StepFail msg)
             (progn
               (fiber-set-error! fiber msg)
               (fiber-set-status! fiber FiberFailed)
               (FiberErrored msg)))

            ;; Async: suspend and register callback
            ((StepAsync data)
             (progn
               (fiber-set-status! fiber FiberSuspended)
               ;; Register callback that resumes the fiber when async completes
               (lisp Unit (fiber data)
                 (cl:funcall (step-async-internal-register data)
                             (cl:lambda (result)
                               (cl:setf (fiber-internal-continuation fiber)
                                        (cl:funcall (step-async-internal-continuation data) result))
                               (cl:setf (fiber-internal-status fiber) 'pending)
                               'coalton::unit/unit))
                 'coalton::unit/unit)
               FiberSuspendedAsync)))))))
