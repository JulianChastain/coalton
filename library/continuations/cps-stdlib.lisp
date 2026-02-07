;;;; cps-stdlib.lisp
;;;;
;;;; CPS-transformed versions of standard library functions.
;;;; These functions are in continuation-passing style, making them
;;;; compatible with delimited continuation operations.

(in-package #:coalton-library/continuations)

(named-readtables:in-readtable coalton:coalton)

#+coalton-release
(cl:declaim #.coalton-impl/settings:*coalton-optimize-library*)

;;;
;;; CPS List Operations
;;;

(coalton-toplevel

  ;;
  ;; CPS map - traverses a list, applying a function in CPS
  ;;

  (declare cps-map ((:a -> (Cont :r :b)) -> (List :a) -> (Cont :r (List :b))))
  (define (cps-map f lst)
    "Map a CPS function over a list.

(cps-map f lst) applies f to each element of lst, threading the continuation
through each application. Effects from f are sequenced left-to-right."
    (match lst
      ((Nil) (cont-pure Nil))
      ((Cons x xs)
       (cont-bind (f x)
                  (fn (y)
                    (cont-bind (cps-map f xs)
                               (fn (ys)
                                 (cont-pure (Cons y ys)))))))))

  (declare cps-for-each ((:a -> (Cont :r Unit)) -> (List :a) -> (Cont :r Unit)))
  (define (cps-for-each f lst)
    "Apply a CPS function to each element of a list for effects only."
    (match lst
      ((Nil) (cont-pure Unit))
      ((Cons x xs)
       (cont-bind (f x)
                  (fn (_)
                    (cps-for-each f xs))))))

  ;;
  ;; CPS fold operations
  ;;

  (declare cps-fold ((:b -> :a -> (Cont :r :b)) -> :b -> (List :a) -> (Cont :r :b)))
  (define (cps-fold f init lst)
    "Left fold with a CPS accumulator function.

(cps-fold f init lst) folds lst left-to-right, threading continuations.
f is called with the accumulator and each element."
    (match lst
      ((Nil) (cont-pure init))
      ((Cons x xs)
       (cont-bind (f init x)
                  (fn (acc)
                    (cps-fold f acc xs))))))

  (declare cps-fold-right ((:a -> :b -> (Cont :r :b)) -> :b -> (List :a) -> (Cont :r :b)))
  (define (cps-fold-right f init lst)
    "Right fold with a CPS element function.

(cps-fold-right f init lst) folds lst right-to-left."
    (match lst
      ((Nil) (cont-pure init))
      ((Cons x xs)
       (cont-bind (cps-fold-right f init xs)
                  (fn (acc)
                    (f x acc))))))

  ;;
  ;; CPS filter
  ;;

  (declare cps-filter ((:a -> (Cont :r Boolean)) -> (List :a) -> (Cont :r (List :a))))
  (define (cps-filter pred lst)
    "Filter a list with a CPS predicate.

(cps-filter pred lst) keeps elements where pred returns True."
    (match lst
      ((Nil) (cont-pure Nil))
      ((Cons x xs)
       (cont-bind (pred x)
                  (fn (keep)
                    (cont-bind (cps-filter pred xs)
                               (fn (rest)
                                 (if keep
                                     (cont-pure (Cons x rest))
                                     (cont-pure rest)))))))))

  ;;
  ;; CPS find
  ;;

  (declare cps-find ((:a -> (Cont :r Boolean)) -> (List :a) -> (Cont :r (Optional :a))))
  (define (cps-find pred lst)
    "Find the first element satisfying a CPS predicate."
    (match lst
      ((Nil) (cont-pure None))
      ((Cons x xs)
       (cont-bind (pred x)
                  (fn (found)
                    (if found
                        (cont-pure (Some x))
                        (cps-find pred xs))))))))

;;;
;;; CPS Optional Operations
;;;

(coalton-toplevel

  (declare cps-map-optional ((:a -> (Cont :r :b)) -> (Optional :a) -> (Cont :r (Optional :b))))
  (define (cps-map-optional f opt)
    "Map a CPS function over an Optional."
    (match opt
      ((None) (cont-pure None))
      ((Some x) (cont-bind (f x) (fn (y) (cont-pure (Some y)))))))

  (declare cps-and-then ((:a -> (Cont :r (Optional :b))) -> (Optional :a) -> (Cont :r (Optional :b))))
  (define (cps-and-then f opt)
    "Monadic bind for Optional in CPS."
    (match opt
      ((None) (cont-pure None))
      ((Some x) (f x)))))

;;;
;;; CPS Result Operations
;;;

(coalton-toplevel

  (declare cps-map-ok ((:a -> (Cont :r :b)) -> (Result :e :a) -> (Cont :r (Result :e :b))))
  (define (cps-map-ok f res)
    "Map a CPS function over the Ok case of a Result."
    (match res
      ((Err e) (cont-pure (Err e)))
      ((Ok x) (cont-bind (f x) (fn (y) (cont-pure (Ok y)))))))

  (declare cps-map-err ((:e -> (Cont :r :f)) -> (Result :e :a) -> (Cont :r (Result :f :a))))
  (define (cps-map-err f res)
    "Map a CPS function over the Err case of a Result."
    (match res
      ((Ok x) (cont-pure (Ok x)))
      ((Err e) (cont-bind (f e) (fn (e2) (cont-pure (Err e2)))))))

  (declare cps-and-then-result ((:a -> (Cont :r (Result :e :b))) -> (Result :e :a) -> (Cont :r (Result :e :b))))
  (define (cps-and-then-result f res)
    "Monadic bind for Result in CPS."
    (match res
      ((Err e) (cont-pure (Err e)))
      ((Ok x) (f x)))))

;;;
;;; CPS Function Combinators
;;;

(coalton-toplevel

  (declare cps-compose ((:b -> (Cont :r :c)) -> (:a -> (Cont :r :b)) -> :a -> (Cont :r :c)))
  (define (cps-compose g f x)
    "Compose two CPS functions.

(cps-compose g f) is like (compose g f) but for CPS functions.
First applies f, then g to the result."
    (cont-bind (f x) g))

  (declare cps-flip ((:a -> :b -> (Cont :r :c)) -> :b -> :a -> (Cont :r :c)))
  (define (cps-flip f b a)
    "Flip the arguments of a CPS function."
    (f a b))

  (declare cps-const (:a -> :b -> (Cont :r :a)))
  (define (cps-const a _b)
    "CPS constant function - ignores second argument."
    (cont-pure a))

  (declare cps-id (:a -> (Cont :r :a)))
  (define (cps-id x)
    "CPS identity function."
    (cont-pure x)))

;;;
;;; CPS Numeric Operations
;;;

(coalton-toplevel

  (declare cps-sum ((Num :a) => (List :a) -> (Cont :r :a)))
  (define (cps-sum lst)
    "Sum a list of numbers in CPS."
    (cps-fold (fn (acc x) (cont-pure (+ acc x))) (fromInt 0) lst))

  (declare cps-product ((Num :a) => (List :a) -> (Cont :r :a)))
  (define (cps-product lst)
    "Multiply a list of numbers in CPS."
    (cps-fold (fn (acc x) (cont-pure (* acc x))) (fromInt 1) lst)))

;;;
;;; CPS Boolean Operations
;;;

(coalton-toplevel

  (declare cps-all ((:a -> (Cont :r Boolean)) -> (List :a) -> (Cont :r Boolean)))
  (define (cps-all pred lst)
    "Check if all elements satisfy a CPS predicate.

Short-circuits on first False."
    (match lst
      ((Nil) (cont-pure True))
      ((Cons x xs)
       (cont-bind (pred x)
                  (fn (result)
                    (if result
                        (cps-all pred xs)
                        (cont-pure False)))))))

  (declare cps-any ((:a -> (Cont :r Boolean)) -> (List :a) -> (Cont :r Boolean)))
  (define (cps-any pred lst)
    "Check if any element satisfies a CPS predicate.

Short-circuits on first True."
    (match lst
      ((Nil) (cont-pure False))
      ((Cons x xs)
       (cont-bind (pred x)
                  (fn (result)
                    (if result
                        (cont-pure True)
                        (cps-any pred xs))))))))

;;;
;;; CPS Traversable-like Operations
;;;

(coalton-toplevel

  (declare cps-sequence ((List (Cont :r :a)) -> (Cont :r (List :a))))
  (define (cps-sequence lst)
    "Sequence a list of CPS computations.

(cps-sequence [m1, m2, ...]) runs each computation in order and
collects the results into a list."
    (cps-map id lst))

  (declare cps-sequence_ ((List (Cont :r Unit)) -> (Cont :r Unit)))
  (define (cps-sequence_ lst)
    "Sequence CPS computations for effects only."
    (match lst
      ((Nil) (cont-pure Unit))
      ((Cons m ms)
       (cont-bind m (fn (_) (cps-sequence_ ms))))))

  (declare cps-replicate (UFix -> (Cont :r :a) -> (Cont :r (List :a))))
  (define (cps-replicate n m)
    "Replicate a CPS computation n times and collect results."
    (if (== n 0)
        (cont-pure Nil)
        (cont-bind m
                   (fn (x)
                     (cont-bind (cps-replicate (- n 1) m)
                                (fn (xs)
                                  (cont-pure (Cons x xs)))))))))

;;;
;;; CPS Iteration
;;;

(coalton-toplevel

  (declare cps-iterate ((:a -> (Cont :r :a)) -> UFix -> :a -> (Cont :r :a)))
  (define (cps-iterate f n x)
    "Iterate a CPS function n times.

(cps-iterate f 3 x) is like f(f(f(x))) but in CPS."
    (if (== n 0)
        (cont-pure x)
        (cont-bind (f x)
                   (fn (y)
                     (cps-iterate f (- n 1) y)))))

  (declare cps-unfold ((:b -> (Cont :r (Optional (Tuple :a :b)))) -> :b -> (Cont :r (List :a))))
  (define (cps-unfold f seed)
    "Unfold a list from a seed using a CPS generator function.

f should return Some (value, next-seed) to continue or None to stop."
    (cont-bind (f seed)
               (fn (result)
                 (match result
                   ((None) (cont-pure Nil))
                   ((Some (Tuple x next))
                    (cont-bind (cps-unfold f next)
                               (fn (xs)
                                 (cont-pure (Cons x xs))))))))))

;;;
;;; CPS Exception-like Control
;;;

(coalton-toplevel

  (declare cps-catch ((Cont :r (Result :e :a)) -> (:e -> (Cont :r :a)) -> (Cont :r :a)))
  (define (cps-catch m handler)
    "Catch errors in a CPS computation.

Runs m, and if it produces an Err, passes it to handler."
    (cont-bind m
               (fn (result)
                 (match result
                   ((Ok x) (cont-pure x))
                   ((Err e) (handler e))))))

  (declare cps-throw (:e -> (Cont :r (Result :e :a))))
  (define (cps-throw e)
    "Throw an error in CPS."
    (cont-pure (Err e)))

  (declare cps-try ((Cont :r :a) -> (:a -> (Cont :r :b)) -> (Cont :r :b)))
  (define (cps-try m f)
    "Try a computation and transform its result."
    (cont-bind m f)))
