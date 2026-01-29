;;;; subtyping-tests.lisp
;;;;
;;;; Unit tests for the algebraic subtyping infrastructure
;;;;

(in-package #:coalton-tests)

;;;
;;; Type structure tests
;;;

(deftest test-tyvar-sub-creation ()
  "Test creation of bounded type variables."
  (tc:reset-levels)
  (let ((var (tc:make-variable-at-level tc:+kstar+ 0)))
    (is (tc:tyvar-sub-p var))
    (is (= 0 (tc:tyvar-sub-level var)))
    (is (null (tc:tyvar-sub-lower-bounds var)))
    (is (null (tc:tyvar-sub-upper-bounds var)))))

(deftest test-ty-top-bot ()
  "Test top and bottom type creation and properties."
  (let ((top tc:+ty-top+)
        (bot tc:+ty-bot+))
    (is (tc:ty-top-p top))
    (is (tc:ty-bot-p bot))
    (is (tc:ty= top top))
    (is (tc:ty= bot bot))
    (is (not (tc:ty= top bot)))))

(deftest test-ty-union-creation ()
  "Test union type creation."
  (let ((union (tc:make-ty-union
                :members (list tc:*integer-type* tc:*string-type*))))
    (is (tc:ty-union-p union))
    (is (= 2 (length (tc:ty-union-members union))))))

(deftest test-ty-intersection-creation ()
  "Test intersection type creation."
  (let ((intersection (tc:make-ty-intersection
                       :members (list tc:*integer-type* tc:*string-type*))))
    (is (tc:ty-intersection-p intersection))
    (is (= 2 (length (tc:ty-intersection-members intersection))))))

;;;
;;; Constraint propagation tests
;;;

(deftest test-constrain-reflexive ()
  "Test that T <= T for any type T."
  (is (tc:constrain tc:*integer-type* tc:*integer-type*))
  (is (tc:constrain tc:*string-type* tc:*string-type*)))

(deftest test-constrain-bot-subtype ()
  "Test that bot <= T for any type T."
  (is (tc:constrain tc:+ty-bot+ tc:*integer-type*))
  (is (tc:constrain tc:+ty-bot+ tc:*string-type*))
  (is (tc:constrain tc:+ty-bot+ tc:+ty-top+)))

(deftest test-constrain-top-supertype ()
  "Test that T <= top for any type T."
  (is (tc:constrain tc:*integer-type* tc:+ty-top+))
  (is (tc:constrain tc:*string-type* tc:+ty-top+))
  (is (tc:constrain tc:+ty-bot+ tc:+ty-top+)))

(deftest test-constrain-tycon-mismatch ()
  "Test that different type constructors cannot be constrained."
  (signals tc:constraint-error
    (tc:constrain tc:*integer-type* tc:*string-type*)))

(deftest test-constrain-upper-bound-addition ()
  "Test adding upper bounds to a type variable."
  (tc:reset-levels)
  (let ((var (tc:make-variable-at-level)))
    (tc:add-upper-bound var tc:*integer-type*)
    (is (= 1 (length (tc:tyvar-sub-upper-bounds var))))
    (is (tc:ty= tc:*integer-type*
                (first (tc:tyvar-sub-upper-bounds var))))))

(deftest test-constrain-lower-bound-addition ()
  "Test adding lower bounds to a type variable."
  (tc:reset-levels)
  (let ((var (tc:make-variable-at-level)))
    (tc:add-lower-bound var tc:*integer-type*)
    (is (= 1 (length (tc:tyvar-sub-lower-bounds var))))
    (is (tc:ty= tc:*integer-type*
                (first (tc:tyvar-sub-lower-bounds var))))))

(deftest test-constrain-propagation ()
  "Test that constraints propagate through bounds."
  (tc:reset-levels)
  (let ((var (tc:make-variable-at-level)))
    ;; Add Integer as lower bound
    (tc:add-lower-bound var tc:*integer-type*)
    ;; Add String as upper bound - this should trigger Integer <= String check
    (signals tc:constraint-error
      (tc:add-upper-bound var tc:*string-type*))))

(deftest test-constrain-var-to-var ()
  "Test constraining one variable to another."
  (tc:reset-levels)
  (let ((var1 (tc:make-variable-at-level))
        (var2 (tc:make-variable-at-level)))
    (tc:constrain var1 var2)
    ;; var1 should have var2 as upper bound
    (is (member var2 (tc:tyvar-sub-upper-bounds var1)))
    ;; var2 should have var1 as lower bound
    (is (member var1 (tc:tyvar-sub-lower-bounds var2)))))

(deftest test-constrain-function-type-covariance ()
  "Test covariance in function return types."
  ;; If A <= B, then (T -> A) <= (T -> B)
  ;; We can't directly test this with Integer/String, but we can test
  ;; that the constraint system handles function types correctly
  (tc:reset-levels)
  (let* ((func1 (tc:make-function-type tc:*integer-type* tc:*integer-type*))
         (func2 (tc:make-function-type tc:*integer-type* tc:*integer-type*)))
    (is (tc:constrain func1 func2))))

(deftest test-constrain-function-type-contravariance ()
  "Test contravariance in function argument types."
  ;; (B -> T) <= (A -> T) when A <= B (contravariant)
  (tc:reset-levels)
  (let* ((func1 (tc:make-function-type tc:*integer-type* tc:*string-type*))
         (func2 (tc:make-function-type tc:*string-type* tc:*string-type*)))
    ;; These should not be compatible
    (signals tc:constraint-error
      (tc:constrain func1 func2))))

(deftest test-constrain-function-type-mismatch ()
  "Test that mismatched function types fail to constrain."
  (let* ((func1 (tc:make-function-type tc:*integer-type* tc:*integer-type*))
         (func2 (tc:make-function-type tc:*integer-type* tc:*string-type*)))
    (signals tc:constraint-error
      (tc:constrain func1 func2))))

;;;
;;; Level-based polymorphism tests
;;;

(deftest test-level-tracking ()
  "Test that levels are tracked correctly."
  (tc:reset-levels)
  (is (= 0 tc:*current-level*))
  (tc:with-new-level ()
    (is (= 1 tc:*current-level*))
    (tc:with-new-level ()
      (is (= 2 tc:*current-level*))))
  (is (= 0 tc:*current-level*)))

(deftest test-variable-level-assignment ()
  "Test that variables are assigned the correct level."
  (tc:reset-levels)
  (let ((outer-var (tc:make-variable-at-current-level)))
    (is (= 0 (tc:tyvar-sub-level outer-var)))
    (tc:with-new-level ()
      (let ((inner-var (tc:make-variable-at-current-level)))
        (is (= 1 (tc:tyvar-sub-level inner-var)))))))

(deftest test-generalization-check ()
  "Test can-generalize-p predicate."
  (tc:reset-levels)
  (tc:with-new-level ()
    (let ((var (tc:make-variable-at-current-level)))
      ;; At level 1, var can be generalized when exiting to level 0
      (is (tc:can-generalize-p var 0))))
  (let ((var (tc:make-variable-at-current-level)))
    ;; At level 0, var cannot be generalized at level 0 (same level)
    (is (not (tc:can-generalize-p var 0)))))

(deftest test-extrusion ()
  "Test type extrusion to lower levels."
  (tc:reset-levels)
  (tc:with-new-level ()
    (let ((var (tc:make-variable-at-current-level)))
      (is (= 1 (tc:tyvar-sub-level var)))
      ;; Extrude to level 0
      (let ((extruded (tc:extrude var 0)))
        (is (= 0 (tc:tyvar-sub-level extruded)))
        (is (not (eq var extruded)))))))

(deftest test-extrusion-no-change ()
  "Test that extrusion doesn't change variables already at target level."
  (tc:reset-levels)
  (let ((var (tc:make-variable-at-current-level)))
    (let ((extruded (tc:extrude var 0)))
      ;; Same level, should be the same object
      (is (eq var extruded)))))

;;;
;;; Simplification tests
;;;

(deftest test-simplify-union-identity ()
  "Test union simplification with bottom (identity element)."
  (let ((result (tc:simplify-union (list tc:*integer-type* tc:+ty-bot+))))
    (is (tc:ty= result tc:*integer-type*))))

(deftest test-simplify-union-absorption ()
  "Test union absorption with top."
  (let ((result (tc:simplify-union (list tc:*integer-type* tc:+ty-top+))))
    (is (tc:ty-top-p result))))

(deftest test-simplify-union-single ()
  "Test that single-member union simplifies to the member."
  (let ((result (tc:simplify-union (list tc:*integer-type*))))
    (is (tc:ty= result tc:*integer-type*))))

(deftest test-simplify-union-empty ()
  "Test that empty union simplifies to bottom."
  (let ((result (tc:simplify-union nil)))
    (is (tc:ty-bot-p result))))

(deftest test-simplify-union-dedup ()
  "Test that duplicate members are removed from union."
  (let ((result (tc:simplify-union
                 (list tc:*integer-type* tc:*integer-type* tc:*string-type*))))
    (is (tc:ty-union-p result))
    (is (= 2 (length (tc:ty-union-members result))))))

(deftest test-simplify-intersection-identity ()
  "Test intersection simplification with top (identity element)."
  (let ((result (tc:simplify-intersection (list tc:*integer-type* tc:+ty-top+))))
    (is (tc:ty= result tc:*integer-type*))))

(deftest test-simplify-intersection-absorption ()
  "Test intersection absorption with bottom."
  (let ((result (tc:simplify-intersection (list tc:*integer-type* tc:+ty-bot+))))
    (is (tc:ty-bot-p result))))

(deftest test-simplify-intersection-single ()
  "Test that single-member intersection simplifies to the member."
  (let ((result (tc:simplify-intersection (list tc:*integer-type*))))
    (is (tc:ty= result tc:*integer-type*))))

(deftest test-simplify-intersection-empty ()
  "Test that empty intersection simplifies to top."
  (let ((result (tc:simplify-intersection nil)))
    (is (tc:ty-top-p result))))

(deftest test-simplify-type-sandwich ()
  "Test sandwich removal when lower and upper bounds are equal."
  (tc:reset-levels)
  (let ((var (tc:make-variable-at-level)))
    ;; Create a sandwich: Integer <= var <= Integer
    (tc:add-lower-bound var tc:*integer-type*)
    (tc:add-upper-bound var tc:*integer-type*)
    ;; Simplification should produce Integer
    (let ((simplified (tc:simplify-type var)))
      (is (tc:ty= simplified tc:*integer-type*)))))

(deftest test-simplify-type-lower-bounds-only ()
  "Test simplification of variable with only lower bounds."
  (tc:reset-levels)
  (let ((var (tc:make-variable-at-level)))
    (tc:add-lower-bound var tc:*integer-type*)
    (tc:add-lower-bound var tc:*string-type*)
    ;; With only lower bounds, should become a union
    (let ((simplified (tc:simplify-type var)))
      (is (tc:ty-union-p simplified)))))

(deftest test-simplify-type-upper-bounds-only ()
  "Test simplification of variable with only upper bounds."
  (tc:reset-levels)
  (let ((var (tc:make-variable-at-level)))
    (tc:add-upper-bound var tc:*integer-type*)
    (tc:add-upper-bound var tc:*string-type*)
    ;; With only upper bounds, should become an intersection
    (let ((simplified (tc:simplify-type var)))
      (is (tc:ty-intersection-p simplified)))))

(deftest test-compact-type ()
  "Test the full compaction pipeline."
  (tc:reset-levels)
  (let ((var (tc:make-variable-at-level)))
    ;; Create sandwich
    (tc:add-lower-bound var tc:*integer-type*)
    (tc:add-upper-bound var tc:*integer-type*)
    (let ((compacted (tc:compact-type var)))
      (is (tc:ty= compacted tc:*integer-type*)))))

;;;
;;; Type equality tests for new types
;;;

(deftest test-union-equality ()
  "Test equality of union types (order independent)."
  (let ((union1 (tc:make-ty-union
                 :members (list tc:*integer-type* tc:*string-type*)))
        (union2 (tc:make-ty-union
                 :members (list tc:*string-type* tc:*integer-type*))))
    (is (tc:ty= union1 union2))))

(deftest test-intersection-equality ()
  "Test equality of intersection types (order independent)."
  (let ((inter1 (tc:make-ty-intersection
                 :members (list tc:*integer-type* tc:*string-type*)))
        (inter2 (tc:make-ty-intersection
                 :members (list tc:*string-type* tc:*integer-type*))))
    (is (tc:ty= inter1 inter2))))

;;;
;;; Type variable extraction tests
;;;

(deftest test-type-variables-union ()
  "Test type variable extraction from union types."
  (tc:reset-levels)
  (let* ((var (tc:make-variable-at-level))
         (union (tc:make-ty-union
                 :members (list var tc:*integer-type*))))
    (let ((vars (tc:type-variables union)))
      (is (member var vars)))))

(deftest test-type-variables-intersection ()
  "Test type variable extraction from intersection types."
  (tc:reset-levels)
  (let* ((var (tc:make-variable-at-level))
         (inter (tc:make-ty-intersection
                 :members (list var tc:*integer-type*))))
    (let ((vars (tc:type-variables inter)))
      (is (member var vars)))))
