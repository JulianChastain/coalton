;;;; Fiber Scheduler - cooperative scheduling with yield threshold
;;;;
;;;; The scheduler manages multiple fibers, executing them in round-robin
;;;; fashion with periodic yields to ensure fairness. It integrates with
;;;; the event loop for async I/O.

(in-package #:coalton-library/effects/runtime)

(named-readtables:in-readtable coalton:coalton)

;;;
;;; Configuration
;;;

(cl:defvar *default-yield-threshold* 2048
  "Default number of operations before a fiber yields.
Inspired by Effect-TS which uses 2048.")

(coalton-toplevel
  (declare default-yield-threshold (Unit -> UFix))
  (define (default-yield-threshold)
    "Get the default yield threshold."
    (lisp UFix ()
      *default-yield-threshold*)))


;;;
;;; Scheduler Internal Structure
;;;

(cl:defstruct scheduler-internal
  "Internal mutable structure for the scheduler."
  ;; Ready queue (FIFO list of fibers)
  (ready-queue nil :type cl:list)
  ;; Suspended fibers (waiting on async)
  (suspended nil :type cl:list)
  ;; Currently executing fiber (or nil)
  (current nil :type (cl:or cl:null fiber-internal))
  ;; Operation count for current fiber
  (op-count 0 :type cl:fixnum)
  ;; Yield threshold
  (yield-threshold *default-yield-threshold* :type cl:fixnum)
  ;; Whether the scheduler is running
  (running-p nil :type cl:boolean)
  ;; Global effect handlers (list of (tag . handler-fn))
  (global-handlers nil :type cl:list))


;;;
;;; Scheduler Type and Operations
;;;

(coalton-toplevel

  (repr :native scheduler-internal)
  (define-type Scheduler
    "A cooperative scheduler for executing fibers.

The scheduler:
- Maintains a ready queue of runnable fibers
- Tracks suspended fibers waiting on async I/O
- Executes fibers in round-robin order
- Yields after a threshold number of operations
- Supports global effect handlers")

  (declare make-scheduler (Unit -> Scheduler))
  (define (make-scheduler)
    "Create a new scheduler with default settings."
    (lisp Scheduler ()
      (make-scheduler-internal)))

  (declare make-scheduler-with-threshold (UFix -> Scheduler))
  (define (make-scheduler-with-threshold threshold)
    "Create a new scheduler with a custom yield threshold."
    (lisp Scheduler (threshold)
      (make-scheduler-internal :yield-threshold threshold)))

  (declare scheduler-yield-threshold (Scheduler -> UFix))
  (define (scheduler-yield-threshold sched)
    "Get the yield threshold of a scheduler."
    (lisp UFix (sched)
      (scheduler-internal-yield-threshold sched)))

  (declare scheduler-set-yield-threshold! (Scheduler -> UFix -> Unit))
  (define (scheduler-set-yield-threshold! sched threshold)
    "Set the yield threshold of a scheduler."
    (lisp Unit (sched threshold)
      (cl:setf (scheduler-internal-yield-threshold sched) threshold)
      'coalton::unit/unit))

  (declare scheduler-running? (Scheduler -> Boolean))
  (define (scheduler-running? sched)
    "Check if the scheduler is currently running."
    (lisp Boolean (sched)
      (scheduler-internal-running-p sched)))

  (declare scheduler-current (Scheduler -> (Optional (Fiber :a))))
  (define (scheduler-current sched)
    "Get the currently executing fiber, if any."
    (lisp (Optional (Fiber :a)) (sched)
      (cl:let ((current (scheduler-internal-current sched)))
        (cl:if current
               (Some current)
               None))))

  (declare scheduler-ready-count (Scheduler -> UFix))
  (define (scheduler-ready-count sched)
    "Get the number of fibers in the ready queue."
    (lisp UFix (sched)
      (cl:length (scheduler-internal-ready-queue sched))))

  (declare scheduler-suspended-count (Scheduler -> UFix))
  (define (scheduler-suspended-count sched)
    "Get the number of suspended fibers."
    (lisp UFix (sched)
      (cl:length (scheduler-internal-suspended sched))))

  (declare scheduler-empty? (Scheduler -> Boolean))
  (define (scheduler-empty? sched)
    "Check if the scheduler has no more work to do."
    (and (== 0 (scheduler-ready-count sched))
         (== 0 (scheduler-suspended-count sched)))))


;;;
;;; Queue Management
;;;

(coalton-toplevel

  (declare scheduler-enqueue! (Scheduler -> (Fiber :a) -> Unit))
  (define (scheduler-enqueue! sched fiber)
    "Add a fiber to the ready queue."
    (lisp Unit (sched fiber)
      ;; Add to end of queue (FIFO)
      (cl:setf (scheduler-internal-ready-queue sched)
               (cl:nconc (scheduler-internal-ready-queue sched) (cl:list fiber)))
      'coalton::unit/unit))

  (declare scheduler-dequeue! (Scheduler -> (Optional (Fiber :a))))
  (define (scheduler-dequeue! sched)
    "Remove and return the next fiber from the ready queue."
    (lisp (Optional (Fiber :a)) (sched)
      (cl:let ((queue (scheduler-internal-ready-queue sched)))
        (cl:if queue
               (cl:progn
                 (cl:setf (scheduler-internal-ready-queue sched) (cl:cdr queue))
                 (Some (cl:car queue)))
               None))))

  (declare scheduler-suspend! (Scheduler -> (Fiber :a) -> Unit))
  (define (scheduler-suspend! sched fiber)
    "Move a fiber to the suspended list."
    (lisp Unit (sched fiber)
      (cl:push fiber (scheduler-internal-suspended sched))
      'coalton::unit/unit))

  (declare scheduler-resume! (Scheduler -> (Fiber :a) -> Unit))
  (define (scheduler-resume! sched fiber)
    "Move a fiber from suspended back to ready."
    (lisp Unit (sched fiber)
      (cl:setf (scheduler-internal-suspended sched)
               (cl:remove fiber (scheduler-internal-suspended sched)))
      (cl:setf (scheduler-internal-ready-queue sched)
               (cl:nconc (scheduler-internal-ready-queue sched) (cl:list fiber)))
      'coalton::unit/unit)))


;;;
;;; Fiber Spawning
;;;

(coalton-toplevel

  (declare scheduler-spawn! (Scheduler -> (Step :a) -> (Fiber :a)))
  (define (scheduler-spawn! sched step)
    "Spawn a new fiber and add it to the scheduler.
Returns the created fiber."
    (let ((fiber (make-fiber step)))
      (scheduler-enqueue! sched fiber)
      fiber))

  (declare scheduler-spawn-child! (Scheduler -> (Fiber :b) -> (Step :a) -> (Fiber :a)))
  (define (scheduler-spawn-child! sched parent step)
    "Spawn a child fiber under a parent and add it to the scheduler."
    (let ((fiber (make-child-fiber parent step)))
      (scheduler-enqueue! sched fiber)
      fiber)))


;;;
;;; Global Effect Handlers
;;;

(coalton-toplevel

  (declare scheduler-add-handler! (Scheduler -> Symbol -> (:a -> (:b -> (Step :c)) -> (Step :c)) -> Unit))
  (define (scheduler-add-handler! sched tag handler)
    "Add a global effect handler to the scheduler."
    (lisp Unit (sched tag handler)
      (cl:push (cl:cons tag handler) (scheduler-internal-global-handlers sched))
      'coalton::unit/unit))

  (declare scheduler-find-handler (Scheduler -> Symbol -> (Optional (:a -> (:b -> (Step :c)) -> (Step :c)))))
  (define (scheduler-find-handler sched tag)
    "Find a global handler for an effect tag."
    (lisp (Optional (:a -> (:b -> (Step :c)) -> (Step :c))) (sched tag)
      (cl:let ((entry (cl:assoc tag (scheduler-internal-global-handlers sched))))
        (cl:if entry
               (Some (cl:cdr entry))
               None)))))


;;;
;;; Single-Step Execution
;;;

(coalton-toplevel

  (declare scheduler-step! (Scheduler -> Boolean))
  (define (scheduler-step! sched)
    "Execute one scheduling step.
Returns True if work was done, False if scheduler is idle."
    (match (scheduler-dequeue! sched)
      ((None) False)
      ((Some fiber)
       (progn
         ;; Set as current fiber
         (lisp Unit (sched fiber)
           (cl:setf (scheduler-internal-current sched) fiber)
           (cl:setf (scheduler-internal-op-count sched) 0)
           'coalton::unit/unit)

         ;; Mark fiber as running
         (fiber-set-status! fiber FiberRunning)

         ;; Execute fiber steps until yield or completion
         (scheduler-run-fiber! sched fiber)

         ;; Clear current fiber
         (lisp Unit (sched)
           (cl:setf (scheduler-internal-current sched) cl:nil)
           'coalton::unit/unit)

         True))))

  (declare scheduler-run-fiber! (Scheduler -> (Fiber :a) -> Unit))
  (define (scheduler-run-fiber! sched fiber)
    "Run a fiber until it yields, completes, or hits the yield threshold."
    (let ((threshold (scheduler-yield-threshold sched)))
      (lisp Unit (sched fiber threshold)
        (cl:loop
          (cl:let ((op-count (scheduler-internal-op-count sched)))
            ;; Check yield threshold
            (cl:when (cl:>= op-count threshold)
              ;; Re-queue fiber
              (cl:setf (scheduler-internal-ready-queue sched)
                       (cl:nconc (scheduler-internal-ready-queue sched) (cl:list fiber)))
              (cl:return 'coalton::unit/unit))

            ;; Increment op count
            (cl:incf (scheduler-internal-op-count sched))

            ;; Execute one step and dispatch on result
            (cl:let ((result (fiber-step! fiber)))
              (cl:cond
                ;; Continue: keep going (loop continues)
                ((cl:typep result 'FiberStepResult/FiberContinuing)
                 cl:nil)

                ;; Yielded: re-queue
                ((cl:typep result 'FiberStepResult/FiberYielded)
                 (cl:setf (scheduler-internal-ready-queue sched)
                          (cl:nconc (scheduler-internal-ready-queue sched) (cl:list fiber)))
                 (cl:return 'coalton::unit/unit))

                ;; Completed: done with this fiber
                ((cl:typep result 'FiberStepResult/FiberCompleted)
                 (cl:return 'coalton::unit/unit))

                ;; Errored: done with this fiber
                ((cl:typep result 'FiberStepResult/FiberErrored)
                 (cl:return 'coalton::unit/unit))

                ;; Interrupted: done with this fiber
                ((cl:typep result 'FiberStepResult/FiberWasInterrupted)
                 (cl:return 'coalton::unit/unit))

                ;; Suspended on async: add to suspended list
                ((cl:typep result 'FiberStepResult/FiberSuspendedAsync)
                 (cl:push fiber (scheduler-internal-suspended sched))
                 (cl:return 'coalton::unit/unit))

                ;; Needs handler: try global handlers
                ((cl:typep result 'FiberStepResult/FiberNeedsHandler)
                 (cl:let* ((op (FiberStepResult/FiberNeedsHandler-_0 result))
                           (tag (effect-op-internal-tag op))
                           (entry (cl:assoc tag (scheduler-internal-global-handlers sched))))
                   (cl:if entry
                          ;; Found global handler - apply it
                          (cl:let* ((handler (cl:cdr entry))
                                    (value (effect-op-internal-value op))
                                    (cont (fiber-internal-continuation fiber)))
                            ;; cont should be a StepPerform - extract resume fn
                            (cl:if (cl:typep cont 'Step/StepPerform)
                              (cl:let ((data (Step/StepPerform-_0 cont)))
                                (cl:setf (fiber-internal-continuation fiber)
                                         (call-coalton-function
                                          (call-coalton-function handler value)
                                          (cl:lambda (result)
                                            (cl:funcall (step-perform-internal-continuation data) result)))))
                              ;; Continuation is not StepPerform — cannot apply handler
                              (cl:progn
                                (cl:setf (fiber-internal-error-msg fiber)
                                         (cl:format cl:nil "Cannot apply handler: unexpected continuation type"))
                                (cl:setf (fiber-internal-status fiber) 'failed)
                                (cl:return 'coalton::unit/unit))))
                          ;; No handler - fail the fiber
                          (cl:progn
                            (cl:setf (fiber-internal-error-msg fiber)
                                     (cl:format cl:nil "Unhandled effect: ~A" tag))
                            (cl:setf (fiber-internal-status fiber) 'failed)
                            (cl:return 'coalton::unit/unit)))))

                ;; Unknown result type - fail the fiber
                (cl:t
                 (cl:setf (fiber-internal-error-msg fiber)
                          (cl:format cl:nil "Unknown fiber step result: ~A" result))
                 (cl:setf (fiber-internal-status fiber) 'failed)
                 (cl:return 'coalton::unit/unit))))))))))


;;;
;;; Full Scheduler Run
;;;

(coalton-toplevel

  (declare scheduler-run! (Scheduler -> Unit))
  (define (scheduler-run! sched)
    "Run the scheduler until all fibers complete.
Does not integrate with event loop - use with-async-runtime for async."
    (lisp Unit (sched)
      (cl:setf (scheduler-internal-running-p sched) cl:t)
      (cl:loop
        (cl:unless (scheduler-internal-running-p sched)
          (cl:return))
        (cl:let ((did-work (scheduler-step! sched)))
          (cl:unless did-work
            ;; No ready fibers - check if we have suspended fibers
            (cl:if (scheduler-internal-suspended sched)
                   ;; Have suspended fibers - would need event loop
                   (cl:progn
                     (cl:warn "Scheduler has suspended fibers but no event loop")
                     (cl:setf (scheduler-internal-running-p sched) cl:nil))
                   ;; No fibers at all - we're done
                   (cl:setf (scheduler-internal-running-p sched) cl:nil)))))
      'coalton::unit/unit))

  (declare scheduler-stop! (Scheduler -> Unit))
  (define (scheduler-stop! sched)
    "Stop the scheduler."
    (lisp Unit (sched)
      (cl:setf (scheduler-internal-running-p sched) cl:nil)
      'coalton::unit/unit)))


;;;
;;; Convenience: Run a Step to Completion
;;;

(coalton-toplevel

  (declare run-with-scheduler ((Step :a) -> (Result String :a)))
  (define (run-with-scheduler step)
    "Run a step computation with a fresh scheduler.
Returns the result or an error message."
    (let ((sched (make-scheduler)))
      (let ((fiber (scheduler-spawn! sched step)))
        (progn
          (scheduler-run! sched)
          (match (fiber-status fiber)
            ((FiberDone)
             (match (fiber-result fiber)
               ((Some result) (Ok result))
               ((None) (Err "Fiber completed but has no result"))))
            ((FiberFailed)
             (match (fiber-error fiber)
               ((Some msg) (Err msg))
               ((None) (Err "Fiber failed with unknown error"))))
            ((FiberInterrupted)
             (Err "Fiber was interrupted"))
            (_
             (Err "Fiber did not complete"))))))))
