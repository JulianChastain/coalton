(in-package #:coalton-library/effects)

(coalton-toplevel

  ;;;
  ;;; Reader Effect
  ;;;
  ;;; The Reader effect provides read-only access to an environment.
  ;;; The environment is implicitly available throughout the computation.
  ;;;

  (declare ask (Unit -> :r ! (Reader :r)))
  (define (ask)
    "Get the current environment value."
    (perform reader.ask))

  (declare asks ((:r -> :a) -> :a ! (Reader :r)))
  (define (asks f)
    "Apply a function to the environment."
    (f (ask)))

  (declare local ((:r -> :r) -> (Unit -> :a ! (Reader :r)) -> :a ! (Reader :r)))
  (define (local f computation)
    "Run a computation with a modified environment.

The modification only applies within the scope of the computation."
    (let ((env (ask)))
      (handle (computation)
        (reader.ask (resume)
          (resume (f env)))
        (return (x) x))))

  (declare run-reader (:r -> (Unit -> :a ! (Reader :r)) -> :a))
  (define (run-reader env computation)
    "Run a reader computation with a given environment."
    (handle (computation)
      (reader.ask (resume)
        (resume env))
      (return (x) x))))
