(in-package #:coalton-library/effects)

(coalton-toplevel

  ;;;
  ;;; State Effect
  ;;;
  ;;; The State effect provides mutable state within a computation.
  ;;; Unlike the State monad, effects allow state to be used in
  ;;; direct style without explicit threading.
  ;;;

  ;; Note: The actual effect operations are defined in the typechecker
  ;; and compiled to CL conditions/restarts. This file provides the
  ;; user-facing API.

  (declare get (Unit -> :s ! (State :s)))
  (define (get)
    "Get the current state value."
    (perform state.get))

  (declare put (:s -> Unit ! (State :s)))
  (define (put new-state)
    "Replace the current state with a new value."
    (perform (state.put new-state)))

  (declare modify ((:s -> :s) -> Unit ! (State :s)))
  (define (modify f)
    "Modify the state by applying a function to it."
    (let ((current (get)))
      (put (f current))))

  (declare run-state (:s -> (Unit -> :a ! (State :s)) -> (Tuple :a :s)))
  (define (run-state initial-state computation)
    "Run a stateful computation with an initial state.

Returns a tuple of (result, final-state)."
    (let ((state initial-state))
      (handle (computation)
        (state.get (resume)
          (resume state))
        (state.put (new-state resume)
          (lisp Unit (new-state state)
            (setf state new-state)
            'coalton:Unit)
          (resume Unit))
        (return (x)
          (Tuple x state))))))
