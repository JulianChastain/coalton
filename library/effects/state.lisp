(in-package #:coalton-library/effects)

(coalton-toplevel

  ;;;
  ;;; State Effect
  ;;;
  ;;; The State effect provides mutable state within a computation.
  ;;; Unlike the State monad, effects allow state to be used in
  ;;; direct style without explicit threading.
  ;;;

  (declare get (Unit -> :s))
  (define (get)
    "Get the current state value."
    (perform state.get))

  (declare put (:s -> Unit))
  (define (put new-state)
    "Replace the current state with a new value."
    (perform (state.put new-state)))

  (declare modify ((:s -> :s) -> Unit))
  (define (modify f)
    "Modify the state by applying a function to it."
    (let ((current (get)))
      (put (f current))))

  (declare run-state (:s -> (Unit -> :a) -> (Tuple :a :s)))
  (define (run-state initial-state computation)
    "Run a stateful computation with an initial state.

Returns a tuple of (result, final-state)."
    (let ((state (cell:new initial-state)))
      (let ((result
              (handle (computation)
                (state.get (resume)
                  (resume (cell:read state)))
                (state.put (new-state resume)
                  (cell:write! state new-state)
                  (resume Unit))
                (return (x) x))))
        (Tuple result (cell:read state))))))
