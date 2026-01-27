;;;; Tests for binding table and resolution
;;;;
;;;; These tests verify the binding table implementation that maps identifiers
;;;; to bindings using the maximal subset resolution rule.

(fiasco:define-test-package #:coalton-impl/parser/binding-table-tests
  (:use #:cl)
  (:local-nicknames
   (#:scope #:coalton-impl/parser/scope)
   (#:stx #:coalton-impl/parser/syntax-object)
   (#:bt #:coalton-impl/parser/binding-table)))

(in-package #:coalton-impl/parser/binding-table-tests)

;;;
;;; Helper Functions
;;;

(defun make-scopes (&rest tokens)
  "Create a scope set containing all the given tokens."
  (reduce (lambda (set tok)
            (scope:scope-set-add set tok))
          tokens
          :initial-value (scope:empty-scope-set)))

;;;
;;; Scope Binding Tests
;;;

(deftest make-scope-binding-basic ()
  "make-scope-binding creates binding with correct fields"
  (let* ((scopes (scope:empty-scope-set))
         (binding (bt:make-scope-binding 'x scopes :my-value)))
    (is (typep binding 'bt:scope-binding))
    (is (eq 'x (bt:scope-binding-name binding)))
    (is (scope:scope-set-equal scopes (bt:scope-binding-scopes binding)))
    (is (eq :my-value (bt:scope-binding-value binding)))
    (is (null (bt:scope-binding-source binding)))))

(deftest make-scope-binding-with-source ()
  "make-scope-binding accepts optional source location"
  (let* ((source (cons 10 20))
         (binding (bt:make-scope-binding 'x (scope:empty-scope-set) :val
                                          :source source)))
    (is (equal source (bt:scope-binding-source binding)))))

;;;
;;; Binding Table Creation Tests
;;;

(deftest make-binding-table ()
  "make-binding-table creates empty table"
  (let ((table (bt:make-binding-table)))
    (is (typep table 'bt:binding-table))))

(deftest binding-table-add ()
  "binding-table-add adds bindings"
  (let* ((table (bt:make-binding-table))
         (scopes (scope:empty-scope-set))
         (new-table (bt:binding-table-add table 'x scopes :val)))
    ;; Original unchanged (immutability)
    (is (typep new-table 'bt:binding-table))
    ;; Can resolve the added binding
    (let ((result (bt:binding-table-resolve new-table 'x scopes)))
      (is (bt:resolution-bound-p result)))))

(deftest binding-table-add-binding ()
  "binding-table-add-binding adds existing binding"
  (let* ((binding (bt:make-scope-binding 'y (scope:empty-scope-set) :y-val))
         (table (bt:make-binding-table))
         (new-table (bt:binding-table-add-binding table binding)))
    (let ((result (bt:binding-table-resolve new-table 'y (scope:empty-scope-set))))
      (is (bt:resolution-bound-p result))
      (is (eq binding (bt:resolution-result-binding result))))))

;;;
;;; Simple Resolution Tests
;;;

(deftest resolution-simple-lookup ()
  "Simple lookup - single binding found"
  (let* ((s1 (scope:make-scope-token))
         (scopes (make-scopes s1))
         (table (bt:binding-table-add (bt:make-binding-table)
                                       'x scopes :x-value))
         (result (bt:binding-table-resolve table 'x scopes)))
    (is (bt:resolution-bound-p result))
    (is (eq :x-value (bt:scope-binding-value (bt:resolution-result-binding result))))))

(deftest resolution-unbound ()
  "Unbound identifier - no matching binding"
  (let* ((table (bt:make-binding-table))
         (result (bt:binding-table-resolve table 'x (scope:empty-scope-set))))
    (is (bt:resolution-unbound-p result))))

(deftest resolution-unbound-wrong-name ()
  "Binding exists but for different name"
  (let* ((table (bt:binding-table-add (bt:make-binding-table)
                                       'x (scope:empty-scope-set) :x-value))
         (result (bt:binding-table-resolve table 'y (scope:empty-scope-set))))
    (is (bt:resolution-unbound-p result))))

(deftest resolution-unbound-insufficient-scopes ()
  "Binding exists but reference doesn't have required scopes"
  (let* ((s1 (scope:make-scope-token))
         (binding-scopes (make-scopes s1))
         (table (bt:binding-table-add (bt:make-binding-table)
                                       'x binding-scopes :x-value))
         ;; Reference with empty scopes can't see binding with s1
         (result (bt:binding-table-resolve table 'x (scope:empty-scope-set))))
    (is (bt:resolution-unbound-p result))))

;;;
;;; Maximal Subset Resolution Tests
;;;

(deftest resolution-shadowing ()
  "Inner binding (more scopes) shadows outer binding"
  (let* ((s1 (scope:make-scope-token))
         (s2 (scope:make-scope-token))
         (outer-scopes (make-scopes s1))
         (inner-scopes (make-scopes s1 s2))
         (table (bt:binding-table-add
                 (bt:binding-table-add (bt:make-binding-table)
                                        'x outer-scopes :outer)
                 'x inner-scopes :inner))
         ;; Lookup with {s1, s2} should find the inner binding
         (result (bt:binding-table-resolve table 'x inner-scopes)))
    (is (bt:resolution-bound-p result))
    (is (eq :inner (bt:scope-binding-value (bt:resolution-result-binding result))))))

(deftest resolution-maximal-subset-example ()
  "Bindings: x@{}, x@{s1}, x@{s1,s2} - lookup x@{s1,s2} returns x@{s1,s2}"
  (let* ((s1 (scope:make-scope-token))
         (s2 (scope:make-scope-token))
         (table (bt:binding-table-add
                 (bt:binding-table-add
                  (bt:binding-table-add (bt:make-binding-table)
                                         'x (scope:empty-scope-set) :empty)
                  'x (make-scopes s1) :s1)
                 'x (make-scopes s1 s2) :s1-s2))
         (result (bt:binding-table-resolve table 'x (make-scopes s1 s2))))
    (is (bt:resolution-bound-p result))
    (is (eq :s1-s2 (bt:scope-binding-value (bt:resolution-result-binding result))))))

(deftest resolution-maximal-intermediate ()
  "Bindings: x@{}, x@{s1}, x@{s1,s2} - lookup x@{s1} returns x@{s1}"
  (let* ((s1 (scope:make-scope-token))
         (s2 (scope:make-scope-token))
         (table (bt:binding-table-add
                 (bt:binding-table-add
                  (bt:binding-table-add (bt:make-binding-table)
                                         'x (scope:empty-scope-set) :empty)
                  'x (make-scopes s1) :s1)
                 'x (make-scopes s1 s2) :s1-s2))
         (result (bt:binding-table-resolve table 'x (make-scopes s1))))
    (is (bt:resolution-bound-p result))
    (is (eq :s1 (bt:scope-binding-value (bt:resolution-result-binding result))))))

(deftest resolution-falls-back-to-empty ()
  "Lookup with s2 only finds binding with empty scopes"
  (let* ((s1 (scope:make-scope-token))
         (s2 (scope:make-scope-token))
         (table (bt:binding-table-add
                 (bt:binding-table-add (bt:make-binding-table)
                                        'x (scope:empty-scope-set) :empty)
                 'x (make-scopes s1) :s1))
         ;; Lookup with {s2} - only empty scopes is a subset
         (result (bt:binding-table-resolve table 'x (make-scopes s2))))
    (is (bt:resolution-bound-p result))
    (is (eq :empty (bt:scope-binding-value (bt:resolution-result-binding result))))))

;;;
;;; Ambiguity Detection Tests
;;;

(deftest resolution-ambiguous ()
  "Ambiguous: x@{s1}, x@{s2} where neither is subset of other"
  (let* ((s1 (scope:make-scope-token))
         (s2 (scope:make-scope-token))
         (table (bt:binding-table-add
                 (bt:binding-table-add (bt:make-binding-table)
                                        'x (make-scopes s1) :s1)
                 'x (make-scopes s2) :s2))
         ;; Lookup with {s1, s2} - both bindings are maximal
         (result (bt:binding-table-resolve table 'x (make-scopes s1 s2))))
    (is (bt:resolution-ambiguous-p result))
    (is (= 2 (length (bt:resolution-result-candidates result))))))

(deftest resolution-not-ambiguous-with-dominator ()
  "Not ambiguous when one binding dominates others"
  (let* ((s1 (scope:make-scope-token))
         (s2 (scope:make-scope-token))
         (table (bt:binding-table-add
                 (bt:binding-table-add
                  (bt:binding-table-add (bt:make-binding-table)
                                         'x (make-scopes s1) :s1)
                  'x (make-scopes s2) :s2)
                 'x (make-scopes s1 s2) :s1-s2))
         ;; Lookup with {s1, s2} - x@{s1,s2} dominates both
         (result (bt:binding-table-resolve table 'x (make-scopes s1 s2))))
    (is (bt:resolution-bound-p result))
    (is (eq :s1-s2 (bt:scope-binding-value (bt:resolution-result-binding result))))))

(deftest resolution-ambiguous-three-way ()
  "Three-way ambiguity is detected"
  (let* ((s1 (scope:make-scope-token))
         (s2 (scope:make-scope-token))
         (s3 (scope:make-scope-token))
         (table (bt:binding-table-add
                 (bt:binding-table-add
                  (bt:binding-table-add (bt:make-binding-table)
                                         'x (make-scopes s1) :s1)
                  'x (make-scopes s2) :s2)
                 'x (make-scopes s3) :s3))
         (result (bt:binding-table-resolve table 'x (make-scopes s1 s2 s3))))
    (is (bt:resolution-ambiguous-p result))
    (is (= 3 (length (bt:resolution-result-candidates result))))))

;;;
;;; Syntax Object Resolution Tests
;;;

(deftest resolve-syntax ()
  "binding-table-resolve-syntax resolves syntax object"
  (let* ((s1 (scope:make-scope-token))
         (scopes (make-scopes s1))
         (table (bt:binding-table-add (bt:make-binding-table)
                                       'x scopes :x-value))
         (stx (stx:make-identifier-syntax 'x :scopes scopes))
         (result (bt:binding-table-resolve-syntax table stx)))
    (is (bt:resolution-bound-p result))
    (is (eq :x-value (bt:scope-binding-value (bt:resolution-result-binding result))))))

;;;
;;; Resolution Result Structure Tests
;;;

(deftest resolution-unbound-structure ()
  "resolution-unbound has correct structure"
  (let* ((scopes (scope:empty-scope-set))
         (table (bt:make-binding-table))
         (result (bt:binding-table-resolve table 'missing scopes)))
    (is (bt:resolution-unbound-p result))
    (is (not (bt:resolution-bound-p result)))
    (is (not (bt:resolution-ambiguous-p result)))))

(deftest resolution-bound-structure ()
  "resolution-bound has correct structure"
  (let* ((table (bt:binding-table-add (bt:make-binding-table)
                                       'x (scope:empty-scope-set) :val))
         (result (bt:binding-table-resolve table 'x (scope:empty-scope-set))))
    (is (bt:resolution-bound-p result))
    (is (not (bt:resolution-unbound-p result)))
    (is (not (bt:resolution-ambiguous-p result)))
    (is (typep (bt:resolution-result-binding result) 'bt:scope-binding))))

(deftest resolution-ambiguous-structure ()
  "resolution-ambiguous has correct structure"
  (let* ((s1 (scope:make-scope-token))
         (s2 (scope:make-scope-token))
         (table (bt:binding-table-add
                 (bt:binding-table-add (bt:make-binding-table)
                                        'x (make-scopes s1) :s1)
                 'x (make-scopes s2) :s2))
         (result (bt:binding-table-resolve table 'x (make-scopes s1 s2))))
    (is (bt:resolution-ambiguous-p result))
    (is (not (bt:resolution-bound-p result)))
    (is (not (bt:resolution-unbound-p result)))
    (is (listp (bt:resolution-result-candidates result)))
    (dolist (candidate (bt:resolution-result-candidates result))
      (is (typep candidate 'bt:scope-binding)))))

;;;
;;; Multiple Bindings for Same Name Tests
;;;

(deftest multiple-bindings-same-name ()
  "Table can hold multiple bindings for the same name"
  (let* ((s1 (scope:make-scope-token))
         (s2 (scope:make-scope-token))
         (table (bt:binding-table-add
                 (bt:binding-table-add (bt:make-binding-table)
                                        'x (make-scopes s1) :in-s1)
                 'x (make-scopes s2) :in-s2)))
    ;; Lookup with s1 finds s1 binding
    (let ((result1 (bt:binding-table-resolve table 'x (make-scopes s1))))
      (is (bt:resolution-bound-p result1))
      (is (eq :in-s1 (bt:scope-binding-value (bt:resolution-result-binding result1)))))
    ;; Lookup with s2 finds s2 binding
    (let ((result2 (bt:binding-table-resolve table 'x (make-scopes s2))))
      (is (bt:resolution-bound-p result2))
      (is (eq :in-s2 (bt:scope-binding-value (bt:resolution-result-binding result2)))))))

;;;
;;; Edge Cases
;;;

(deftest resolution-empty-table-empty-scopes ()
  "Empty table with empty scopes returns unbound"
  (let ((result (bt:binding-table-resolve
                 (bt:make-binding-table)
                 'x
                 (scope:empty-scope-set))))
    (is (bt:resolution-unbound-p result))))

(deftest resolution-exact-scope-match ()
  "Exact scope match works correctly"
  (let* ((s1 (scope:make-scope-token))
         (scopes (make-scopes s1))
         (table (bt:binding-table-add (bt:make-binding-table)
                                       'x scopes :exact))
         (result (bt:binding-table-resolve table 'x scopes)))
    (is (bt:resolution-bound-p result))
    (is (eq :exact (bt:scope-binding-value (bt:resolution-result-binding result))))))
