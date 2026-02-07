;;;; Standalone test runner for the Shrubbery/Rhombus syntax frontend.
;;;;
;;;; This script tests the translation logic independently from the full
;;;; Coalton build system. It loads trapezoid and the translation functions
;;;; directly, then verifies the shrubbery→Coalton S-expression translation.
;;;;
;;;; Usage:
;;;;   cd coalton-shrubbery
;;;;   sbcl --noinform --no-userinit --no-sysinit --load scripts/run-shrubbery-tests.lisp
;;;;
;;;; Note: On SBCL 2.6.1, trapezoid must be loaded in interpreted mode
;;;; due to a compiler bug with cross-file function references after
;;;; loading conditions.lisp. This does not affect compiled FASL usage.

(require "asdf")

;; Work around SBCL 2.6.1 compiler hang with trapezoid's conditions.lisp.
;; The interpreted evaluator handles all trapezoid code correctly.
(setf *evaluator-mode* :interpret)

;; Create minimal coalton package for symbol references
(unless (find-package "COALTON")
  (defpackage #:coalton
    (:use)
    (:export #:define #:fn #:if #:match #:progn #:make-list #:the
             #:declare #:define-type #:define-class #:define-instance)))

;; Load trapezoid
(handler-bind ((style-warning #'muffle-warning)
               (warning #'muffle-warning))
  (dolist (file '("main.lisp" "conditions.lisp" "characters.lisp" "syntax.lisp"
                  "tokenizer.lisp" "reader.lisp" "parser.lisp" "enforest.lisp"
                  "runtime.lisp"))
    (load (merge-pathnames file "src/" (truename "../trapezoid/")) :verbose nil)))

(format t ";; Trapezoid loaded~%")
(force-output)

;;; ============================================================
;;; Translation Functions (standalone copy)
;;; ============================================================
;;;
;;; These mirror the functions in src/parser/shrubbery.lisp but work
;;; without the full Coalton compiler loaded.

(defpackage #:shrubbery-standalone-test
  (:use #:cl)
  (:local-nicknames (#:trap #:trapezoid)))

(in-package #:shrubbery-standalone-test)

(defun translate-enforested (form)
  "Translate trapezoid enforested output to Coalton S-expressions."
  (cond
    ((null form) nil)
    ((atom form) form)
    ((eq (car form) 'trap:call)
     (cons (translate-enforested (second form))
           (mapcar #'translate-enforested (cddr form))))
    ((eq (car form) 'trap:define)
     (let ((name (second form))
           (value (translate-enforested (third form))))
       (if (and (consp value) (eq (car value) 'coalton:fn))
           (list* 'coalton:define (cons name (second value)) (cddr value))
           (list 'coalton:define name value))))
    ((eq (car form) 'cl:lambda)
     (list 'coalton:fn (second form)
           (let ((translated (mapcar #'translate-enforested (cddr form))))
             (if (= 1 (length translated)) (first translated)
                 (cons 'coalton:progn translated)))))
    ((eq (car form) 'cl:if)
     (list* 'coalton:if
            (translate-enforested (second form))
            (translate-enforested (third form))
            (when (fourth form) (list (translate-enforested (fourth form))))))
    ((eq (car form) 'trap:match)
     (list* 'coalton:match (translate-enforested (second form))
            (mapcar (lambda (branch)
                      (list (translate-pattern (first branch))
                            (translate-enforested (second branch))))
                    (cddr form))))
    ((eq (car form) 'cl:progn)
     (let ((translated (mapcar #'translate-enforested (cdr form))))
       (if (= 1 (length translated)) (first translated)
           (cons 'coalton:progn translated))))
    ((eq (car form) 'cl:list)
     (cons 'coalton:make-list (mapcar #'translate-enforested (cdr form))))
    (t (mapcar #'translate-enforested form))))

(defun translate-pattern (pat)
  "Translate pattern from trapezoid to Coalton format."
  (cond
    ((atom pat) pat)
    ((eq (car pat) 'trap:call)
     (cons (second pat) (mapcar #'translate-pattern (cddr pat))))
    (t pat)))

(defun shrubbery->coalton-sexps (text)
  "Full pipeline: shrubbery text → list of Coalton S-expressions."
  (let ((trap:*produce-syntax-objects* nil))
    (let* ((parsed (trap:parse-shrubbery text))
           (forms (if (and (consp parsed) (eq (car parsed) 'trap:group))
                      (list parsed)
                      (if (consp parsed) parsed (list parsed)))))
      (mapcar (lambda (form) (translate-enforested (trap:enforest form)))
              forms))))

;;; ============================================================
;;; Test Runner
;;; ============================================================

(in-package #:cl-user)

(defvar *pass-count* 0)
(defvar *fail-count* 0)
(defvar *failed-tests* nil)

(defun run-test (name input expected)
  (handler-case
      (let ((result (shrubbery-standalone-test::shrubbery->coalton-sexps input)))
        (if (equal result expected)
            (progn (incf *pass-count*)
                   (format t "  PASS  ~A~%" name))
            (progn (incf *fail-count*)
                   (push name *failed-tests*)
                   (format t "  FAIL  ~A~%        expected: ~S~%        got:      ~S~%" name expected result))))
    (error (c)
      (incf *fail-count*)
      (push name *failed-tests*)
      (format t "  ERROR ~A~%        ~A~%" name c)))
  (force-output))

(format t "~%;; ==========================================================~%")
(format t ";; Shrubbery/Rhombus Syntax Translation Tests~%")
(format t ";; ==========================================================~%~%")

;;; --- Atomic Expressions ---
(format t ";; Atoms~%")
(run-test "integer literal" "42" '(42))
(run-test "variable reference" "x" '(x))
;; Note: negative literals like "-5" are not supported by trapezoid's
;; enforester (treats `-` as infix operator). Negative numbers should
;; be written as `0 - 5` or handled via a negate function.

;;; --- Binary Operators ---
(format t "~%;; Binary Operators~%")
(run-test "addition" "1 + 2" '((+ 1 2)))
(run-test "subtraction" "5 - 3" '((- 5 3)))
(run-test "multiplication" "2 * 3" '((* 2 3)))
(run-test "division" "10 / 2" '((/ 10 2)))

;;; --- Operator Precedence ---
(format t "~%;; Operator Precedence~%")
(run-test "mul binds tighter than add" "1 + 2 * 3" '((+ 1 (* 2 3))))
(run-test "div binds tighter than sub" "10 - 6 / 2" '((- 10 (/ 6 2))))
(run-test "parens override precedence" "(1 + 2) * 3" '((* (+ 1 2) 3)))
(run-test "left-assoc addition" "1 + 2 + 3" '((+ (+ 1 2) 3)))
(run-test "left-assoc subtraction" "10 - 3 - 2" '((- (- 10 3) 2)))
(run-test "complex mixed precedence" "1 + 2 * 3 + 4" '((+ (+ 1 (* 2 3)) 4)))
(run-test "nested parentheses" "((1 + 2))" '((+ 1 2)))
(run-test "both sides parenthesized" "(1 + 2) * (3 + 4)" '((* (+ 1 2) (+ 3 4))))

;;; --- Comparison Operators ---
(format t "~%;; Comparison Operators~%")
(run-test "greater than" "x > 0" '((> x 0)))
(run-test "less than" "x < 10" '((< x 10)))
(run-test "equality" "a == b" '((== a b)))
(run-test "not equal" "a != b" '((!= a b)))
(run-test "arithmetic then compare" "x + 1 > y" '((> (+ x 1) y)))

;;; --- Value Definitions ---
(format t "~%;; Value Definitions~%")
(run-test "simple def" "def x = 5" '((coalton:define x 5)))
(run-test "def with expression" "def x = 1 + 2" '((coalton:define x (+ 1 2))))
(run-test "def with complex expr" "def z = (a + b) * (c + d)"
          '((coalton:define z (* (+ a b) (+ c d)))))

;;; --- Function Definitions ---
(format t "~%;; Function Definitions~%")
(run-test "def function via lambda" "def f = fun(x): x + 1"
          '((coalton:define (f x) (+ x 1))))
(run-test "def 2-arg function" "def add = fun(x, y): x + y"
          '((coalton:define (add x y) (+ x y))))

;;; --- Lambda Expressions ---
(format t "~%;; Lambda Expressions~%")
(run-test "single-param lambda" "fun(x): x + 1" '((coalton:fn (x) (+ x 1))))
(run-test "multi-param lambda" "fun(x, y): x + y" '((coalton:fn (x y) (+ x y))))

;;; --- Function Calls ---
(format t "~%;; Function Calls~%")
(run-test "single arg call" "f(x)" '((f x)))
(run-test "multi arg call" "f(x, y)" '((f x y)))
(run-test "nested call" "f(g(x))" '((f (g x))))
(run-test "call with expr arg" "f(x + 1)" '((f (+ x 1))))
(run-test "call with complex args" "f(x + 1, y * 2)" '((f (+ x 1) (* y 2))))

;;; --- Multiple Top-Level Forms ---
(format t "~%;; Multiple Top-Level Forms~%")
(run-test "two definitions"
          (format nil "def x = 5~%def y = 10")
          '((coalton:define x 5) (coalton:define y 10)))
(run-test "three definitions"
          (format nil "def a = 1~%def b = 2~%def c = 3")
          '((coalton:define a 1) (coalton:define b 2) (coalton:define c 3)))

;;; --- Mixed/Complex ---
(format t "~%;; Mixed Expressions~%")
(run-test "def with function call" "def result = f(x + 1)"
          '((coalton:define result (f (+ x 1)))))
(run-test "nested arithmetic calls" "f(g(1 + 2), h(3 * 4))"
          '((f (g (+ 1 2)) (h (* 3 4)))))

;;; --- Summary ---
(format t "~%;; ==========================================================~%")
(format t ";; Results: ~D passed, ~D failed (of ~D total)~%"
        *pass-count* *fail-count* (+ *pass-count* *fail-count*))
(when *failed-tests*
  (format t ";; Failed: ~{~A~^, ~}~%" (nreverse *failed-tests*)))
(format t ";; ==========================================================~%")

(sb-ext:quit :code (if (zerop *fail-count*) 0 1))
