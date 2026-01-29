;;;; continuations-tests.lisp
;;;;
;;;; Tests for delimited continuations and CPS standard library.

(in-package #:coalton-tests)

;;;
;;; Continuation Type Tests
;;;

(deftest test-cont-pure ()
  "Test that cont-pure lifts a value correctly."
  (is (= 42
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cont-pure 42))))))

(deftest test-cont-functor ()
  "Test the Functor instance for Cont."
  (is (= 84
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (coalton-library/classes:map (fn (x) (* x 2))
                                        (coalton-library/continuations:cont-pure 42)))))))

(deftest test-cont-monad ()
  "Test the Monad instance for Cont."
  (is (= 52
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (>>= (coalton-library/continuations:cont-pure 42)
                (fn (x)
                  (coalton-library/continuations:cont-pure (+ x 10)))))))))

(deftest test-cont-bind-chain ()
  "Test chaining multiple cont-bind operations."
  (is (= 15
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (>>= (coalton-library/continuations:cont-pure 1)
                (fn (a)
                  (>>= (coalton-library/continuations:cont-pure 2)
                       (fn (b)
                         (>>= (coalton-library/continuations:cont-pure 3)
                              (fn (c)
                                (coalton-library/continuations:cont-pure
                                 (+ a (+ b (+ c 9)))))))))))))))

;;;
;;; CPS List Operation Tests
;;;

(deftest test-cps-map ()
  "Test cps-map over a list."
  (is (equal (list 2 4 6)
             (coalton:coalton
              (coalton-library/continuations:run-cont
               (coalton-library/continuations:cps-map
                (fn (x) (coalton-library/continuations:cont-pure (* x 2)))
                (make-list 1 2 3)))))))

(deftest test-cps-fold ()
  "Test cps-fold for left fold."
  (is (= 15
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-fold
            (fn (acc x) (coalton-library/continuations:cont-pure (+ acc x)))
            0
            (make-list 1 2 3 4 5)))))))

(deftest test-cps-filter ()
  "Test cps-filter with a predicate."
  (is (equal (list 2 4)
             (coalton:coalton
              (coalton-library/continuations:run-cont
               (coalton-library/continuations:cps-filter
                (fn (x) (coalton-library/continuations:cont-pure (== (mod x 2) 0)))
                (make-list 1 2 3 4 5)))))))

(deftest test-cps-find ()
  "Test cps-find to locate first match."
  (is (eq 'coalton:True
          (coalton:coalton
           (coalton-library/classes:some?
            (coalton-library/continuations:run-cont
             (coalton-library/continuations:cps-find
              (fn (x) (coalton-library/continuations:cont-pure (> x 3)))
              (make-list 1 2 3 4 5))))))))

;;;
;;; CPS Boolean Operation Tests
;;;

(deftest test-cps-all-true ()
  "Test cps-all when all elements satisfy predicate."
  (is (eq 'coalton:True
          (coalton:coalton
           (coalton-library/continuations:run-cont
            (coalton-library/continuations:cps-all
             (fn (x) (coalton-library/continuations:cont-pure (> x 0)))
             (make-list 1 2 3 4 5)))))))

(deftest test-cps-all-false ()
  "Test cps-all when not all elements satisfy predicate."
  (is (eq 'coalton:False
          (coalton:coalton
           (coalton-library/continuations:run-cont
            (coalton-library/continuations:cps-all
             (fn (x) (coalton-library/continuations:cont-pure (> x 3)))
             (make-list 1 2 3 4 5)))))))

(deftest test-cps-any-true ()
  "Test cps-any when some element satisfies predicate."
  (is (eq 'coalton:True
          (coalton:coalton
           (coalton-library/continuations:run-cont
            (coalton-library/continuations:cps-any
             (fn (x) (coalton-library/continuations:cont-pure (> x 3)))
             (make-list 1 2 3 4 5)))))))

(deftest test-cps-any-false ()
  "Test cps-any when no element satisfies predicate."
  (is (eq 'coalton:False
          (coalton:coalton
           (coalton-library/continuations:run-cont
            (coalton-library/continuations:cps-any
             (fn (x) (coalton-library/continuations:cont-pure (> x 10)))
             (make-list 1 2 3 4 5)))))))

;;;
;;; CPS Numeric Operation Tests
;;;

(deftest test-cps-sum ()
  "Test cps-sum for summing a list."
  (is (= 15
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-sum
            (make-list 1 2 3 4 5)))))))

(deftest test-cps-product ()
  "Test cps-product for multiplying a list."
  (is (= 120
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-product
            (make-list 1 2 3 4 5)))))))

;;;
;;; CPS Sequence Tests
;;;

(deftest test-cps-sequence ()
  "Test cps-sequence for sequencing computations."
  (is (equal (list 1 2 3)
             (coalton:coalton
              (coalton-library/continuations:run-cont
               (coalton-library/continuations:cps-sequence
                (make-list (coalton-library/continuations:cont-pure 1)
                           (coalton-library/continuations:cont-pure 2)
                           (coalton-library/continuations:cont-pure 3))))))))

