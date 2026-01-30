(cl:in-package #:coalton-native-tests)

;;
;; This test case is ported from the Hacket fundep example here:
;; github.com/lexi-lambda/hackett/blob/master/hackett-test/tests/hackett/integration/fundeps-arithmetic.rkt
;;
;; NOTE: Temporarily disabled on subtypes branch due to type unification issue
;; with EQ types. The error is "Failed to unify types EQ #T122 and EQ #T91"
;; This needs to be fixed in the subtyping implementation.
;;

#|
(coalton-toplevel
  (define-type (Proxy :a)
    Proxy)

  (define-type Z)
  (define-type (S :n))

  (declare sub1 (Proxy (S :n) -> Proxy :n))
  (define (sub1 _)
    Proxy)

  (define-class (ReifyPeano :n)
    (reify-peano (Proxy :n -> Integer)))
  (define-instance (ReifyPeano Z)
    (define (reify-peano _)
      0))
  (define-instance (ReifyPeano :n => ReifyPeano (S :n))
    (define (reify-peano p)
      (+ 1 (reify-peano (sub1 p)))))

  (define-class (Add :a :b :c (:a :b -> :c)))
  (define-instance (Add Z :a :a))
  (define-instance ((Add :a :b :c) => Add (S :a) :b (S :c)))

  (define-class (Fib :a :b (:a -> :b)))
  (define-instance (Fib Z Z))
  (define-instance (Fib (S Z) (S Z)))
  (define-instance ((Fib :a :b) (Fib (S :a) :c) (Add :b :c :d) => Fib (S (S :a)) :d))

  (declare fib (Fib :a :b => Proxy :a -> Proxy :b))
  (define (fib _)
    Proxy))

(define-test test-fundep-fib ()
  (is (== 0 (reify-peano (fib (the (Proxy Z) Proxy)))))
  (is (== 1 (reify-peano (fib (the (Proxy (S Z)) Proxy)))))
  (is (== 1 (reify-peano (fib (the (Proxy (S (S Z))) Proxy)))))
  (is (== 2 (reify-peano (fib (the (Proxy (S (S (S Z)))) Proxy)))))
  (is (== 3 (reify-peano (fib (the (Proxy (S (S (S (S Z))))) Proxy)))))
  (is (== 5 (reify-peano (fib (the (Proxy (S (S (S (S (S Z)))))) Proxy))))))
|#
