;;;; Tests for the Shrubbery/Rhombus syntax frontend
;;;;
;;;; These tests verify the translation from shrubbery notation through
;;;; the trapezoid enforester into Coalton S-expression forms, and then
;;;; through the existing Coalton parser pipeline.
;;;;
;;;; Test layers:
;;;;   1. translate-enforested: trapezoid output → Coalton S-expressions
;;;;   2. sexp->syntax: S-expressions → Coalton syntax objects
;;;;   3. shrubbery->coalton-sexps: full pipeline (text → S-expressions)
;;;;   4. parse-shrubbery-toplevel: full pipeline through Coalton parser
;;;;   5. coalton-shrubbery macro: end-to-end compilation

(fiasco:define-test-package #:coalton-impl/parser/shrubbery-tests
  (:use #:cl)
  (:local-nicknames
   (#:stx #:coalton-impl/parser/syntax-object)
   (#:stx-cst #:coalton-impl/parser/syntax-cst)
   (#:source #:coalton-impl/source)
   (#:parser #:coalton-impl/parser)
   (#:shrubbery #:coalton-impl/parser/shrubbery)
   (#:trap #:trapezoid)))

(in-package #:coalton-impl/parser/shrubbery-tests)

;;;
;;; Helper Functions
;;;

(defun sexps (text)
  "Translate shrubbery TEXT to a list of Coalton S-expressions."
  (shrubbery:shrubbery->coalton-sexps text))

(defun sexp1 (text)
  "Translate shrubbery TEXT to a single Coalton S-expression."
  (first (sexps text)))

(defun enforest-raw (text)
  "Parse and enforest TEXT, returning the raw trapezoid output."
  (let ((trap:*produce-syntax-objects* nil))
    (trap:enforest (trap:parse-shrubbery text))))

;;; ============================================================
;;; Layer 1: Trapezoid Enforester Output Verification
;;; ============================================================
;;;
;;; Verify that trapezoid produces the expected forms that our
;;; translation layer depends on.

(deftest enforest-integer ()
  "Integers pass through the enforester"
  (is (eql 42 (enforest-raw "42"))))

(deftest enforest-variable ()
  "Variables pass through the enforester"
  (is (eql 'x (enforest-raw "x"))))

(deftest enforest-binary-op ()
  "Binary operators produce (call op left right)"
  (let ((result (enforest-raw "1 + 2")))
    (is (eq 'trap:call (first result)))
    (is (eq '+ (second result)))
    (is (eql 1 (third result)))
    (is (eql 2 (fourth result)))))

(deftest enforest-define ()
  "Definitions produce (define name value)"
  (let ((result (enforest-raw "def x = 5")))
    (is (eq 'trap:define (first result)))
    (is (eq 'x (second result)))
    (is (eql 5 (third result)))))

(deftest enforest-lambda ()
  "Lambdas produce (lambda (args) body)"
  (let ((result (enforest-raw "fun(x): x + 1")))
    (is (eq 'lambda (first result)))
    (is (equal '(x) (second result)))))

(deftest enforest-function-call ()
  "Function calls produce (call f args...)"
  (let ((result (enforest-raw "f(x)")))
    (is (eq 'trap:call (first result)))
    (is (eq 'f (second result)))
    (is (eq 'x (third result)))))

(deftest enforest-precedence ()
  "Multiplication has higher precedence than addition"
  (let ((result (enforest-raw "1 + 2 * 3")))
    ;; Should be (call + 1 (call * 2 3))
    (is (eq '+ (second result)))
    (is (eql 1 (third result)))
    (let ((rhs (fourth result)))
      (is (eq 'trap:call (first rhs)))
      (is (eq '* (second rhs))))))

(deftest enforest-multi-line ()
  "Multi-line input produces a list of groups"
  (let ((trap:*produce-syntax-objects* nil))
    (let ((parsed (trap:parse-shrubbery (format nil "def x = 5~%def y = 10"))))
      ;; Should be a list of two groups, not a single group
      (is (listp parsed))
      (is (= 2 (length parsed)))
      (is (eq 'trap:group (caar parsed)))
      (is (eq 'trap:group (caadr parsed))))))

;;; ============================================================
;;; Layer 2: S-expression → Coalton Syntax Object Conversion
;;; ============================================================

(deftest sexp-to-syntax-atom ()
  "Atomic S-expressions become atomic syntax objects"
  (let ((stx (shrubbery::sexp->syntax 42 (cons 0 2))))
    (is (stx:syntax-object-p stx))
    (is (eql 42 (stx:syntax-e stx)))
    (is (equal (cons 0 2) (stx:syntax-object-source stx)))))

(deftest sexp-to-syntax-symbol ()
  "Symbol S-expressions become symbol syntax objects"
  (let ((stx (shrubbery::sexp->syntax 'x (cons 0 1))))
    (is (stx:syntax-object-p stx))
    (is (eq 'x (stx:syntax-e stx)))))

(deftest sexp-to-syntax-list ()
  "List S-expressions become list syntax objects with children"
  (let ((stx (shrubbery::sexp->syntax '(f x y) (cons 0 5))))
    (is (stx:syntax-object-p stx))
    (let ((children (stx:syntax-e stx)))
      (is (= 3 (length children)))
      (is (every #'stx:syntax-object-p children))
      (is (eq 'f (stx:syntax-e (first children))))
      (is (eq 'x (stx:syntax-e (second children))))
      (is (eq 'y (stx:syntax-e (third children)))))))

(deftest sexp-to-syntax-nested ()
  "Nested S-expressions produce nested syntax objects"
  (let ((stx (shrubbery::sexp->syntax '((a b) (c d)) (cons 0 10))))
    (is (stx:syntax-object-p stx))
    (let ((children (stx:syntax-e stx)))
      (is (= 2 (length children)))
      (is (every #'stx:syntax-object-p children))
      ;; First child is a list
      (let ((first-children (stx:syntax-e (first children))))
        (is (= 2 (length first-children)))
        (is (eq 'a (stx:syntax-e (first first-children))))))))

(deftest sexp-to-syntax-nil-source ()
  "NIL source span is accepted"
  (let ((stx (shrubbery::sexp->syntax 42 nil)))
    (is (stx:syntax-object-p stx))
    (is (null (stx:syntax-object-source stx)))))

;;; ============================================================
;;; Layer 3: translate-enforested (Trapezoid → Coalton S-expressions)
;;; ============================================================

;;; --- Atoms ---

(deftest translate-integer ()
  "Integer literals pass through"
  (is (equal '(42) (sexps "42"))))

(deftest translate-variable ()
  "Variables pass through"
  (is (equal '(x) (sexps "x"))))

;;; --- Binary Operators ---

(deftest translate-addition ()
  "Addition: 1 + 2 → (+ 1 2)"
  (is (equal '((+ 1 2)) (sexps "1 + 2"))))

(deftest translate-subtraction ()
  "Subtraction: 5 - 3 → (- 5 3)"
  (is (equal '((- 5 3)) (sexps "5 - 3"))))

(deftest translate-multiplication ()
  "Multiplication: 2 * 3 → (* 2 3)"
  (is (equal '((* 2 3)) (sexps "2 * 3"))))

(deftest translate-division ()
  "Division: 10 / 2 → (/ 10 2)"
  (is (equal '((/ 10 2)) (sexps "10 / 2"))))

;;; --- Operator Precedence ---

(deftest translate-mul-over-add ()
  "Multiplication binds tighter than addition"
  (is (equal '((+ 1 (* 2 3))) (sexps "1 + 2 * 3"))))

(deftest translate-div-over-sub ()
  "Division binds tighter than subtraction"
  (is (equal '((- 10 (/ 6 2))) (sexps "10 - 6 / 2"))))

(deftest translate-parens-override ()
  "Parentheses override precedence"
  (is (equal '((* (+ 1 2) 3)) (sexps "(1 + 2) * 3"))))

(deftest translate-left-associative-add ()
  "Addition is left-associative"
  (is (equal '((+ (+ 1 2) 3)) (sexps "1 + 2 + 3"))))

(deftest translate-left-associative-sub ()
  "Subtraction is left-associative"
  (is (equal '((- (- 10 3) 2)) (sexps "10 - 3 - 2"))))

(deftest translate-complex-precedence ()
  "Complex mixed precedence"
  (is (equal '((+ (+ 1 (* 2 3)) 4)) (sexps "1 + 2 * 3 + 4"))))

(deftest translate-nested-parens ()
  "Nested parentheses unwrap"
  (is (equal '((+ 1 2)) (sexps "((1 + 2))"))))

;;; --- Comparison Operators ---

(deftest translate-greater-than ()
  "Greater than comparison"
  (is (equal '((> x 0)) (sexps "x > 0"))))

(deftest translate-less-than ()
  "Less than comparison"
  (is (equal '((< x 10)) (sexps "x < 10"))))

(deftest translate-equality ()
  "Equality comparison"
  (is (equal '((== a b)) (sexps "a == b"))))

(deftest translate-arith-then-compare ()
  "Arithmetic has higher precedence than comparison"
  (is (equal '((> (+ x 1) y)) (sexps "x + 1 > y"))))

;;; --- Definitions ---

(deftest translate-simple-define ()
  "Simple value definition"
  (is (equal '((coalton:define x 5)) (sexps "def x = 5"))))

(deftest translate-define-expression ()
  "Definition with expression value"
  (is (equal '((coalton:define x (+ 1 2))) (sexps "def x = 1 + 2"))))

(deftest translate-define-function ()
  "Function definition via def + lambda unwraps into define"
  (is (equal '((coalton:define (f x) (+ x 1)))
             (sexps "def f = fun(x): x + 1"))))

;;; --- Lambdas ---

(deftest translate-single-param-lambda ()
  "Single parameter lambda"
  (is (equal '((coalton:fn (x) (+ x 1)))
             (sexps "fun(x): x + 1"))))

(deftest translate-multi-param-lambda ()
  "Multi-parameter lambda"
  (is (equal '((coalton:fn (x y) (+ x y)))
             (sexps "fun(x, y): x + y"))))

;;; --- Function Calls ---

(deftest translate-single-arg-call ()
  "Single argument function call"
  (is (equal '((f x)) (sexps "f(x)"))))

(deftest translate-multi-arg-call ()
  "Multiple argument function call"
  (is (equal '((f x y)) (sexps "f(x, y)"))))

(deftest translate-nested-call ()
  "Nested function calls"
  (is (equal '((f (g x))) (sexps "f(g(x))"))))

(deftest translate-call-with-expression ()
  "Function call with expression argument"
  (is (equal '((f (+ x 1))) (sexps "f(x + 1)"))))

(deftest translate-call-complex-args ()
  "Function call with complex arguments"
  (is (equal '((f (+ x 1) (* y 2))) (sexps "f(x + 1, y * 2)"))))

;;; --- Multiple Top-level Forms ---

(deftest translate-two-defines ()
  "Two definitions on separate lines"
  (is (equal '((coalton:define x 5)
               (coalton:define y 10))
             (sexps (format nil "def x = 5~%def y = 10")))))

(deftest translate-three-defines ()
  "Three definitions on separate lines"
  (is (equal '((coalton:define a 1)
               (coalton:define b 2)
               (coalton:define c 3))
             (sexps (format nil "def a = 1~%def b = 2~%def c = 3")))))

;;; --- Mixed Expressions ---

(deftest translate-define-with-call ()
  "Definition with function call value"
  (is (equal '((coalton:define result (f (+ x 1))))
             (sexps "def result = f(x + 1)"))))

(deftest translate-define-complex-expression ()
  "Definition with complex parenthesized expression"
  (is (equal '((coalton:define z (* (+ a b) (+ c d))))
             (sexps "def z = (a + b) * (c + d)"))))

;;; ============================================================
;;; Layer 4: Source Location Mapping
;;; ============================================================

(deftest build-line-offsets-empty ()
  "Empty string produces offsets for line 1 at position 0"
  (let ((offsets (shrubbery::build-line-offsets "")))
    (is (= 2 (length offsets)))
    (is (= 0 (aref offsets 1)))))

(deftest build-line-offsets-single-line ()
  "Single line produces one offset"
  (let ((offsets (shrubbery::build-line-offsets "hello")))
    (is (= 2 (length offsets)))
    (is (= 0 (aref offsets 1)))))

(deftest build-line-offsets-multi-line ()
  "Multiple lines produce correct offsets"
  (let ((offsets (shrubbery::build-line-offsets (format nil "abc~%def~%ghi"))))
    (is (= 4 (length offsets)))
    (is (= 0 (aref offsets 1)))    ; line 1 starts at 0
    (is (= 4 (aref offsets 2)))    ; line 2 starts after "abc\n"
    (is (= 8 (aref offsets 3)))))  ; line 3 starts after "abc\ndef\n"

(deftest line-col-to-offset ()
  "Line/column conversion works correctly"
  (let ((offsets (shrubbery::build-line-offsets (format nil "abc~%def~%ghi"))))
    (is (= 0 (shrubbery::line-col->offset offsets 1 1)))   ; 'a'
    (is (= 2 (shrubbery::line-col->offset offsets 1 3)))   ; 'c'
    (is (= 4 (shrubbery::line-col->offset offsets 2 1)))   ; 'd'
    (is (= 9 (shrubbery::line-col->offset offsets 3 2))))) ; 'h'

(deftest line-col-nil-returns-zero ()
  "NIL line or column returns 0"
  (let ((offsets (shrubbery::build-line-offsets "abc")))
    (is (= 0 (shrubbery::line-col->offset offsets nil 1)))
    (is (= 0 (shrubbery::line-col->offset offsets 1 nil)))))

;;; ============================================================
;;; Layer 5: Full Pipeline (parse-shrubbery-toplevel)
;;; ============================================================

(deftest parse-toplevel-simple-define ()
  "Simple definition parses to a program with one define"
  (let* ((text "def x = 5")
         (source (source:make-source-string text :name "test"))
         (program (shrubbery:parse-shrubbery-toplevel text source)))
    (is (= 1 (length (parser:program-defines program))))))

(deftest parse-toplevel-multiple-defines ()
  "Multiple definitions parse to a program with multiple defines"
  (let* ((text (format nil "def x = 5~%def y = 10"))
         (source (source:make-source-string text :name "test"))
         (program (shrubbery:parse-shrubbery-toplevel text source)))
    (is (= 2 (length (parser:program-defines program))))))

(deftest parse-toplevel-function-define ()
  "Function definition (def + lambda) produces a define with params"
  (let* ((text "def f = fun(x): x + 1")
         (source (source:make-source-string text :name "test"))
         (program (shrubbery:parse-shrubbery-toplevel text source)))
    (is (= 1 (length (parser:program-defines program))))
    (let ((def (first (parser:program-defines program))))
      (is (not (null (parser:toplevel-define-params def)))))))

;;; ============================================================
;;; Layer 6: End-to-End (coalton-shrubbery macro)
;;; ============================================================

(deftest end-to-end-simple-define ()
  "Simple value definition compiles and is accessible"
  (eval '(coalton:coalton-shrubbery "def shrubbery-test-x = 42"))
  (is (= 42 (symbol-value (find-symbol "SHRUBBERY-TEST-X" *package*)))))

(deftest end-to-end-function-define ()
  "Function definition compiles and is callable"
  (eval '(coalton:coalton-shrubbery "def shrubbery-test-add = fun(a, b): a + b"))
  (let ((fn (symbol-function (find-symbol "SHRUBBERY-TEST-ADD" *package*))))
    (is (= 3 (funcall fn 1 2)))
    (is (= 7 (funcall fn 3 4)))))

(deftest end-to-end-expression ()
  "Arithmetic expressions compile correctly"
  (eval '(coalton:coalton-shrubbery "def shrubbery-test-expr = (2 + 3) * 4"))
  (is (= 20 (symbol-value (find-symbol "SHRUBBERY-TEST-EXPR" *package*)))))

(deftest end-to-end-multiple-defs ()
  "Multiple definitions compile together"
  (eval `(coalton:coalton-shrubbery ,(format nil "def shrubbery-test-a = 10~%def shrubbery-test-b = 20")))
  (is (= 10 (symbol-value (find-symbol "SHRUBBERY-TEST-A" *package*))))
  (is (= 20 (symbol-value (find-symbol "SHRUBBERY-TEST-B" *package*)))))