(deftest test-cps-replicate ()
  "Test cps-replicate for replicating a computation."
  (is (equal (list 42 42 42)
             (coalton:coalton
              (coalton-library/continuations:run-cont
               (coalton-library/continuations:cps-replicate
                3
                (coalton-library/continuations:cont-pure 42)))))))

;;;
;;; CPS Iteration Tests
;;;

(deftest test-cps-iterate ()
  "Test cps-iterate for iterating a function."
  (is (= 32
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-iterate
            (fn (x) (coalton-library/continuations:cont-pure (* x 2)))
            5
            1))))))

;;;
;;; Control Operator Tests
;;;

(deftest test-cont-reset ()
  "Test cont-reset for delimiting continuations."
  (is (= 10
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cont-reset
            (coalton-library/continuations:cont-pure 10)))))))

(deftest test-abort-to-prompt ()
  "Test abort-to-prompt for aborting to a delimiter."
  (is (= 99
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cont-reset
            (>>= (coalton-library/continuations:abort-to-prompt
                  (coalton-library/continuations:MkPrompt Unit)
                  99)
                 (fn (_)
                   ;; This should never be reached
                   (coalton-library/continuations:cont-pure 0)))))))))

;;;
;;; CPS Function Combinator Tests
;;;

(deftest test-cps-compose ()
  "Test cps-compose for composing CPS functions."
  (is (= 24
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-compose
            (fn (x) (coalton-library/continuations:cont-pure (* x 2)))
            (fn (x) (coalton-library/continuations:cont-pure (+ x 2)))
            10))))))

(deftest test-cps-const ()
  "Test cps-const for constant CPS function."
  (is (= 42
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-const 42 99))))))

(deftest test-cps-id ()
  "Test cps-id for identity CPS function."
  (is (= 42
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-id 42))))))

;;;
;;; CPS Optional Operation Tests
;;;

(deftest test-cps-map-optional-some ()
  "Test cps-map-optional on Some value."
  (is (= 84
         (coalton:coalton
          (match (coalton-library/continuations:run-cont
                  (coalton-library/continuations:cps-map-optional
                   (fn (x) (coalton-library/continuations:cont-pure (* x 2)))
                   (Some 42)))
            ((Some x) x)
            ((None) 0))))))

(deftest test-cps-map-optional-none ()
  "Test cps-map-optional on None value."
  (is (eq 'coalton:True
          (coalton:coalton
           (coalton-library/classes:none?
            (coalton-library/continuations:run-cont
             (coalton-library/continuations:cps-map-optional
              (fn (x) (coalton-library/continuations:cont-pure (* x 2)))
              None)))))))

;;;
;;; CPS Result Operation Tests
;;;

(deftest test-cps-map-ok ()
  "Test cps-map-ok on Ok value."
  (is (= 84
         (coalton:coalton
          (match (coalton-library/continuations:run-cont
                  (coalton-library/continuations:cps-map-ok
                   (fn (x) (coalton-library/continuations:cont-pure (* x 2)))
                   (Ok 42)))
            ((Ok x) x)
            ((Err _) 0))))))

(deftest test-cps-map-err ()
  "Test cps-map-err on Err value."
  (is (equal "ERROR!"
             (coalton:coalton
              (match (coalton-library/continuations:run-cont
                      (coalton-library/continuations:cps-map-err
                       (fn (e) (coalton-library/continuations:cont-pure
                                (<> e "!")))
                       (the (Result String Integer) (Err "ERROR"))))
                ((Ok _) "ok")
                ((Err e) e))))))

;;;
;;; Integration Tests
;;;

(deftest test-cont-complex-chain ()
  "Test complex chaining of continuation operations."
  (is (= 60
         (coalton:coalton
          (coalton-library/continuations:run-cont
           (>>= (coalton-library/continuations:cps-sum (make-list 1 2 3 4 5))
                (fn (sum)
                  (>>= (coalton-library/continuations:cps-product (make-list 1 2 3 4))
                       (fn (prod)
                         (coalton-library/continuations:cont-pure
                          (+ sum (/ prod 2))))))))))))

;;;
;;; Run all continuation tests
;;;

(defun run-continuation-tests ()
  "Run all continuation tests."
  (run! 'test-cont-pure)
  (run! 'test-cont-functor)
  (run! 'test-cont-monad)
  (run! 'test-cont-bind-chain)
  (run! 'test-cps-map)
  (run! 'test-cps-fold)
  (run! 'test-cps-filter)
  (run! 'test-cps-find)
  (run! 'test-cps-all-true)
  (run! 'test-cps-all-false)
  (run! 'test-cps-any-true)
  (run! 'test-cps-any-false)
  (run! 'test-cps-sum)
  (run! 'test-cps-product)
  (run! 'test-cps-sequence)
  (run! 'test-cps-replicate)
  (run! 'test-cps-iterate)
  (run! 'test-cont-reset)
  (run! 'test-abort-to-prompt)
  (run! 'test-cps-compose)
  (run! 'test-cps-const)
  (run! 'test-cps-id)
  (run! 'test-cps-map-optional-some)
  (run! 'test-cps-map-optional-none)
  (run! 'test-cps-map-ok)
  (run! 'test-cps-map-err)
  (run! 'test-cont-complex-chain))
