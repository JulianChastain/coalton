;;;; Structured Concurrency - fork, join, race, and scopes
;;;;
;;;; This module provides structured concurrency primitives that ensure
;;;; proper cleanup and error propagation across fiber hierarchies.

(in-package #:coalton-library/effects/runtime)

(named-readtables:in-readtable coalton:coalton)

;;;
;;; Scope Type
;;;
;;; A scope manages a group of child fibers with structured lifecycle.
;;;

(cl:defstruct scope-internal
  "Internal structure for a concurrency scope."
  ;; The scheduler this scope belongs to
  (scheduler nil :type (cl:or cl:null scheduler-internal))
  ;; Parent fiber that owns this scope
  (parent-fiber nil :type (cl:or cl:null fiber-internal))
  ;; Child fibers spawned in this scope
  (children nil :type cl:list)
  ;; Whether the scope is closed (no more spawning allowed)
  (closed-p nil :type cl:boolean)
  ;; Error from any failed child
  (error nil :type (cl:or cl:null cl:string)))


(coalton-toplevel

  (repr :native scope-internal)
  (define-type Scope
    "A structured concurrency scope.

Scopes ensure that:
- All child fibers complete before the scope exits
- Errors in children propagate to the parent
- Interruption of parent interrupts all children
- Resources are properly cleaned up")

  (declare scope-closed? (Scope -> Boolean))
  (define (scope-closed? scope)
    "Check if a scope is closed for new spawns."
    (lisp Boolean (scope)
      (scope-internal-closed-p scope)))

  (declare scope-error (Scope -> (Optional String)))
  (define (scope-error scope)
    "Get the error from a failed child, if any."
    (lisp (Optional String) (scope)
      (cl:let ((error-msg (scope-internal-error scope)))
        (cl:if error-msg
               (Some error-msg)
               None))))

  (declare scope-children-count (Scope -> UFix))
  (define (scope-children-count scope)
    "Get the number of children in the scope."
    (lisp UFix (scope)
      (cl:length (scope-internal-children scope)))))


;;;
;;; Fork Operation
;;;

(coalton-toplevel

  (declare fork (Scheduler -> (Step :a) -> (Step (Fiber :a))))
  (define (fork sched step)
    "Fork a new fiber to run the given step.
Returns immediately with the fiber handle.
The fiber runs concurrently with the current fiber."
    (StepContinue
     (fn ()
       (let ((fiber (scheduler-spawn! sched step)))
         (StepDone fiber)))))

  (declare fork-in-scope (Scope -> (Step :a) -> (Step (Fiber :a))))
  (define (fork-in-scope scope step)
    "Fork a fiber within a scope.
The fiber is tracked by the scope for structured concurrency."
    (if (scope-closed? scope)
        (StepFail "Cannot fork in closed scope")
        (StepContinue
         (fn ()
           (lisp (Step (Fiber :a)) (scope step)
             (cl:let* ((sched (scope-internal-scheduler scope))
                       (parent (scope-internal-parent-fiber scope))
                       (fiber (cl:if parent
                                     (scheduler-spawn-child! sched parent step)
                                     (scheduler-spawn! sched step))))
               (cl:push fiber (scope-internal-children scope))
               (StepDone fiber))))))))


;;;
;;; Join Operation
;;;

(coalton-toplevel

  (declare await-fiber ((Fiber :a) -> (Step (Result String :a))))
  (define (await-fiber fiber)
    "Wait for a fiber to complete and get its result.
Returns Ok with the value if successful, Err if failed."
    (>>= (poll-until 10 (fn () (fiber-done? fiber)))
         (fn (_)
           (match (fiber-status fiber)
             ((FiberDone)
              (match (fiber-result fiber)
                ((Some v) (StepDone (Ok v)))
                ((None) (StepDone (Err "Fiber completed but no result")))))
             ((FiberFailed)
              (match (fiber-error fiber)
                ((Some msg) (StepDone (Err msg)))
                ((None) (StepDone (Err "Fiber failed with unknown error")))))
             ((FiberInterrupted)
              (StepDone (Err "Fiber was interrupted")))
             (_
              (StepDone (Err "Fiber in unexpected state")))))))

  (declare await-fiber-unwrap ((Fiber :a) -> (Step :a)))
  (define (await-fiber-unwrap fiber)
    "Wait for a fiber and unwrap its result, failing on error."
    (>>= (await-fiber fiber)
         (fn (result)
           (match result
             ((Ok v) (StepDone v))
             ((Err msg) (StepFail msg)))))))


;;;
;;; Race Operation
;;;

(coalton-toplevel

  (declare race ((Fiber :a) -> (Fiber :a) -> (Step :a)))
  (define (race fiber1 fiber2)
    "Race two fibers. Returns the result of whichever completes first.
The losing fiber is interrupted."
    (>>= (poll-until 10
                     (fn () (or (fiber-done? fiber1)
                                (fiber-done? fiber2))))
         (fn (_)
           (cond
             ((fiber-done? fiber1)
              (progn
                (fiber-interrupt! fiber2)
                (await-fiber-unwrap fiber1)))
             ((fiber-done? fiber2)
              (progn
                (fiber-interrupt! fiber1)
                (await-fiber-unwrap fiber2)))
             (True
              (StepFail "Race: no fiber completed"))))))

  (declare race-list ((List (Fiber :a)) -> (Step :a)))
  (define (race-list fibers)
    "Race multiple fibers. Returns the result of the first to complete.
All other fibers are interrupted."
    (match fibers
      ((Nil) (StepFail "race-list: empty list"))
      ((Cons f (Nil)) (await-fiber-unwrap f))
      ((Cons f1 (Cons f2 rest))
       ;; Pairwise race all fibers
       (match rest
         ((Nil) (race f1 f2))
         (_
          ;; Race first two, then race winner with rest
          ;; This isn't the most efficient but it's simple
          (StepFail "race-list: TODO implement for >2 fibers")))))))


;;;
;;; All Operation
;;;

(coalton-toplevel

  (declare all-fibers ((List (Fiber :a)) -> (Step (List (Result String :a)))))
  (define (all-fibers fibers)
    "Wait for all fibers to complete.
Returns a list of results in the same order as the input fibers."
    (match fibers
      ((Nil) (StepDone Nil))
      ((Cons f rest)
       (>>= (await-fiber f)
            (fn (result)
              (>>= (all-fibers rest)
                   (fn (results)
                     (StepDone (Cons result results)))))))))

  (declare all-fibers-unwrap ((List (Fiber :a)) -> (Step (List :a))))
  (define (all-fibers-unwrap fibers)
    "Wait for all fibers and unwrap their results.
Fails if any fiber fails (fail-fast behavior)."
    (match fibers
      ((Nil) (StepDone Nil))
      ((Cons f rest)
       (>>= (await-fiber-unwrap f)
            (fn (result)
              (>>= (all-fibers-unwrap rest)
                   (fn (results)
                     (StepDone (Cons result results))))))))))


;;;
;;; With Scope
;;;

(coalton-toplevel

  (declare with-scope (Scheduler -> (Scope -> (Step :a)) -> (Step :a)))
  (define (with-scope sched body)
    "Run a computation with a new concurrency scope.
All fibers forked within the scope are automatically awaited on exit.
If any child fails, the scope fails and remaining children are interrupted."
    (let ((scope (lisp Scope (sched)
                   (make-scope-internal :scheduler sched))))
      (>>= (body scope)
           (fn (result)
             ;; Close scope
             (lisp Unit (scope)
               (cl:setf (scope-internal-closed-p scope) cl:t)
               'coalton::unit/unit)
             (wait-scope-children scope result)))))

  (declare wait-scope-children (Scope -> :a -> (Step :a)))
  (define (wait-scope-children scope result)
    "Wait for all children in a scope to complete."
    (let ((children-count (scope-children-count scope)))
      (if (== 0 children-count)
          ;; All done - check for error
          (match (scope-error scope)
            ((Some msg) (StepFail msg))
            ((None) (StepDone result)))
          ;; Check children and yield
          (StepYield
           (fn ()
             (progn
               ;; Process children
               (lisp Unit (scope)
                 (cl:dolist (child (scope-internal-children scope))
                   (cl:when (fiber-done? child)
                     ;; Remove from list
                     (cl:setf (scope-internal-children scope)
                              (cl:remove child (scope-internal-children scope)))
                     ;; Check for error
                     (cl:when (cl:eq (fiber-internal-status child) 'failed)
                       (cl:let ((error-msg (fiber-internal-error-msg child)))
                         (cl:setf (scope-internal-error scope)
                                  (cl:or error-msg "Child failed"))
                         ;; Interrupt remaining children
                         (cl:dolist (c (scope-internal-children scope))
                           (cl:setf (fiber-internal-interrupted-p c) cl:t))))))
                 'coalton::unit/unit)
               (wait-scope-children scope result))))))))


;;;
;;; Parallel Combinators
;;;

(coalton-toplevel

  (declare parallel-map (Scheduler -> (:a -> (Step :b)) -> (List :a) -> (Step (List :b))))
  (define (parallel-map sched f items)
    "Apply f to each item in parallel, collecting results.
Results are in the same order as inputs."
    (with-scope sched
                (fn (scope)
                  (let ((fibers (map (fn (x) (fork-in-scope scope (f x))) items)))
                    ;; Wait for all fork operations to complete
                    (>>= (foldr
                          (fn (fiber-step acc)
                            (>>= fiber-step
                                 (fn (fiber)
                                   (>>= acc
                                        (fn (fibers)
                                          (StepDone (Cons fiber fibers)))))))
                          (StepDone (the (List (Fiber :b)) Nil))
                          fibers)
                         ;; Now wait for all fibers
                         (fn (fiber-list)
                           (all-fibers-unwrap fiber-list)))))))

  (declare parallel-for-each (Scheduler -> (:a -> (Step Unit)) -> (List :a) -> (Step Unit)))
  (define (parallel-for-each sched f items)
    "Apply f to each item in parallel, discarding results."
    (>>= (parallel-map sched f items)
         (fn (_) (StepDone Unit))))

  (declare parallel2 (Scheduler -> (Step :a) -> (Step :b) -> (Step (Tuple :a :b))))
  (define (parallel2 sched step1 step2)
    "Run two steps in parallel, returning both results as a tuple."
    (with-scope sched
                (fn (scope)
                  (>>= (fork-in-scope scope step1)
                       (fn (fiber1)
                         (>>= (fork-in-scope scope step2)
                              (fn (fiber2)
                                (>>= (await-fiber-unwrap fiber1)
                                     (fn (result1)
                                       (>>= (await-fiber-unwrap fiber2)
                                            (fn (result2)
                                              (StepDone (Tuple result1 result2))))))))))))))


;;;
;;; Supervision
;;;

(coalton-toplevel

  (declare supervise (Scheduler -> (String -> (Step Unit)) -> (Step :a) -> (Step :a)))
  (define (supervise sched on-error step)
    "Run a step with supervision.
If the step fails, on-error is called with the error message,
and the step is retried."
    (catch-step step
                (fn (v) (StepDone v))
                (fn (msg)
                  ;; Call error handler then retry
                  (>>= (on-error msg)
                       (fn (_) (supervise sched on-error step))))))

  (declare supervise-with-limit (Scheduler -> UFix -> (String -> (Step Unit)) -> (Step :a) -> (Step :a)))
  (define (supervise-with-limit sched max-retries on-error step)
    "Run a step with supervision and limited retries."
    (if (<= max-retries 0)
        step
        (catch-step step
                    (fn (v) (StepDone v))
                    (fn (msg)
                      (>>= (on-error msg)
                           (fn (_) (supervise-with-limit sched (- max-retries 1) on-error step))))))))
