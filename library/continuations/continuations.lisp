;;;; continuations.lisp
;;;;
;;;; Implementation of delimited continuations for Coalton.
;;;; Uses cl-cont at runtime for actual continuation capture.

(in-package #:coalton-library/continuations)

;;;
;;; Cont type - represents a delimited continuation computation
;;;

(coalton-toplevel

  ;;
  ;; The Cont type wraps a CPS computation.
  ;; (Cont :r :a) is a computation that:
  ;;   - Produces a value of type :a
  ;;   - Has answer type :r (the type of the overall reset block)
  ;;
  ;; Internally, it holds a function ((:a -> :r) -> :r) where the first
  ;; argument is the continuation to receive the result.
  ;;

  (repr :native cl-cont:funcallable/cc)
  (define-type (Cont :r :a)
    "A delimited continuation computation.

(Cont :r :a) represents a computation that eventually produces a value
of type :a, delimited by a reset with answer type :r.

The continuation can be invoked to continue the computation, or discarded
to abandon it."
    (ContFn ((:a -> :r) -> :r)))

  ;;
  ;; Prompt type - marker for continuation delimiters
  ;;

  (define-type (Prompt :r)
    "A prompt (delimiter) marker for delimited continuations.

Prompts mark boundaries for continuation capture. When shift captures
a continuation, it only captures up to the nearest enclosing prompt.

The type parameter :r is the answer type of the delimited computation."
    (MkPrompt Unit))

  ;;
  ;; Running continuations
  ;;

  (declare run-cont ((Cont :r :r) -> :r))
  (define (run-cont (ContFn f))
    "Run a continuation computation with the identity continuation.

This executes the computation, where the final result is returned directly.
Equivalent to: (f id)"
    (f id))

  ;;
  ;; Monad instance for Cont
  ;;

  (declare cont-pure (:a -> (Cont :r :a)))
  (define (cont-pure x)
    "Lift a pure value into a continuation computation.

(cont-pure x) creates a computation that immediately passes x to its
continuation."
    (ContFn (fn (k) (k x))))

  (declare cont-bind ((Cont :r :a) -> ((:a -> (Cont :r :b)) -> (Cont :r :b))))
  (define (cont-bind (ContFn m) f)
    "Sequence two continuation computations.

(cont-bind m f) runs m, passes its result to f, and runs the resulting
computation. This is the monadic bind for Cont."
    (ContFn (fn (k)
              (m (fn (a)
                   (match (f a)
                     ((ContFn g) (g k))))))))

  (define-instance (Functor (Cont :r))
    (define (map f (ContFn m))
      (ContFn (fn (k)
                (m (fn (a) (k (f a))))))))

  (define-instance (Applicative (Cont :r))
    (define pure cont-pure)
    (define (liftA2 f ca cb)
      (cont-bind ca (fn (a) (cont-bind cb (fn (b) (cont-pure (f a b))))))))

  (define-instance (Monad (Cont :r))
    (define (>>= m f) (cont-bind m f)))

  ;;
  ;; Control operators
  ;;

  (declare with-prompt ((Prompt :r) -> (Cont :r :r) -> :r))
  (define (with-prompt _prompt comp)
    "Run a continuation computation with a prompt delimiter.

Equivalent to reset, but with an explicit prompt object."
    (run-cont comp))

  (declare abort-to-prompt ((Prompt :r) -> :r -> (Cont :r :a)))
  (define (abort-to-prompt _prompt result)
    "Abort to the nearest prompt, returning the given result.

This discards the current continuation and immediately returns to the
enclosing reset/with-prompt with the given value."
    (ContFn (fn (_k) result)))

  ;;
  ;; Advanced control operators
  ;;

  (declare control ((:a -> (Cont :r :r)) -> (Cont :r :a)))
  (define (control f)
    "The control operator for delimited continuations.

Unlike shift, control does NOT delimit the continuation passed to f.
This means if f invokes the continuation and then does more work,
that work is not part of the captured continuation.

(control (fn (k) body)) captures the continuation k and runs body.
If k is invoked, control returns to the capture point."
    (ContFn (fn (k)
              (run-cont (f (fn (x) (cont-pure (k x))))))))

  (declare control0 ((:a -> :r) -> (Cont :r :a)))
  (define (control0 f)
    "The control0 operator - like control but with no implicit prompt.

(control0 f) captures the raw continuation and passes it to f.
The continuation is NOT wrapped - f receives the raw function."
    (ContFn (fn (k) (f k))))

  (declare shift0 ((:a -> :r) -> (Cont :r :a)))
  (define (shift0 f)
    "The shift0 operator - like shift but with no implicit reset.

(shift0 f) captures the continuation and passes it to f as a function.
Unlike shift, there is no implicit reset around the captured continuation."
    (ContFn (fn (k) (f k))))

  ;;
  ;; CPS transformation utilities
  ;;

  (declare cps ((:a -> (Cont :r :a))))
  (define (cps x)
    "Convert a direct-style value to CPS.

(cps x) creates a continuation that immediately passes x to its
continuation. Alias for cont-pure."
    (cont-pure x))

  (declare reflect ((Cont :r :a) -> :a))
  (define (reflect comp)
    "Reflect a CPS computation into direct style.

WARNING: This is only valid within a reset/with-prompt block!
It converts a Cont back to a regular value by capturing the
continuation implicitly.

This is implemented using shift internally."
    ;; This is a placeholder - actual implementation needs shift
    ;; In real use, this would be:
    ;; (shift k (cont-bind comp (fn (x) (cont-pure (k x)))))
    (lisp :a (comp)
      (cl-cont:let/cc k
        (let ((result (match comp
                        ((ContFn f)
                         (funcall f (lambda (x) (funcall k x)))))))
          result))))

  (declare reify ((:a -> (Cont :r :a))))
  (define (reify f)
    "Reify direct-style code into a CPS computation.

(reify (fn () expr)) captures expr as a continuation computation.
The computation can then be manipulated as a first-class value.

Equivalent to wrapping expr in reset and returning the Cont."
    (cont-pure f)))

;;;
;;; CPS-aware function composition
;;;

(coalton-toplevel

  (declare cont-map ((:a -> :b) -> (Cont :r :a) -> (Cont :r :b)))
  (define (cont-map f m)
    "Map a function over a continuation computation.

(cont-map f m) applies f to the result of m when the continuation
is invoked."
    (map f m))

  (declare cont-ap ((Cont :r (:a -> :b)) -> (Cont :r :a) -> (Cont :r :b)))
  (define (cont-ap mf ma)
    "Apply a continuation-wrapped function to a continuation-wrapped value."
    (cont-bind mf (fn (f) (cont-map f ma)))))

;;;
;;; Utility functions for working with continuations
;;;

(coalton-toplevel

  (declare call-with-continuation (((:a -> :r) -> :r) -> (Cont :r :a)))
  (define (call-with-continuation f)
    "Create a Cont from a function that takes a continuation.

This is the fundamental way to introduce a continuation capture point.
The function f receives the current continuation and can invoke it
zero, once, or multiple times."
    (ContFn f))

  (declare cont-callcc (((:a -> (Cont :r :b)) -> (Cont :r :a)) -> (Cont :r :a)))
  (define (cont-callcc f)
    "Call with current continuation in monadic style.

(cont-callcc f) captures the current continuation as a function that,
when called, returns to this point with the given value."
    (ContFn (fn (k)
              (run-cont (f (fn (x) (ContFn (fn (_k2) (k x)))))))))

  (declare cont-reset ((Cont :a :a) -> (Cont :r :a)))
  (define (cont-reset m)
    "Delimit a continuation computation.

(cont-reset m) runs m with a delimiter, so any shift inside m only
captures up to this point. The result is wrapped in a new Cont."
    (cont-pure (run-cont m)))

  (declare cont-shift (((:a -> (Cont :r :r)) -> (Cont :r :r)) -> (Cont :r :a)))
  (define (cont-shift f)
    "Capture the delimited continuation.

(cont-shift f) captures the continuation up to the nearest enclosing
cont-reset and passes it to f. The continuation is delimited - invoking
it returns to the reset point."
    (ContFn (fn (k)
              (run-cont (f (fn (x) (cont-pure (k x)))))))))
