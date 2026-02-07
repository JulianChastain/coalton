(in-package #:coalton-library/effects)

(coalton-toplevel

  ;;;
  ;;; Effect Combinators
  ;;;
  ;;; Common utilities for working with effects.
  ;;;

  (declare pure (:a -> :a))
  (define (pure x)
    "Lift a pure value into an effectful context.

This is the identity function but with an explicit Pure effect annotation."
    x)

  (declare with-effect ((:a -> :b) -> :a -> :b))
  (define (with-effect f x)
    "Apply a pure function to an effectful value.

Equivalent to: (f x) but preserves effect annotations."
    (f x)))
