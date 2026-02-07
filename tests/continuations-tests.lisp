;;;; continuations-tests.lisp
;;;;
;;;; Tests for delimited continuations and CPS standard library.

(in-package #:coalton-tests)

;;; Alias for convenience
(defmacro coalton-cont (&body body)
  `(coalton:coalton ,@body))

;;;
;;; Continuation Type Tests
;;;

(deftest test-cont-pure ()
  "Test that cont-pure lifts a value correctly."
  (is (= 42
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cont-pure 42))))))

(deftest test-cont-functor ()
  "Test the Functor instance for Cont."
  (is (= 84
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/classes:map
            (coalton:fn (x) (coalton-library/classes:* x 2))
            (coalton-library/continuations:cont-pure 42)))))))

(deftest test-cont-monad ()
  "Test the Monad instance for Cont."
  (is (= 52
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/classes:>>= (coalton-library/continuations:cont-pure 42)
                (coalton:fn (x)
                  (coalton-library/continuations:cont-pure (coalton-library/classes:+ x 10)))))))))

(deftest test-cont-bind-chain ()
  "Test chaining multiple cont-bind operations."
  (is (= 15
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/classes:>>=
            (coalton-library/continuations:cont-pure 1)
            (coalton:fn (a)
              (coalton-library/classes:>>=
               (coalton-library/continuations:cont-pure 2)
               (coalton:fn (b)
                 (coalton-library/classes:>>=
                  (coalton-library/continuations:cont-pure 3)
                  (coalton:fn (c)
                    (coalton-library/continuations:cont-pure
                     (coalton-library/classes:+ a (coalton-library/classes:+ b (coalton-library/classes:+ c 9)))))))))))))))

;;;
;;; CPS List Operation Tests
;;;

(deftest test-cps-map ()
  "Test cps-map over a list."
  (is (equal (list 2 4 6)
             (coalton-cont
              (coalton-library/continuations:run-cont
               (coalton-library/continuations:cps-map
                (coalton:fn (x) (coalton-library/continuations:cont-pure (coalton-library/classes:* x 2)))
                (coalton:make-list 1 2 3)))))))

(deftest test-cps-fold ()
  "Test cps-fold for left fold."
  (is (= 15
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-fold
            (coalton:fn (acc x) (coalton-library/continuations:cont-pure (coalton-library/classes:+ acc x)))
            0
            (coalton:make-list 1 2 3 4 5)))))))

(deftest test-cps-filter ()
  "Test cps-filter with a predicate."
  (is (equal (list 2 4)
             (coalton-cont
              (coalton-library/continuations:run-cont
               (coalton-library/continuations:cps-filter
                (coalton:fn (x)
                  (coalton-library/continuations:cont-pure
                   (coalton-library/classes:== (coalton-library/math/integral:mod x 2) 0)))
                (coalton:make-list 1 2 3 4 5)))))))

(deftest test-cps-find ()
  "Test cps-find to locate first match."
  (is (eq coalton:True
          (coalton-cont
           (coalton-library/optional:some?
            (coalton-library/continuations:run-cont
             (coalton-library/continuations:cps-find
              (coalton:fn (x) (coalton-library/continuations:cont-pure (coalton-library/classes:> x 3)))
              (coalton:make-list 1 2 3 4 5))))))))

;;;
;;; CPS Boolean Operation Tests
;;;

(deftest test-cps-all-true ()
  "Test cps-all when all elements satisfy predicate."
  (is (eq coalton:True
          (coalton-cont
           (coalton-library/continuations:run-cont
            (coalton-library/continuations:cps-all
             (coalton:fn (x) (coalton-library/continuations:cont-pure (coalton-library/classes:> x 0)))
             (coalton:make-list 1 2 3 4 5)))))))

(deftest test-cps-all-false ()
  "Test cps-all when not all elements satisfy predicate."
  (is (eq coalton:False
          (coalton-cont
           (coalton-library/continuations:run-cont
            (coalton-library/continuations:cps-all
             (coalton:fn (x) (coalton-library/continuations:cont-pure (coalton-library/classes:> x 3)))
             (coalton:make-list 1 2 3 4 5)))))))

(deftest test-cps-any-true ()
  "Test cps-any when some element satisfies predicate."
  (is (eq coalton:True
          (coalton-cont
           (coalton-library/continuations:run-cont
            (coalton-library/continuations:cps-any
             (coalton:fn (x) (coalton-library/continuations:cont-pure (coalton-library/classes:> x 3)))
             (coalton:make-list 1 2 3 4 5)))))))

(deftest test-cps-any-false ()
  "Test cps-any when no element satisfies predicate."
  (is (eq coalton:False
          (coalton-cont
           (coalton-library/continuations:run-cont
            (coalton-library/continuations:cps-any
             (coalton:fn (x) (coalton-library/continuations:cont-pure (coalton-library/classes:> x 10)))
             (coalton:make-list 1 2 3 4 5)))))))

;;;
;;; CPS Numeric Operation Tests
;;;

(deftest test-cps-sum ()
  "Test cps-sum for summing a list."
  (is (= 15
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-sum
            (coalton:make-list 1 2 3 4 5)))))))

(deftest test-cps-product ()
  "Test cps-product for multiplying a list."
  (is (= 120
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-product
            (coalton:make-list 1 2 3 4 5)))))))

;;;
;;; Sequence Tests
;;;

(deftest test-cps-sequence ()
  "Test cps-sequence for sequencing computations."
  (is (equal (list 1 2 3)
             (coalton-cont
              (coalton-library/continuations:run-cont
               (coalton-library/continuations:cps-sequence
                (coalton:make-list (coalton-library/continuations:cont-pure 1)
                           (coalton-library/continuations:cont-pure 2)
                           (coalton-library/continuations:cont-pure 3))))))))

(deftest test-cps-replicate ()
  "Test cps-replicate for replicating a computation."
  (is (equal (list 42 42 42)
             (coalton-cont
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
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-iterate
            (coalton:fn (x) (coalton-library/continuations:cont-pure (coalton-library/classes:* x 2)))
            5
            1))))))

;;;
;;; Control Operator Tests
;;;

(deftest test-cont-reset ()
  "Test cont-reset for delimiting continuations."
  (is (= 10
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cont-reset
            (coalton-library/continuations:cont-pure 10)))))))

(deftest test-abort-to-prompt ()
  "Test abort-to-prompt for aborting to a delimiter."
  (is (= 99
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cont-reset
            (coalton-library/classes:>>=
             (coalton-library/continuations:abort-to-prompt
              (coalton-library/continuations:MkPrompt coalton:Unit)
              99)
             (coalton:fn (coalton:_)
               ;; This should never be reached
               (coalton-library/continuations:cont-pure 0)))))))))

;;;
;;; CPS Function Combinator Tests
;;;

(deftest test-cps-compose ()
  "Test cps-compose for composing CPS functions."
  (is (= 24
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-compose
            (coalton:fn (x) (coalton-library/continuations:cont-pure (coalton-library/classes:* x 2)))
            (coalton:fn (x) (coalton-library/continuations:cont-pure (coalton-library/classes:+ x 2)))
            10))))))

(deftest test-cps-const ()
  "Test cps-const for constant CPS function."
  (is (= 42
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-const 42 99))))))

(deftest test-cps-id ()
  "Test cps-id for identity CPS function."
  (is (= 42
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/continuations:cps-id 42))))))

;;;
;;; CPS Optional Operation Tests
;;;

(deftest test-cps-map-optional-some ()
  "Test cps-map-optional on Some value."
  (is (= 84
         (coalton-cont
          (coalton:match (coalton-library/continuations:run-cont
                  (coalton-library/continuations:cps-map-optional
                   (coalton:fn (x) (coalton-library/continuations:cont-pure (coalton-library/classes:* x 2)))
                   (coalton:Some 42)))
            ((coalton:Some x) x)
            ((coalton:None) 0))))))

(deftest test-cps-map-optional-none ()
  "Test cps-map-optional on None value."
  (is (eq coalton:True
          (coalton-cont
           (coalton-library/optional:none?
            (coalton-library/continuations:run-cont
             (coalton-library/continuations:cps-map-optional
              (coalton:fn (x) (coalton-library/continuations:cont-pure (coalton-library/classes:* x 2)))
              coalton:None)))))))

;;;
;;; CPS Result Operation Tests
;;;

(deftest test-cps-map-ok ()
  "Test cps-map-ok on Ok value."
  (is (= 84
         (coalton-cont
          (coalton:match (coalton-library/continuations:run-cont
                  (coalton-library/continuations:cps-map-ok
                   (coalton:fn (x) (coalton-library/continuations:cont-pure (coalton-library/classes:* x 2)))
                   (coalton-library/classes:Ok 42)))
            ((coalton-library/classes:Ok x) x)
            ((coalton-library/classes:Err coalton:_) 0))))))

(deftest test-cps-map-err ()
  "Test cps-map-err on Err value."
  (is (equal "ERROR!"
             (coalton-cont
              (coalton:match (coalton-library/continuations:run-cont
                      (coalton-library/continuations:cps-map-err
                       (coalton:fn (e) (coalton-library/continuations:cont-pure
                                (coalton-library/classes:<> e "!")))
                       (coalton:the (coalton-library/classes:Result coalton:String coalton:Integer)
                                    (coalton-library/classes:Err "ERROR"))))
                ((coalton-library/classes:Ok coalton:_) "ok")
                ((coalton-library/classes:Err e) e))))))

;;;
;;; Integration Tests
;;;

(deftest test-cont-complex-chain ()
  "Test complex chaining of continuation operations."
  (is (= 27
         (coalton-cont
          (coalton-library/continuations:run-cont
           (coalton-library/classes:>>=
            (coalton-library/continuations:cps-sum (coalton:make-list 1 2 3 4 5))
            (coalton:fn (sum)
              (coalton-library/classes:>>=
               (coalton-library/continuations:cps-product (coalton:make-list 1 2 3 4))
               (coalton:fn (prod)
                 (coalton-library/continuations:cont-pure
                  (coalton-library/classes:+ sum (coalton-library/math/arith:/ prod 2))))))))))))

