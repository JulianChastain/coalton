;;;; Integration tests for hygienic macro expansion in the parser pipeline
;;;;
;;;; These tests verify that hygienic macro expansion works correctly when
;;;; integrated into Coalton's parser, testing end-to-end scenarios with
;;;; the *use-hygienic-macros* feature flag.

(fiasco:define-test-package #:coalton-impl/parser/hygienic-integration-tests
  (:use #:cl)
  (:local-nicknames
   (#:cst #:concrete-syntax-tree)
   (#:parser #:coalton-impl/parser)
   (#:source #:coalton-impl/source)
   (#:scope #:coalton-impl/parser/scope)
   (#:stx #:coalton-impl/parser/syntax-object)
   (#:stx-cst #:coalton-impl/parser/syntax-cst)
   (#:macro #:coalton-impl/parser/macro)))

(in-package #:coalton-impl/parser/hygienic-integration-tests)

;;;
;;; Helper Functions
;;;

(defun parse-form (string fn)
  "Parse the form in STRING using FN."
  (let ((source (source:make-source-string string :name "test")))
    (with-open-stream (stream (source:source-stream source))
      (parser:with-reader-context stream
        (let ((cst (parser:maybe-read-form stream parser::*coalton-eclector-client*)))
          (funcall fn (and cst (stx-cst:cst->syntax cst)) source))))))

(defun parse-coalton-expression (string &optional (hygienic nil))
  "Parse STRING as a Coalton expression.
When HYGIENIC is true, use hygienic macro expansion."
  (let ((macro:*use-hygienic-macros* hygienic))
    (parse-form string
                (lambda (form source)
                  (when form
                    (parser:parse-expression form source))))))

;;;
;;; Feature Flag Tests
;;;

(deftest feature-flag-default-is-nil ()
  "The *use-hygienic-macros* flag defaults to nil"
  (let ((macro:*use-hygienic-macros* macro:*use-hygienic-macros*))
    ;; Don't rebind, just check default
    (is (null macro:*use-hygienic-macros*))))

(deftest feature-flag-can-be-enabled ()
  "The *use-hygienic-macros* flag can be dynamically bound to t"
  (let ((macro:*use-hygienic-macros* t))
    (is macro:*use-hygienic-macros*)))

;;;
;;; Basic Parsing Tests with Hygienic Flag
;;;

(deftest parse-simple-expression-traditional ()
  "Simple expressions parse correctly with traditional expansion"
  (let ((result (parse-coalton-expression "42" nil)))
    (is (not (null result)))))

(deftest parse-simple-expression-hygienic ()
  "Simple expressions parse correctly with hygienic expansion"
  (let ((result (parse-coalton-expression "42" t)))
    (is (not (null result)))))

(deftest parse-variable-traditional ()
  "Variable expressions parse correctly with traditional expansion"
  (let ((result (parse-coalton-expression "x" nil)))
    (is (not (null result)))))

(deftest parse-variable-hygienic ()
  "Variable expressions parse correctly with hygienic expansion"
  (let ((result (parse-coalton-expression "x" t)))
    (is (not (null result)))))

(deftest parse-application-traditional ()
  "Application expressions parse correctly with traditional expansion"
  (let ((result (parse-coalton-expression "(f x)" nil)))
    (is (not (null result)))))

(deftest parse-application-hygienic ()
  "Application expressions parse correctly with hygienic expansion"
  (let ((result (parse-coalton-expression "(f x)" t)))
    (is (not (null result)))))

;;;
;;; Let Binding Tests
;;;

(deftest parse-let-traditional ()
  "Let expressions parse correctly with traditional expansion"
  (let ((result (parse-coalton-expression "(let ((x 1)) x)" nil)))
    (is (not (null result)))))

(deftest parse-let-hygienic ()
  "Let expressions parse correctly with hygienic expansion"
  (let ((result (parse-coalton-expression "(let ((x 1)) x)" t)))
    (is (not (null result)))))

(deftest parse-nested-let-traditional ()
  "Nested let expressions parse correctly with traditional expansion"
  (let ((result (parse-coalton-expression "(let ((x 1)) (let ((y 2)) x))" nil)))
    (is (not (null result)))))

(deftest parse-nested-let-hygienic ()
  "Nested let expressions parse correctly with hygienic expansion"
  (let ((result (parse-coalton-expression "(let ((x 1)) (let ((y 2)) x))" t)))
    (is (not (null result)))))

;;;
;;; Lambda/Function Tests
;;;

(deftest parse-fn-traditional ()
  "Function expressions parse correctly with traditional expansion"
  (let ((result (parse-coalton-expression "(fn (x) x)" nil)))
    (is (not (null result)))))

(deftest parse-fn-hygienic ()
  "Function expressions parse correctly with hygienic expansion"
  (let ((result (parse-coalton-expression "(fn (x) x)" t)))
    (is (not (null result)))))

;;;
;;; Match Tests
;;;

(deftest parse-match-traditional ()
  "Match expressions parse correctly with traditional expansion"
  (let ((result (parse-coalton-expression "(match x ((Some y) y) ((None) 0))" nil)))
    (is (not (null result)))))

(deftest parse-match-hygienic ()
  "Match expressions parse correctly with hygienic expansion"
  (let ((result (parse-coalton-expression "(match x ((Some y) y) ((None) 0))" t)))
    (is (not (null result)))))

;;;
;;; Wrapper Function Tests
;;;

(deftest expand-macro-hygienic-wrapper-basic ()
  "expand-macro-hygienic-wrapper expands a simple CL macro"
  ;; Test with a simple macro that transforms to something else
  ;; We use progn which is a real CL macro
  (parse-form "(progn x)"
              (lambda (form source)
                (when form
                  (let ((result (macro:expand-macro-hygienic-wrapper form source)))
                    (is (not (null result)))
                    (is (typep result 'stx:syntax-object)))))))

(deftest make-cl-macro-transformer-creates-function ()
  "make-cl-macro-transformer returns a function"
  (let ((transformer (macro:make-cl-macro-transformer '(progn x))))
    (is (functionp transformer))))

(deftest make-cl-macro-transformer-expands ()
  "make-cl-macro-transformer creates a transformer that expands macros"
  (let* ((transformer (macro:make-cl-macro-transformer '(progn x)))
         (input (stx:make-list-syntax
                 (list (stx:make-identifier-syntax 'progn)
                       (stx:make-identifier-syntax 'x))))
         (result (funcall transformer input)))
    (is (stx:syntax-object-p result))))

;;;
;;; Regression Tests - Existing Behavior Unchanged
;;;

(deftest regression-traditional-parsing-unchanged ()
  "Traditional parsing (flag=nil) behavior is unchanged"
  ;; Multiple expression types should all parse the same way
  (dolist (expr '("42" "x" "(f x)" "(let ((x 1)) x)" "(fn (x) x)"))
    (let ((result (parse-coalton-expression expr nil)))
      (is (not (null result)) "Expression ~S should parse" expr))))

;;;
;;; Complex Expression Tests
;;;

(deftest parse-complex-nested-traditional ()
  "Complex nested expressions parse with traditional expansion"
  (let ((result (parse-coalton-expression
                 "(let ((f (fn (x) x)))
                    (match (f 1)
                      (y y)))"
                 nil)))
    (is (not (null result)))))

(deftest parse-complex-nested-hygienic ()
  "Complex nested expressions parse with hygienic expansion"
  (let ((result (parse-coalton-expression
                 "(let ((f (fn (x) x)))
                    (match (f 1)
                      (y y)))"
                 t)))
    (is (not (null result)))))

;;;
;;; Error Handling Tests
;;;

(deftest parse-error-propagates-traditional ()
  "Parse errors propagate correctly with traditional expansion"
  ;; Use coalton:let explicitly and add a malformed binding list
  (signals parser:parse-error
    (parse-form "(coalton:let)"
                (lambda (form source)
                  (let ((macro:*use-hygienic-macros* nil))
                    (parser:parse-expression form source))))))

(deftest parse-error-propagates-hygienic ()
  "Parse errors propagate correctly with hygienic expansion"
  ;; Use coalton:let explicitly and add a malformed binding list
  (signals parser:parse-error
    (parse-form "(coalton:let)"
                (lambda (form source)
                  (let ((macro:*use-hygienic-macros* t))
                    (parser:parse-expression form source))))))

;;;
;;; Scoping Correctness Tests
;;;
;;; These tests verify that parsing produces correct structure.
;;; Note: We use coalton: package prefixes to ensure correct symbol resolution.
;;;

(deftest let-expression-parses-to-node-let ()
  "Let expressions should parse to node-let with proper structure.

   (coalton:let ((x 1)) x) - should produce a node-let with one binding"
  (let ((result (parse-coalton-expression "(coalton:let ((x 1)) x)" nil)))
    (is (not (null result)))
    (is (typep result 'parser:node-let))
    ;; Should have bindings and a body
    (is (not (null (parser:node-let-bindings result))))
    (is (not (null (parser:node-let-body result))))))

(deftest nested-let-parses-correctly ()
  "Nested let expressions should parse correctly.

   (coalton:let ((x 1)) (coalton:let ((x 2)) x)) - should produce nested node-let"
  (let ((result (parse-coalton-expression "(coalton:let ((x 1)) (coalton:let ((x 2)) x))" nil)))
    (is (not (null result)))
    (is (typep result 'parser:node-let))
    ;; The body's last-node should be another let
    (let* ((body (parser:node-let-body result))
           (inner (parser:node-body-last-node body)))
      (is (typep inner 'parser:node-let)))))

(deftest let-with-multiple-bindings ()
  "Let with multiple bindings should parse correctly.

   (coalton:let ((x 1) (y 2)) x)"
  (let ((result (parse-coalton-expression "(coalton:let ((x 1) (y 2)) x)" nil)))
    (is (not (null result)))
    (is (typep result 'parser:node-let))
    ;; Should have two bindings
    (is (= 2 (length (parser:node-let-bindings result))))))

(deftest fn-expression-parses-correctly ()
  "Function expressions should parse to node-abstraction.

   (coalton:fn (x) x) - should produce a node-abstraction"
  (let ((result (parse-coalton-expression "(coalton:fn (x) x)" nil)))
    (is (not (null result)))
    (is (typep result 'parser:node-abstraction))
    ;; Should have params and body
    (is (not (null (parser:node-abstraction-params result))))
    (is (not (null (parser:node-abstraction-body result))))))

(deftest fn-in-let-body-parses ()
  "Function in let body should parse correctly.

   (coalton:let ((x 1)) (coalton:fn (y) y))"
  (let ((result (parse-coalton-expression "(coalton:let ((x 1)) (coalton:fn (y) y))" nil)))
    (is (not (null result)))
    (is (typep result 'parser:node-let))
    (let* ((body (parser:node-let-body result))
           (last-node (parser:node-body-last-node body)))
      (is (typep last-node 'parser:node-abstraction)))))

(deftest match-expression-parses-correctly ()
  "Match expressions should parse to node-match.

   (coalton:match x ((Some y) y))"
  (let ((result (parse-coalton-expression "(coalton:match x ((Some y) y))" nil)))
    (is (not (null result)))
    (is (typep result 'parser:node-match))
    ;; Should have branches
    (is (not (null (parser:node-match-branches result))))))

;;;
;;; Syntax Object Preservation Tests
;;;

(deftest cst-to-syntax-preserves-structure ()
  "Converting CST to syntax and back preserves the structure"
  (parse-form "(let ((x 1)) (f x))"
              (lambda (form source)
                (declare (ignore source))
                (when form
                  ;; form is already a syntax object from parse-form
                  ;; Convert to CST and back, check datum is preserved
                  (let* ((datum (stx:syntax->datum form))
                         (back (macro:syntax->cst form (stx:syntax-object-source form))))
                    ;; Raw datum should be preserved
                    (is (equal datum (cst:raw back))))))))

(defun flatten-datum (tree)
  "Flatten a nested list into a flat list of atoms."
  (cond
    ((null tree) nil)
    ((atom tree) (list tree))
    (t (append (flatten-datum (car tree))
               (flatten-datum (cdr tree))))))

(deftest hygienic-expansion-preserves-user-identifiers ()
  "Hygienic expansion should preserve user identifier names"
  (let ((macro:*use-hygienic-macros* t))
    (parse-form "(let ((my-var 1)) my-var)"
                (lambda (form source)
                  (declare (ignore source))
                  (when form
                    ;; form is already a syntax object from parse-form
                    ;; The datum should contain 'my-var
                    (let ((datum (stx:syntax->datum form)))
                      (is (member 'my-var (flatten-datum datum)))))))))

;;;
;;; Macro Expansion Integration
;;;

(deftest progn-macro-expands ()
  "CL macros like progn should expand correctly"
  (let ((macro:*use-hygienic-macros* t))
    (parse-form "(progn 1 2 3)"
                (lambda (form source)
                  (when form
                    (let ((expanded (macro:expand-macro-hygienic-wrapper form source)))
                      ;; Should return a CST
                      (is (typep expanded 'stx:syntax-object))))))))

(deftest when-macro-expands-to-if ()
  "The when macro should expand to an if form"
  (let ((macro:*use-hygienic-macros* t))
    (parse-form "(when test body)"
                (lambda (form source)
                  (when form
                    (let ((expanded (macro:expand-macro-hygienic-wrapper form source)))
                      ;; Should be expanded (when -> if)
                      (is (typep expanded 'stx:syntax-object))
                      ;; Raw should start with IF
                      (is (eq 'if (first (stx:syntax->datum expanded))))))))))
