;;;; cl-types-tests.lisp
;;;;
;;;; Unit tests for the CL type system interface
;;;;

(in-package #:coalton-tests)

;;;
;;; ty-cl-type structure tests
;;;

(deftest test-ty-cl-type-creation ()
  "Test creation of CL type wrappers."
  (let ((cl-type (tc:make-ty-cl-type :specifier 'cl:integer)))
    (is (tc:ty-cl-type-p cl-type))
    (is (eq 'cl:integer (tc:ty-cl-type-specifier cl-type)))
    (is (not (tc:ty-cl-type-normalized-p cl-type)))))

(deftest test-ty-cl-type-compound ()
  "Test creation of compound CL type wrappers."
  (let ((cl-type (tc:make-ty-cl-type :specifier '(satisfies evenp))))
    (is (tc:ty-cl-type-p cl-type))
    (is (equal '(satisfies evenp) (tc:ty-cl-type-specifier cl-type)))))

(deftest test-ty-cl-type-kind ()
  "Test that CL types have kind *."
  (let ((cl-type (tc:make-ty-cl-type :specifier 'cl:integer)))
    (is (tc:kstar-p (tc:kind-of cl-type)))))

(deftest test-ty-cl-type-no-type-variables ()
  "Test that CL types have no type variables."
  (let ((cl-type (tc:make-ty-cl-type :specifier '(or integer string))))
    (is (null (tc:type-variables cl-type)))))

;;;
;;; Conversion tests: cl-type->ty
;;;

(deftest test-cl-type-to-ty-top ()
  "Test that CL T converts to ty-top."
  (let ((result (tc:cl-type->ty t)))
    (is (tc:ty-top-p result))))

(deftest test-cl-type-to-ty-bot ()
  "Test that CL NIL converts to ty-bot."
  (let ((result (tc:cl-type->ty nil)))
    (is (tc:ty-bot-p result))))

(deftest test-cl-type-to-ty-registered ()
  "Test conversion of registered CL types."
  (let ((result (tc:cl-type->ty 'cl:integer)))
    (is (tc:tycon-p result))
    (is (tc:ty= result tc:*integer-type*))))

(deftest test-cl-type-to-ty-or ()
  "Test that (OR ...) converts to ty-union."
  (let ((result (tc:cl-type->ty '(or integer string))))
    (is (tc:ty-union-p result))
    (is (= 2 (length (tc:ty-union-members result))))))

(deftest test-cl-type-to-ty-and ()
  "Test that (AND ...) converts to ty-intersection."
  (let ((result (tc:cl-type->ty '(and number (satisfies evenp)))))
    ;; This should be a ty-intersection with a registered type and a CL type
    (is (or (tc:ty-intersection-p result)
            ;; Could also be simplified to a single CL type
            (tc:ty-cl-type-p result)))))

(deftest test-cl-type-to-ty-satisfies ()
  "Test that (SATISFIES ...) wraps as ty-cl-type."
  (let ((result (tc:cl-type->ty '(satisfies evenp))))
    (is (tc:ty-cl-type-p result))
    (is (equal '(satisfies evenp) (tc:ty-cl-type-specifier result)))))

(deftest test-cl-type-to-ty-member ()
  "Test that (MEMBER ...) wraps as ty-cl-type."
  (let ((result (tc:cl-type->ty '(member :a :b :c))))
    (is (tc:ty-cl-type-p result))
    (is (equal '(member :a :b :c) (tc:ty-cl-type-specifier result)))))

(deftest test-cl-type-to-ty-array ()
  "Test that (ARRAY ...) wraps as ty-cl-type."
  (let ((result (tc:cl-type->ty '(array integer 2))))
    (is (tc:ty-cl-type-p result))
    (is (equal '(array integer 2) (tc:ty-cl-type-specifier result)))))

(deftest test-cl-type-to-ty-or-simplification ()
  "Test that OR with bot simplifies."
  (let ((result (tc:cl-type->ty '(or integer nil))))
    ;; (OR integer NIL) should simplify to just integer
    (is (or (tc:tycon-p result)
            (and (tc:ty-union-p result)
                 (= 1 (length (tc:ty-union-members result))))))))

;;;
;;; Conversion tests: ty->cl-type
;;;

(deftest test-ty-to-cl-type-top ()
  "Test that ty-top converts to T."
  (let ((result (tc:ty->cl-type tc:+ty-top+)))
    (is (eq t result))))

(deftest test-ty-to-cl-type-bot ()
  "Test that ty-bot converts to NIL."
  (let ((result (tc:ty->cl-type tc:+ty-bot+)))
    (is (eq nil result))))

(deftest test-ty-to-cl-type-union ()
  "Test that ty-union converts to (OR ...)."
  (let* ((union (tc:make-ty-union
                 :members (list tc:*integer-type* tc:*string-type*)))
         (result (tc:ty->cl-type union)))
    (is (consp result))
    (is (eq 'or (car result)))))

(deftest test-ty-to-cl-type-intersection ()
  "Test that ty-intersection converts to (AND ...)."
  (let* ((inter (tc:make-ty-intersection
                 :members (list tc:*integer-type* tc:*string-type*)))
         (result (tc:ty->cl-type inter)))
    (is (consp result))
    (is (eq 'and (car result)))))

(deftest test-ty-to-cl-type-unwrap ()
  "Test that ty-cl-type unwraps to original specifier."
  (let* ((cl-type (tc:make-ty-cl-type :specifier '(satisfies evenp)))
         (result (tc:ty->cl-type cl-type)))
    (is (equal '(satisfies evenp) result))))

(deftest test-ty-to-cl-type-roundtrip ()
  "Test that roundtrip conversion preserves semantics."
  (let* ((spec '(or integer string))
         (ty (tc:cl-type->ty spec))
         (result (tc:ty->cl-type ty)))
    ;; The result should be equivalent to the original
    (multiple-value-bind (sub1 valid1)
        (cl:subtypep spec result)
      (multiple-value-bind (sub2 valid2)
          (cl:subtypep result spec)
        (is valid1)
        (is valid2)
        (is sub1)
        (is sub2)))))

;;;
;;; Subtype checking tests
;;;

(deftest test-cl-subtype-p-positive ()
  "Test cl-subtype-p with known subtypes."
  (multiple-value-bind (sub valid)
      (tc:cl-subtype-p 'integer 'number)
    (is valid)
    (is sub)))

(deftest test-cl-subtype-p-negative ()
  "Test cl-subtype-p with non-subtypes."
  (multiple-value-bind (sub valid)
      (tc:cl-subtype-p 'string 'number)
    (is valid)
    (is (not sub))))

(deftest test-cl-types-disjoint-p ()
  "Test cl-types-disjoint-p."
  (multiple-value-bind (disjoint valid)
      (tc:cl-types-disjoint-p 'integer 'string)
    (is valid)
    (is disjoint)))

(deftest test-cl-types-not-disjoint ()
  "Test cl-types-disjoint-p with overlapping types."
  (multiple-value-bind (disjoint valid)
      (tc:cl-types-disjoint-p 'integer 'number)
    (is valid)
    (is (not disjoint))))

;;;
;;; Constraint tests with CL types
;;;

(deftest test-constrain-cl-type-to-top ()
  "Test that CL types constrain to top."
  (let ((cl-type (tc:make-ty-cl-type :specifier 'integer)))
    (is (tc:constrain cl-type tc:+ty-top+))))

(deftest test-constrain-bot-to-cl-type ()
  "Test that bot constrains to CL types."
  (let ((cl-type (tc:make-ty-cl-type :specifier 'integer)))
    (is (tc:constrain tc:+ty-bot+ cl-type))))

(deftest test-constrain-cl-type-subtypes ()
  "Test constraining CL types with subtype relationship."
  (let ((integer-type (tc:make-ty-cl-type :specifier 'integer))
        (number-type (tc:make-ty-cl-type :specifier 'number)))
    ;; integer <= number should succeed
    (is (tc:constrain integer-type number-type))))

(deftest test-constrain-cl-type-not-subtypes ()
  "Test constraining CL types without subtype relationship."
  (let ((string-type (tc:make-ty-cl-type :specifier 'string))
        (number-type (tc:make-ty-cl-type :specifier 'number)))
    ;; string <= number should fail
    (signals tc:constraint-error
      (tc:constrain string-type number-type))))

(deftest test-constrain-cl-type-to-tyvar-sub ()
  "Test constraining CL type to bounded variable."
  (tc:reset-levels)
  (let ((cl-type (tc:make-ty-cl-type :specifier 'integer))
        (var (tc:make-variable-at-level)))
    ;; CL type as upper bound
    (tc:constrain var cl-type)
    (is (member cl-type (tc:tyvar-sub-upper-bounds var) :test #'tc:ty=))
    ;; CL type as lower bound
    (let ((var2 (tc:make-variable-at-level)))
      (tc:constrain cl-type var2)
      (is (member cl-type (tc:tyvar-sub-lower-bounds var2) :test #'tc:ty=)))))

;;;
;;; Simplification tests with CL types
;;;

(deftest test-simplify-type-cl-type ()
  "Test that ty-cl-type simplifies to itself."
  (let ((cl-type (tc:make-ty-cl-type :specifier '(satisfies evenp))))
    (is (eq cl-type (tc:simplify-type cl-type)))))

;;;
;;; ty-cl-type equality tests
;;;

(deftest test-ty-cl-type-equality ()
  "Test equality of ty-cl-type based on subtypep."
  (let ((int1 (tc:make-ty-cl-type :specifier 'cl:integer))
        (int2 (tc:make-ty-cl-type :specifier 'cl:integer))
        (str (tc:make-ty-cl-type :specifier 'cl:string)))
    (is (tc:ty= int1 int2))
    (is (not (tc:ty= int1 str)))))

(deftest test-ty-cl-type-equality-compound ()
  "Test equality of compound CL types."
  (let ((type1 (tc:make-ty-cl-type :specifier '(or integer string)))
        (type2 (tc:make-ty-cl-type :specifier '(or string integer))))
    ;; These should be equal since (OR integer string) = (OR string integer)
    (is (tc:ty= type1 type2))))

;;;
;;; Type registry tests
;;;

(deftest test-type-registry-lookup ()
  "Test that registered types can be looked up."
  (let ((result (tc:lookup-cl-type 'cl:integer)))
    (is (tc:ty= result tc:*integer-type*))))

(deftest test-type-registry-unknown ()
  "Test that unknown types return NIL."
  (let ((result (tc:lookup-cl-type 'some-unknown-type)))
    (is (null result))))
