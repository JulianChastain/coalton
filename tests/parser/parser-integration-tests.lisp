;;;; Integration tests for the CST→Syntax parser pipeline
;;;;
;;;; These tests verify that the full parser pipeline works correctly
;;;; through syntax objects: reading source → CST → syntax objects →
;;;; parsing → AST nodes. They exercise expression, pattern, type,
;;;; and toplevel parsing, and verify that source locations and scopes
;;;; propagate correctly through the pipeline.

(fiasco:define-test-package #:coalton-impl/parser/parser-integration-tests
  (:use #:cl)
  (:local-nicknames
   (#:cst #:concrete-syntax-tree)
   (#:parser #:coalton-impl/parser)
   (#:source #:coalton-impl/source)
   (#:scope #:coalton-impl/parser/scope)
   (#:stx #:coalton-impl/parser/syntax-object)
   (#:stx-cst #:coalton-impl/parser/syntax-cst)))

(in-package #:coalton-impl/parser/parser-integration-tests)

;;;
;;; Helper Functions
;;;

(defun read-syntax (string)
  "Read STRING as a single form and return it as a syntax object."
  (let ((source (source:make-source-string string :name "test")))
    (with-open-stream (stream (source:source-stream source))
      (parser:with-reader-context stream
        (let ((cst (parser:maybe-read-form stream source parser:*coalton-eclector-client*)))
          (values (and cst (stx-cst:cst->syntax cst source))
                  source))))))

(defun parse-expr (string)
  "Parse STRING as a Coalton expression, returning the AST node."
  (multiple-value-bind (form source) (read-syntax string)
    (when form
      (parser:parse-expression form source))))

(defun parse-pat (string)
  "Parse STRING as a Coalton pattern, returning the pattern node."
  (multiple-value-bind (form source) (read-syntax string)
    (when form
      (parser:parse-pattern form source))))

(defun parse-type (string)
  "Parse STRING as a Coalton type expression, returning the qualified-ty."
  (multiple-value-bind (form source) (read-syntax string)
    (when form
      (parser:parse-qualified-type form source))))

(defun parse-prog (string)
  "Parse STRING as a complete Coalton program, returning the program struct."
  (let ((source (source:make-source-string string :name "test")))
    (with-open-stream (stream (source:source-stream source))
      (parser:with-reader-context stream
        (parser:read-program stream source :file)))))

;;;
;;; Expression Parsing Tests
;;;

(deftest parse-integer-literal ()
  "Integer literals parse to node-integer-literal"
  (let ((node (parse-expr "42")))
    (is (typep node 'parser:node-integer-literal))
    (is (= 42 (parser:node-integer-literal-value node)))))

(deftest parse-string-literal ()
  "String literals parse to node-literal"
  (let ((node (parse-expr "\"hello\"")))
    (is (typep node 'parser:node-literal))
    (is (string= "hello" (parser:node-literal-value node)))))

(deftest parse-variable ()
  "Variables parse to node-variable"
  (let ((node (parse-expr "x")))
    (is (typep node 'parser:node-variable))))

(deftest parse-lambda ()
  "Lambda expressions parse to node-abstraction"
  (let ((node (parse-expr "(coalton:fn (x) x)")))
    (is (typep node 'parser:node-abstraction))
    (is (= 1 (length (parser:node-abstraction-params node))))))

(deftest parse-multi-param-lambda ()
  "Multi-parameter lambda parses correctly"
  (let ((node (parse-expr "(coalton:fn (x y z) x)")))
    (is (typep node 'parser:node-abstraction))
    (is (= 3 (length (parser:node-abstraction-params node))))))

(deftest parse-let-expression ()
  "Let expressions parse to node-let with correct bindings"
  (let ((node (parse-expr "(coalton:let ((x 1) (y 2)) x)")))
    (is (typep node 'parser:node-let))
    (is (= 2 (length (parser:node-let-bindings node))))
    (is (not (null (parser:node-let-body node))))))

(deftest parse-nested-let ()
  "Nested let expressions parse correctly"
  (let ((node (parse-expr "(coalton:let ((x 1)) (coalton:let ((y 2)) x))")))
    (is (typep node 'parser:node-let))
    (let* ((body (parser:node-let-body node))
           (inner (parser:node-body-last-node body)))
      (is (typep inner 'parser:node-let))
      (is (= 1 (length (parser:node-let-bindings inner)))))))

(deftest parse-if-expression ()
  "If expressions parse to node-if"
  (let ((node (parse-expr "(coalton:if x 1 2)")))
    (is (typep node 'parser:node-if))))

(deftest parse-when-expression ()
  "When expressions parse to node-when"
  (let ((node (parse-expr "(coalton:when x 1)")))
    (is (typep node 'parser:node-when))))

(deftest parse-unless-expression ()
  "Unless expressions parse to node-unless"
  (let ((node (parse-expr "(coalton:unless x 1)")))
    (is (typep node 'parser:node-unless))))

(deftest parse-and-expression ()
  "And expressions parse to node-and"
  (let ((node (parse-expr "(coalton:and x y)")))
    (is (typep node 'parser:node-and))))

(deftest parse-or-expression ()
  "Or expressions parse to node-or"
  (let ((node (parse-expr "(coalton:or x y)")))
    (is (typep node 'parser:node-or))))

(deftest parse-cond-expression ()
  "Cond expressions parse to node-cond"
  (let ((node (parse-expr "(coalton:cond (x 1) (y 2))")))
    (is (typep node 'parser:node-cond))
    (is (= 2 (length (parser:node-cond-clauses node))))))

(deftest parse-progn-expression ()
  "Progn expressions parse to node-progn"
  (let ((node (parse-expr "(coalton:progn 1 2 3)")))
    (is (typep node 'parser:node-progn))))

(deftest parse-match-expression ()
  "Match expressions parse to node-match with branches"
  (let ((node (parse-expr "(coalton:match x ((coalton-prelude:Some y) y))")))
    (is (typep node 'parser:node-match))
    (is (= 1 (length (parser:node-match-branches node))))))

(deftest parse-the-expression ()
  "The expressions parse to node-the"
  (let ((node (parse-expr "(coalton:the coalton:UFix 42)")))
    (is (typep node 'parser:node-the))))

(deftest parse-return-expression ()
  "Return expressions parse to node-return"
  (let ((node (parse-expr "(coalton:return 42)")))
    (is (typep node 'parser:node-return))))

;;;
;;; Pattern Parsing Tests
;;;

(deftest parse-wildcard-pattern ()
  "Wildcard patterns parse to pattern-wildcard"
  (let ((pat (parse-pat "coalton:_")))
    (is (typep pat 'parser:pattern-wildcard))))

(deftest parse-variable-pattern ()
  "Variable patterns parse to pattern-var"
  (let ((pat (parse-pat "x")))
    (is (parser:pattern-var-p pat))))

(deftest parse-literal-pattern ()
  "Literal patterns parse to pattern-literal"
  (let ((pat (parse-pat "42")))
    (is (typep pat 'parser:pattern-literal))
    (is (= 42 (parser:pattern-literal-value pat)))))

(deftest parse-constructor-pattern ()
  "Constructor patterns parse to pattern-constructor"
  (let ((pat (parse-pat "(coalton-prelude:Some x)")))
    (is (typep pat 'parser:pattern-constructor))
    (is (= 1 (length (parser:pattern-constructor-patterns pat))))))

(deftest parse-string-literal-pattern ()
  "String literal patterns parse correctly"
  (let ((pat (parse-pat "\"hello\"")))
    (is (typep pat 'parser:pattern-literal))
    (is (string= "hello" (parser:pattern-literal-value pat)))))

;;;
;;; Type Parsing Tests
;;;

(deftest parse-simple-type ()
  "Simple type names parse correctly"
  (let ((ty (parse-type "UFix")))
    (is (not (null ty)))))

(deftest parse-function-type ()
  "Function types parse correctly"
  (let ((ty (parse-type "(UFix -> UFix)")))
    (is (not (null ty)))))

(deftest parse-parameterized-type ()
  "Parameterized types parse correctly"
  (let ((ty (parse-type "(List UFix)")))
    (is (not (null ty)))))

(deftest parse-type-variable ()
  "Type variables parse correctly"
  (let ((ty (parse-type ":a")))
    (is (not (null ty)))))

(deftest parse-constrained-type ()
  "Constrained types parse correctly"
  (let ((ty (parse-type "(Num :a => :a)")))
    (is (not (null ty)))))

;;;
;;; Toplevel Parsing Tests
;;;

(deftest parse-program-with-define ()
  "Programs with define parse correctly"
  (let ((prog (parse-prog "(package test-pkg)
(define x 42)")))
    (is (not (null prog)))
    (is (= 1 (length (parser:program-defines prog))))))

(deftest parse-program-with-multiple-defines ()
  "Programs with multiple defines parse correctly"
  (let ((prog (parse-prog "(package test-pkg)
(define x 42)
(define y 0)")))
    (is (= 2 (length (parser:program-defines prog))))))

(deftest parse-program-with-define-type ()
  "Programs with define-type parse correctly"
  (let ((prog (parse-prog "(package test-pkg)
(define-type Color Red Green Blue)")))
    (is (= 1 (length (parser:program-types prog))))))

(deftest parse-program-with-define-class ()
  "Programs with define-class parse correctly"
  (let ((prog (parse-prog "(package test-pkg)
(define-class (MyClass :a))")))
    (is (= 1 (length (parser:program-classes prog))))))

(deftest parse-program-with-declare ()
  "Programs with declare parse correctly"
  (let ((prog (parse-prog "(package test-pkg)
(declare f (UFix -> UFix))
(define (f x) x)")))
    (is (= 1 (length (parser:program-defines prog))))))

;;;
;;; Source Location Preservation Tests
;;;

(deftest expression-has-source-location ()
  "Parsed expressions carry source location information"
  (let ((node (parse-expr "42")))
    (is (not (null (source:location node))))))

(deftest nested-expression-has-source-location ()
  "Nested expression nodes carry source locations"
  (let ((node (parse-expr "(coalton:let ((x 1)) x)")))
    (is (not (null (source:location node))))
    ;; Bindings should have locations too
    (let ((binding (first (parser:node-let-bindings node))))
      (is (not (null (source:location binding)))))))

(deftest pattern-has-source-location ()
  "Parsed patterns carry source location information"
  (let ((pat (parse-pat "x")))
    (is (not (null (source:location pat))))))

;;;
;;; CST→Syntax Conversion Tests
;;;

(deftest syntax-object-from-reader ()
  "Reading source produces valid syntax objects"
  (multiple-value-bind (stx source) (read-syntax "(f x y)")
    (declare (ignore source))
    (is (stx:syntax-object-p stx))
    (is (stx-cst:stx-consp stx))
    (is (= 3 (stx-cst:stx-length stx)))))

(deftest syntax-preserves-atoms ()
  "Atomic values are preserved through CST→syntax conversion"
  (multiple-value-bind (stx source) (read-syntax "42")
    (declare (ignore source))
    (is (stx-cst:stx-atom-p stx))
    (is (= 42 (stx:syntax-e stx)))))

(deftest syntax-preserves-symbols ()
  "Symbols are preserved through CST→syntax conversion"
  (multiple-value-bind (stx source) (read-syntax "hello")
    (declare (ignore source))
    (is (stx-cst:stx-symbol-p stx))
    (is (symbolp (stx:syntax-e stx)))))

(deftest syntax-preserves-nesting ()
  "Nested list structure is preserved through CST→syntax conversion"
  (multiple-value-bind (stx source) (read-syntax "((a b) (c d))")
    (declare (ignore source))
    (is (stx-cst:stx-consp stx))
    (is (= 2 (stx-cst:stx-length stx)))
    ;; First element is a nested list
    (let ((first (stx-cst:stx-first stx)))
      (is (stx-cst:stx-consp first))
      (is (= 2 (stx-cst:stx-length first))))))

(deftest syntax-has-source-info ()
  "Syntax objects from reader carry source information"
  (multiple-value-bind (stx source) (read-syntax "hello")
    (declare (ignore source))
    (is (not (null (stx:syntax-object-source stx))))))

(deftest syntax-children-have-source-info ()
  "Children of list syntax objects carry source information"
  (multiple-value-bind (stx source) (read-syntax "(a b c)")
    (declare (ignore source))
    (dolist (child (stx:syntax-e stx))
      (is (not (null (stx:syntax-object-source child)))))))

(deftest syntax-has-empty-scopes ()
  "Syntax objects from reader have empty scope sets"
  (multiple-value-bind (stx source) (read-syntax "hello")
    (declare (ignore source))
    (is (scope:scope-set-empty-p (stx:syntax-object-scopes stx)))))

;;;
;;; Dotted List Rejection Tests
;;;

(deftest dotted-list-rejected-at-conversion ()
  "Dotted lists are rejected during CST→syntax conversion"
  (let ((source (source:make-source-string "(a . b)" :name "test")))
    (with-open-stream (stream (source:source-stream source))
      (parser:with-reader-context stream
        (let ((cst (parser:maybe-read-form stream source parser:*coalton-eclector-client*)))
          (signals source:source-error
            (stx-cst:cst->syntax cst source)))))))

;;;
;;; Error Reporting Tests
;;;

(deftest parse-error-on-malformed-let ()
  "Malformed let expression signals parse error"
  (signals parser:parse-error
    (parse-expr "(coalton:let)")))

(deftest parse-error-on-empty-fn ()
  "Empty fn expression signals parse error"
  (signals parser:parse-error
    (parse-expr "(coalton:fn)")))

(deftest parse-error-on-malformed-match ()
  "Malformed match expression signals parse error"
  (signals parser:parse-error
    (parse-expr "(coalton:match)")))

(deftest parse-error-on-malformed-if ()
  "Malformed if expression signals parse error"
  (signals parser:parse-error
    (parse-expr "(coalton:if)")))

;;;
;;; Round-trip Tests
;;;

(deftest datum-preserved-through-pipeline ()
  "Raw datum is preserved through CST→syntax conversion"
  (multiple-value-bind (stx source) (read-syntax "(let ((x 1)) x)")
    (declare (ignore source))
    ;; Deep unwrap should match the original s-expression structure
    (let ((datum (stx:syntax->datum stx)))
      (is (listp datum))
      (is (eq 'let (first datum))))))

(deftest complex-datum-preserved ()
  "Complex nested expressions preserve their datum through conversion"
  (multiple-value-bind (stx source) (read-syntax "(fn (x y) (if x y 0))")
    (declare (ignore source))
    (let ((datum (stx:syntax->datum stx)))
      (is (eq 'fn (first datum)))
      (is (listp (second datum)))
      (is (= 2 (length (second datum))))
      (let ((body (third datum)))
        (is (eq 'if (first body)))))))
