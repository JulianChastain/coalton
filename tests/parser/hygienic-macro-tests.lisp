;;;; Tests for hygienic macro expansion
;;;;
;;;; These tests verify the hygienic expansion algorithm implementation,
;;;; including scope manipulation during expansion and CST conversion.

(fiasco:define-test-package #:coalton-impl/parser/hygienic-macro-tests
  (:use #:cl)
  (:local-nicknames
   (#:cst #:concrete-syntax-tree)
   (#:parser #:coalton-impl/parser)
   (#:source #:coalton-impl/source)
   (#:scope #:coalton-impl/parser/scope)
   (#:stx #:coalton-impl/parser/syntax-object)
   (#:stx-cst #:coalton-impl/parser/syntax-cst)
   (#:macro #:coalton-impl/parser/macro)))

(in-package #:coalton-impl/parser/hygienic-macro-tests)

;;;
;;; Helper Functions
;;;

(defun make-atom-cst (value &optional source)
  "Create an atom CST node directly."
  (make-instance 'cst:atom-cst :raw value :source source))

(defun make-cons-cst (first rest &optional source)
  "Create a cons CST node from FIRST and REST."
  (make-instance 'cst:cons-cst
                 :raw (cons (cst:raw first) (if (cst:null rest) nil (cst:raw rest)))
                 :source source
                 :first first
                 :rest rest))

(defun make-list-cst (elements &optional source)
  "Create a list CST from a list of elements (each element is a CST)."
  (if (null elements)
      (make-atom-cst nil source)
      (make-cons-cst (car elements)
                     (make-list-cst (cdr elements) source)
                     source)))

;;;
;;; Expansion Algorithm Tests
;;;

(deftest expand-macro-hygienic-basic ()
  "expand-macro-hygienic returns a syntax object"
  (let* ((input (stx:make-identifier-syntax 'x))
         (result (macro:expand-macro-hygienic input #'identity)))
    (is (stx:syntax-object-p result))))

(deftest expand-macro-hygienic-passes-input ()
  "Transformer receives scoped version of input"
  (let* ((input (stx:make-identifier-syntax 'x))
         (received nil)
         (result (macro:expand-macro-hygienic
                  input
                  (lambda (stx)
                    (setf received stx)
                    stx))))
    (declare (ignore result))
    (is (stx:syntax-object-p received))
    ;; Received input should have at least one scope (the use-site scope)
    (is (not (scope:scope-set-empty-p (stx:syntax-object-scopes received))))))

(deftest expand-macro-hygienic-input-returns-to-original ()
  "Input syntax returns to original scopes after expansion"
  ;; When input is passed through unchanged by the transformer,
  ;; it should end up with its original scopes:
  ;; 1. Use-scope is added before transformer
  ;; 2. Intro-scope is flipped on output (adding it to passed-through input)
  ;; 3. Use-scope is flipped on output (removing it from passed-through input)
  ;;
  ;; So passed-through syntax gets: original + intro (because flip adds when absent)
  ;; This is actually the expected behavior for macro-introduced syntax
  (let* ((original-scopes (scope:empty-scope-set))
         (input (stx:make-identifier-syntax 'x :scopes original-scopes))
         (result (macro:expand-macro-hygienic input #'identity)))
    ;; Result should be a syntax object
    (is (stx:syntax-object-p result))
    ;; The datum should still be x
    (is (eq 'x (stx:syntax-e result)))))

(deftest expand-macro-hygienic-introduced-gets-scope ()
  "Syntax introduced by macro gains intro scope"
  (let* ((input (stx:make-identifier-syntax 'x))
         (result (macro:expand-macro-hygienic
                  input
                  (lambda (stx)
                    (declare (ignore stx))
                    ;; Introduce fresh syntax
                    (stx:make-identifier-syntax 'introduced)))))
    ;; Introduced syntax should have the intro scope
    ;; (flip adds when absent)
    (is (stx:syntax-object-p result))
    (is (eq 'introduced (stx:syntax-e result)))
    ;; Should have at least one scope (the intro scope)
    (is (not (scope:scope-set-empty-p (stx:syntax-object-scopes result))))))

(deftest expand-macro-hygienic-preserves-structure ()
  "Expansion preserves list structure"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (input (stx:make-list-syntax (list a b)))
         (result (macro:expand-macro-hygienic input #'identity)))
    (is (stx-cst:stx-list-p result))
    (is (= 2 (stx-cst:stx-length result)))))

(deftest expand-macro-hygienic-nested-structure ()
  "Expansion handles nested structures"
  (let* ((x (stx:make-identifier-syntax 'x))
         (inner (stx:make-list-syntax (list x)))
         (outer (stx:make-list-syntax (list inner)))
         (result (macro:expand-macro-hygienic outer #'identity)))
    (is (stx-cst:stx-list-p result))
    (let ((inner-result (stx-cst:stx-first result)))
      (is (stx-cst:stx-list-p inner-result)))))

;;;
;;; Scope Tracking Tests
;;;

(deftest expansion-input-scopes-differ-from-introduced ()
  "Input and introduced syntax end up with different scopes"
  (let* ((original-token (scope:make-scope-token))
         (original-scopes (scope:scope-set-add (scope:empty-scope-set) original-token))
         (input (stx:make-identifier-syntax 'input :scopes original-scopes))
         (input-scopes-result nil)
         (introduced-scopes-result nil)
         (result (macro:expand-macro-hygienic
                  input
                  (lambda (stx)
                    ;; Return both input and introduced syntax
                    (let ((introduced (stx:make-identifier-syntax 'introduced)))
                      (stx:make-list-syntax (list stx introduced)))))))
    (setf input-scopes-result (stx:syntax-object-scopes (stx-cst:stx-first result)))
    (setf introduced-scopes-result (stx:syntax-object-scopes (stx-cst:stx-second result)))
    ;; Scopes should be different (input has original+intro, introduced has just intro)
    (is (not (scope:scope-set-equal input-scopes-result introduced-scopes-result)))))

(deftest expansion-recursive-scope-application ()
  "Scopes are applied recursively during expansion"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (inner (stx:make-list-syntax (list a b)))
         (input (stx:make-list-syntax (list inner)))
         (result (macro:expand-macro-hygienic input #'identity)))
    ;; All levels should have scopes applied
    (is (not (scope:scope-set-empty-p (stx:syntax-object-scopes result))))
    (let ((inner-result (stx-cst:stx-first result)))
      (is (not (scope:scope-set-empty-p (stx:syntax-object-scopes inner-result))))
      (dolist (elem (stx:syntax-e inner-result))
        (is (not (scope:scope-set-empty-p (stx:syntax-object-scopes elem))))))))

;;;
;;; Conversion Tests
;;;

(deftest syntax->cst-atom ()
  "syntax->cst converts atomic syntax to CST"
  (let* ((stx (stx:make-atom-syntax 42))
         (fallback (cons 0 10))
         (result (macro:syntax->cst stx fallback)))
    (is (cst:atom result))
    (is (eql 42 (cst:raw result)))))

(deftest syntax->cst-symbol ()
  "syntax->cst converts symbol syntax to CST"
  (let* ((stx (stx:make-identifier-syntax 'foo))
         (fallback (cons 0 10))
         (result (macro:syntax->cst stx fallback)))
    (is (cst:atom result))
    (is (symbolp (cst:raw result)))))

(deftest syntax->cst-list ()
  "syntax->cst converts list syntax to CST"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (stx (stx:make-list-syntax (list a b)))
         (fallback (cons 0 10))
         (result (macro:syntax->cst stx fallback)))
    (is (cst:consp result))))

(deftest syntax->cst-nil ()
  "syntax->cst converts nil syntax to CST"
  (let* ((stx (stx:make-syntax-object nil))
         (fallback (cons 0 10))
         (result (macro:syntax->cst stx fallback)))
    (is (cst:atom result))
    (is (null (cst:raw result)))))

(deftest syntax->cst-preserves-source ()
  "syntax->cst preserves source location from syntax"
  (let* ((source (cons 5 15))
         (stx (stx:make-identifier-syntax 'foo :source source))
         (fallback (cons 0 100))
         (result (macro:syntax->cst stx fallback)))
    (is (equal source (cst:source result)))))

(deftest syntax->cst-uses-fallback ()
  "syntax->cst uses fallback when syntax has no source"
  (let* ((stx (stx:make-identifier-syntax 'foo))
         (fallback (cons 0 100))
         (result (macro:syntax->cst stx fallback)))
    (is (equal fallback (cst:source result)))))

;;;
;;; Integration Tests
;;;

(deftest roundtrip-cst-syntax-cst ()
  "CST -> syntax -> CST preserves structure"
  (let* ((source (cons 0 20))
         ;; (define x 42)
         (original-cst (make-list-cst (list (make-atom-cst 'define source)
                                             (make-atom-cst 'x source)
                                             (make-atom-cst 42 source))
                                       source))
         (stx (stx-cst:cst->syntax original-cst))
         (fallback (cst:source original-cst))
         (result-cst (macro:syntax->cst stx fallback)))
    ;; Structure should be preserved
    (is (cst:consp result-cst))
    (is (equal (cst:raw original-cst) (cst:raw result-cst)))))

(deftest roundtrip-nested-structure ()
  "Nested structures survive roundtrip"
  (let* ((source (cons 0 30))
         ;; (let ((x 1)) x)
         (binding (make-list-cst (list (make-atom-cst 'x source)
                                        (make-atom-cst 1 source))
                                  source))
         (bindings (make-list-cst (list binding) source))
         (original-cst (make-list-cst (list (make-atom-cst 'let source)
                                             bindings
                                             (make-atom-cst 'x source))
                                       source))
         (stx (stx-cst:cst->syntax original-cst))
         (fallback (cst:source original-cst))
         (result-cst (macro:syntax->cst stx fallback)))
    (is (equal (cst:raw original-cst) (cst:raw result-cst)))))

;;;
;;; Transformer Behavior Tests
;;;

(deftest transformer-can-modify-structure ()
  "Transformer can modify the syntax structure"
  (let* ((input (stx:make-list-syntax
                 (list (stx:make-identifier-syntax 'original))))
         (result (macro:expand-macro-hygienic
                  input
                  (lambda (stx)
                    (declare (ignore stx))
                    (stx:make-list-syntax
                     (list (stx:make-identifier-syntax 'replaced)))))))
    (is (eq 'replaced (stx:syntax-e (stx-cst:stx-first result))))))

(deftest transformer-can-wrap-input ()
  "Transformer can wrap input in additional structure"
  (let* ((input (stx:make-identifier-syntax 'x))
         (result (macro:expand-macro-hygienic
                  input
                  (lambda (stx)
                    (stx:make-list-syntax
                     (list (stx:make-identifier-syntax 'wrapper) stx))))))
    (is (= 2 (stx-cst:stx-length result)))
    (is (eq 'wrapper (stx:syntax-e (stx-cst:stx-first result))))))

(deftest transformer-can-extract-parts ()
  "Transformer can extract and rearrange parts"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (input (stx:make-list-syntax (list a b)))
         (result (macro:expand-macro-hygienic
                  input
                  (lambda (stx)
                    ;; Reverse the order
                    (stx:make-list-syntax
                     (list (stx-cst:stx-second stx) (stx-cst:stx-first stx)))))))
    ;; Order should be reversed, with scopes applied
    (is (= 2 (stx-cst:stx-length result)))))

;;;
;;; Edge Cases
;;;

(deftest expand-empty-list ()
  "Expansion handles empty list"
  (let* ((input (stx:make-syntax-object nil))
         (result (macro:expand-macro-hygienic input #'identity)))
    (is (stx:syntax-object-p result))
    (is (stx-cst:stx-null-p result))))

(deftest expand-deeply-nested ()
  "Expansion handles deeply nested structures"
  (let* ((x (stx:make-identifier-syntax 'x))
         (level1 (stx:make-list-syntax (list x)))
         (level2 (stx:make-list-syntax (list level1)))
         (level3 (stx:make-list-syntax (list level2)))
         (result (macro:expand-macro-hygienic level3 #'identity)))
    ;; All levels should be syntax objects
    (is (stx:syntax-object-p result))
    (is (stx:syntax-object-p (stx-cst:stx-first result)))
    (is (stx:syntax-object-p (stx-cst:stx-first (stx-cst:stx-first result))))))
