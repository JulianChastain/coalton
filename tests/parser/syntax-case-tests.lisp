;;;; Tests for syntax-case pattern matching and templates

(fiasco:define-test-package #:coalton/tests/parser/syntax-case-tests
  (:use #:cl)
  (:local-nicknames
   (#:scope #:coalton-impl/parser/scope)
   (#:stx #:coalton-impl/parser/syntax-object)
   (#:stx-cst #:coalton-impl/parser/syntax-cst)
   (#:syntax-case #:coalton-impl/parser/syntax-case)))

(in-package #:coalton/tests/parser/syntax-case-tests)

;;;
;;; Helper Functions and Constants
;;;

;; The ellipsis symbol from the syntax-case package
(defparameter *ellipsis* 'coalton-impl/parser/syntax-case:|...|)

(defun make-test-syntax (datum &optional scopes)
  "Create a syntax object for testing with optional scopes."
  (stx:make-syntax-object datum :scopes (or scopes (scope:empty-scope-set))))

(defun make-list-syntax (elements)
  "Create a list syntax object from a list of syntax objects."
  (stx:make-list-syntax elements))

;;;
;;; Ellipsis Detection Tests
;;;

(fiasco:deftest ellipsis-p-detects-dots ()
  "ellipsis-p detects the ... symbol"
  (fiasco:is (syntax-case:ellipsis-p *ellipsis*))
  (fiasco:is (syntax-case:ellipsis-p 'coalton-impl/parser/syntax-case:|...|))
  (fiasco:is (not (syntax-case:ellipsis-p 'foo)))
  (fiasco:is (not (syntax-case:ellipsis-p nil)))
  (fiasco:is (not (syntax-case:ellipsis-p 42))))

;;;
;;; Pattern Variables Tests
;;;

(fiasco:deftest pattern-variables-extracts-symbols ()
  "pattern-variables extracts pattern variable names"
  (fiasco:is (equal '(x) (syntax-case:pattern-variables 'x)))
  (fiasco:is (equal '(x y) (syntax-case:pattern-variables '(x y))))
  (fiasco:is (null (syntax-case:pattern-variables '_)))
  (fiasco:is (null (syntax-case:pattern-variables '())))
  (fiasco:is (null (syntax-case:pattern-variables (list *ellipsis*)))))

(fiasco:deftest pattern-variables-respects-literals ()
  "pattern-variables excludes literal symbols"
  (let ((vars (syntax-case:pattern-variables '(if test then else) '(if))))
    (fiasco:is (not (member 'if vars)))
    (fiasco:is (member 'test vars))
    (fiasco:is (member 'then vars))
    (fiasco:is (member 'else vars))))

(fiasco:deftest pattern-variables-handles-ellipsis ()
  "pattern-variables handles ellipsis patterns"
  (let ((vars (syntax-case:pattern-variables `(x ,*ellipsis*))))
    (fiasco:is (equal '(x) vars)))
  (let ((vars (syntax-case:pattern-variables `((var val) ,*ellipsis*))))
    (fiasco:is (member 'var vars))
    (fiasco:is (member 'val vars))))

(fiasco:deftest pattern-variables-removes-duplicates ()
  "pattern-variables removes duplicate variable names"
  (let ((vars (syntax-case:pattern-variables '(x (x y) x))))
    (fiasco:is (= 2 (length vars)))
    (fiasco:is (member 'x vars))
    (fiasco:is (member 'y vars))))

;;;
;;; Pattern Matching Tests
;;;

(fiasco:deftest syntax-match-wildcard ()
  "Wildcard _ matches anything"
  (let ((stx (make-test-syntax 'foo)))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match '_ stx)
      (fiasco:is match)
      (fiasco:is (null bindings)))))

(fiasco:deftest syntax-match-symbol-variable ()
  "Symbol pattern binds to syntax"
  (let ((stx (make-test-syntax 'foo)))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match 'x stx)
      (fiasco:is match)
      (fiasco:is (= 1 (length bindings)))
      (fiasco:is (eq 'x (caar bindings)))
      (fiasco:is (stx:syntax-object-p (cdar bindings))))))

(fiasco:deftest syntax-match-literal ()
  "Literal symbols in pattern must match exactly"
  (let ((stx (make-test-syntax 'if)))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match 'if stx '(if))
      (fiasco:is match)
      (fiasco:is (null bindings))))
  ;; Non-matching literal
  (let ((stx (make-test-syntax 'when)))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match 'if stx '(if))
      (declare (ignore bindings))
      (fiasco:is (not match)))))

(fiasco:deftest syntax-match-simple-list ()
  "Simple list pattern matches list syntax"
  (let ((stx (make-list-syntax
              (list (make-test-syntax 'a)
                    (make-test-syntax 'b)))))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match '(x y) stx)
      (fiasco:is match)
      (fiasco:is (= 2 (length bindings)))
      (fiasco:is (assoc 'x bindings))
      (fiasco:is (assoc 'y bindings)))))

(fiasco:deftest syntax-match-nested-list ()
  "Nested list patterns match nested syntax"
  (let ((stx (make-list-syntax
              (list (make-test-syntax 'outer)
                    (make-list-syntax
                     (list (make-test-syntax 'inner)))))))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match '(x (y)) stx)
      (fiasco:is match)
      (fiasco:is (= 2 (length bindings)))
      (fiasco:is (eq 'outer (stx:syntax-e (cdr (assoc 'x bindings)))))
      (fiasco:is (eq 'inner (stx:syntax-e (cdr (assoc 'y bindings))))))))

(fiasco:deftest syntax-match-ellipsis-zero ()
  "Ellipsis pattern matches zero elements"
  (let ((stx (make-list-syntax nil)))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match `(x ,*ellipsis*) stx)
      (fiasco:is match)
      (fiasco:is (= 1 (length bindings)))
      (fiasco:is (null (cdr (assoc 'x bindings)))))))

(fiasco:deftest syntax-match-ellipsis-multiple ()
  "Ellipsis pattern matches multiple elements"
  (let ((stx (make-list-syntax
              (list (make-test-syntax 'a)
                    (make-test-syntax 'b)
                    (make-test-syntax 'c)))))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match `(x ,*ellipsis*) stx)
      (fiasco:is match)
      (fiasco:is (= 1 (length bindings)))
      (let ((x-vals (cdr (assoc 'x bindings))))
        (fiasco:is (= 3 (length x-vals)))
        (fiasco:is (eq 'a (stx:syntax-e (first x-vals))))
        (fiasco:is (eq 'b (stx:syntax-e (second x-vals))))
        (fiasco:is (eq 'c (stx:syntax-e (third x-vals))))))))

(fiasco:deftest syntax-match-ellipsis-with-prefix ()
  "Ellipsis pattern with prefix"
  (let ((stx (make-list-syntax
              (list (make-test-syntax 'let)
                    (make-test-syntax 'a)
                    (make-test-syntax 'b)))))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match `(let x ,*ellipsis*) stx '(let))
      (fiasco:is match)
      (let ((x-vals (cdr (assoc 'x bindings))))
        (fiasco:is (= 2 (length x-vals)))))))

(fiasco:deftest syntax-match-paired-ellipsis ()
  "Ellipsis pattern with paired variables"
  (let ((stx (make-list-syntax
              (list (make-list-syntax
                     (list (make-test-syntax 'x) (make-test-syntax 1)))
                    (make-list-syntax
                     (list (make-test-syntax 'y) (make-test-syntax 2)))))))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match `((var val) ,*ellipsis*) stx)
      (fiasco:is match)
      (let ((var-vals (cdr (assoc 'var bindings)))
            (val-vals (cdr (assoc 'val bindings))))
        (fiasco:is (= 2 (length var-vals)))
        (fiasco:is (= 2 (length val-vals)))
        (fiasco:is (eq 'x (stx:syntax-e (first var-vals))))
        (fiasco:is (eq 'y (stx:syntax-e (second var-vals))))))))

(fiasco:deftest syntax-match-ellipsis-with-suffix ()
  "Ellipsis pattern with elements after ellipsis"
  (let ((stx (make-list-syntax
              (list (make-test-syntax 'a)
                    (make-test-syntax 'b)
                    (make-test-syntax 'end)))))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match `(x ,*ellipsis* tail) stx)
      (fiasco:is match)
      (let ((x-vals (cdr (assoc 'x bindings)))
            (tail (cdr (assoc 'tail bindings))))
        (fiasco:is (= 2 (length x-vals)))
        (fiasco:is (eq 'end (stx:syntax-e tail)))))))

(fiasco:deftest syntax-match-no-match ()
  "Pattern fails to match incompatible syntax"
  ;; Wrong list length
  (let ((stx (make-list-syntax
              (list (make-test-syntax 'a)))))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match '(x y) stx)
      (declare (ignore bindings))
      (fiasco:is (not match))))
  ;; Wrong literal
  (let ((stx (make-list-syntax
              (list (make-test-syntax 'when)
                    (make-test-syntax 'body)))))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match '(if body) stx '(if))
      (declare (ignore bindings))
      (fiasco:is (not match)))))

;;;
;;; syntax->list Tests
;;;

(fiasco:deftest syntax->list-extracts-elements ()
  "syntax->list extracts list elements"
  (let* ((elem1 (make-test-syntax 'a))
         (elem2 (make-test-syntax 'b))
         (stx (make-list-syntax (list elem1 elem2))))
    (let ((result (syntax-case:syntax->list stx)))
      (fiasco:is (= 2 (length result)))
      (fiasco:is (eq elem1 (first result)))
      (fiasco:is (eq elem2 (second result))))))

(fiasco:deftest syntax->list-returns-nil-for-non-list ()
  "syntax->list returns NIL for non-list syntax"
  (let ((stx (make-test-syntax 'foo)))
    (fiasco:is (null (syntax-case:syntax->list stx)))))

;;;
;;; syntax-case Macro Tests
;;;

(fiasco:deftest syntax-case-basic-match ()
  "syntax-case matches basic patterns"
  (let ((stx (make-list-syntax
              (list (make-test-syntax 'foo)
                    (make-test-syntax 'bar)))))
    (let ((result
            (syntax-case:syntax-case stx ()
              ((a b)
               (list (stx:syntax-e a) (stx:syntax-e b))))))
      (fiasco:is (equal '(foo bar) result)))))

(fiasco:deftest syntax-case-with-literals ()
  "syntax-case respects literal declarations"
  (let ((stx (make-list-syntax
              (list (make-test-syntax 'if)
                    (make-test-syntax 'test)
                    (make-test-syntax 'then)))))
    (let ((result
            (syntax-case:syntax-case stx (if)
              ((if test body)
               (list 'matched (stx:syntax-e test) (stx:syntax-e body))))))
      (fiasco:is (equal '(matched test then) result)))))

(fiasco:deftest syntax-case-multiple-clauses ()
  "syntax-case tries clauses in order"
  ;; Match second clause
  (let ((stx (make-list-syntax
              (list (make-test-syntax 'x)))))
    (let ((result
            (syntax-case:syntax-case stx ()
              ((a b) 'two-elements)
              ((a) 'one-element)
              (_ 'fallback))))
      (fiasco:is (eq 'one-element result))))
  ;; Match first clause
  (let ((stx (make-list-syntax
              (list (make-test-syntax 'x)
                    (make-test-syntax 'y)))))
    (let ((result
            (syntax-case:syntax-case stx ()
              ((a b) 'two-elements)
              ((a) 'one-element)
              (_ 'fallback))))
      (fiasco:is (eq 'two-elements result)))))

;;;
;;; with-syntax Macro Tests
;;;

(fiasco:deftest with-syntax-binds-pattern-vars ()
  "with-syntax binds pattern variables"
  (let ((stx (make-list-syntax
              (list (make-test-syntax 'a)
                    (make-test-syntax 'b)))))
    (let ((result
            (syntax-case:with-syntax (((x y) stx))
              (list (stx:syntax-e x) (stx:syntax-e y)))))
      (fiasco:is (equal '(a b) result)))))

(fiasco:deftest with-syntax-multiple-bindings ()
  "with-syntax supports multiple bindings"
  (let ((stx1 (make-list-syntax
               (list (make-test-syntax 'a)
                     (make-test-syntax 'b))))
        (stx2 (make-test-syntax 'c)))
    (let ((result
            (syntax-case:with-syntax (((x y) stx1)
                                      (z stx2))
              (list (stx:syntax-e x) (stx:syntax-e y) (stx:syntax-e z)))))
      (fiasco:is (equal '(a b c) result)))))

;;;
;;; Template Expansion (expand-template function) Tests
;;;

(fiasco:deftest template-expands-variables ()
  "Template expansion substitutes pattern variables"
  (let* ((ctx (make-test-syntax 'context))
         (x-stx (make-test-syntax 'x-value))
         (y-stx (make-test-syntax 'y-value))
         (bindings (list (cons 'x x-stx) (cons 'y y-stx)))
         (result (syntax-case::expand-template '(x y) bindings ctx)))
    (fiasco:is (stx:syntax-object-p result))
    (let ((elems (stx:syntax-e result)))
      (fiasco:is (= 2 (length elems)))
      (fiasco:is (eq 'x-value (stx:syntax-e (first elems))))
      (fiasco:is (eq 'y-value (stx:syntax-e (second elems)))))))

(fiasco:deftest template-expands-ellipsis ()
  "Template expansion handles ellipsis"
  (let* ((ctx (make-test-syntax 'context))
         (x-list (list (make-test-syntax 'a)
                       (make-test-syntax 'b)
                       (make-test-syntax 'c)))
         (bindings (list (cons 'x x-list)))
         (result (syntax-case::expand-template `(x ,*ellipsis*) bindings ctx)))
    (fiasco:is (stx:syntax-object-p result))
    (let ((elems (stx:syntax-e result)))
      (fiasco:is (= 3 (length elems)))
      (fiasco:is (eq 'a (stx:syntax-e (first elems))))
      (fiasco:is (eq 'b (stx:syntax-e (second elems))))
      (fiasco:is (eq 'c (stx:syntax-e (third elems)))))))

(fiasco:deftest template-expands-paired-ellipsis ()
  "Template expansion pairs up ellipsis variables"
  (let* ((ctx (make-test-syntax 'context))
         (vars (list (make-test-syntax 'x) (make-test-syntax 'y)))
         (vals (list (make-test-syntax 1) (make-test-syntax 2)))
         (bindings (list (cons 'var vars) (cons 'val vals)))
         (result (syntax-case::expand-template `((var val) ,*ellipsis*) bindings ctx)))
    (fiasco:is (stx:syntax-object-p result))
    (let ((elems (stx:syntax-e result)))
      (fiasco:is (= 2 (length elems)))
      ;; First pair: (x 1)
      (let ((pair1 (stx:syntax-e (first elems))))
        (fiasco:is (eq 'x (stx:syntax-e (first pair1))))
        (fiasco:is (eql 1 (stx:syntax-e (second pair1)))))
      ;; Second pair: (y 2)
      (let ((pair2 (stx:syntax-e (second elems))))
        (fiasco:is (eq 'y (stx:syntax-e (first pair2))))
        (fiasco:is (eql 2 (stx:syntax-e (second pair2))))))))

(fiasco:deftest template-wraps-non-variables ()
  "Template wraps literal symbols with context scopes"
  (let* ((scope (scope:make-scope-token))
         (ctx (stx:make-syntax-object 'context
                                      :scopes (scope:scope-set-add (scope:empty-scope-set) scope)))
         (bindings nil)
         (result (syntax-case::expand-template 'literal-sym bindings ctx)))
    (fiasco:is (stx:syntax-object-p result))
    (fiasco:is (eq 'literal-sym (stx:syntax-e result)))
    ;; Should inherit scopes from context
    (fiasco:is (scope:scope-set-member-p (stx:syntax-object-scopes result) scope))))
