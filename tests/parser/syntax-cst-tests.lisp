;;;; Tests for syntax abstraction layer
;;;;
;;;; These tests verify the syntax-cst interface for working with syntax objects,
;;;; including predicates, list operations, traversal, and CST conversion.

(fiasco:define-test-package #:coalton-impl/parser/syntax-cst-tests
  (:use #:cl)
  (:local-nicknames
   (#:cst #:concrete-syntax-tree)
   (#:parser #:coalton-impl/parser)
   (#:source #:coalton-impl/source)
   (#:scope #:coalton-impl/parser/scope)
   (#:stx #:coalton-impl/parser/syntax-object)
   (#:stx-cst #:coalton-impl/parser/syntax-cst)))

(in-package #:coalton-impl/parser/syntax-cst-tests)

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
;;; Predicate Tests
;;;

(deftest stx-null-p ()
  "stx-null-p returns T for nil datum"
  (let ((nil-stx (stx:make-syntax-object nil))
        (nonempty-stx (stx:make-list-syntax (list (stx:make-identifier-syntax 'a)))))
    (is (stx-cst:stx-null-p nil-stx))
    (is (not (stx-cst:stx-null-p nonempty-stx)))))

(deftest stx-consp ()
  "stx-consp returns T for non-empty lists"
  (let ((nil-stx (stx:make-syntax-object nil))
        (nonempty-stx (stx:make-list-syntax (list (stx:make-identifier-syntax 'a))))
        (atom-stx (stx:make-identifier-syntax 'foo)))
    (is (not (stx-cst:stx-consp nil-stx)))
    (is (stx-cst:stx-consp nonempty-stx))
    (is (not (stx-cst:stx-consp atom-stx)))))

(deftest stx-atom-p ()
  "stx-atom-p returns T for atoms"
  (let ((symbol-stx (stx:make-identifier-syntax 'foo))
        (number-stx (stx:make-atom-syntax 42))
        (list-stx (stx:make-list-syntax (list (stx:make-identifier-syntax 'a)))))
    (is (stx-cst:stx-atom-p symbol-stx))
    (is (stx-cst:stx-atom-p number-stx))
    (is (not (stx-cst:stx-atom-p list-stx)))))

(deftest stx-identifier-p ()
  "stx-identifier-p returns T for identifiers (excludes keywords and booleans)"
  (let ((ident-stx (stx:make-identifier-syntax 'foo))
        (keyword-stx (stx:make-syntax-object :keyword))
        (true-stx (stx:make-syntax-object t))
        (nil-stx (stx:make-syntax-object nil))
        (number-stx (stx:make-atom-syntax 42)))
    (is (stx-cst:stx-identifier-p ident-stx))
    (is (not (stx-cst:stx-identifier-p keyword-stx)))
    (is (not (stx-cst:stx-identifier-p true-stx)))
    (is (not (stx-cst:stx-identifier-p nil-stx)))
    (is (not (stx-cst:stx-identifier-p number-stx)))))

(deftest stx-keyword-p ()
  "stx-keyword-p returns T for keywords"
  (let ((keyword-stx (stx:make-syntax-object :my-keyword))
        (ident-stx (stx:make-identifier-syntax 'foo)))
    (is (stx-cst:stx-keyword-p keyword-stx))
    (is (not (stx-cst:stx-keyword-p ident-stx)))))

(deftest stx-literal-p ()
  "stx-literal-p returns T for numbers, strings, characters"
  (let ((num-stx (stx:make-atom-syntax 42))
        (str-stx (stx:make-atom-syntax "hello"))
        (char-stx (stx:make-atom-syntax #\a))
        (sym-stx (stx:make-identifier-syntax 'foo)))
    (is (stx-cst:stx-literal-p num-stx))
    (is (stx-cst:stx-literal-p str-stx))
    (is (stx-cst:stx-literal-p char-stx))
    (is (not (stx-cst:stx-literal-p sym-stx)))))

(deftest stx-list-p ()
  "stx-list-p returns T for all lists (including empty)"
  (let ((empty-stx (stx:make-syntax-object nil))
        (nonempty-stx (stx:make-list-syntax (list (stx:make-identifier-syntax 'a))))
        (atom-stx (stx:make-identifier-syntax 'foo)))
    (is (stx-cst:stx-list-p empty-stx))
    (is (stx-cst:stx-list-p nonempty-stx))
    (is (not (stx-cst:stx-list-p atom-stx)))))

(deftest stx-symbol-p ()
  "stx-symbol-p returns T for all symbols (including keywords)"
  (let ((ident-stx (stx:make-identifier-syntax 'foo))
        (keyword-stx (stx:make-syntax-object :key))
        (nil-stx (stx:make-syntax-object nil))
        (number-stx (stx:make-atom-syntax 42)))
    (is (stx-cst:stx-symbol-p ident-stx))
    (is (stx-cst:stx-symbol-p keyword-stx))
    (is (stx-cst:stx-symbol-p nil-stx))
    (is (not (stx-cst:stx-symbol-p number-stx)))))

;;;
;;; List Operation Tests
;;;

(deftest stx-first ()
  "stx-first returns first element"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (list-stx (stx:make-list-syntax (list a b))))
    (is (eq a (stx-cst:stx-first list-stx)))))

(deftest stx-rest ()
  "stx-rest returns rest as syntax object"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (c (stx:make-identifier-syntax 'c))
         (list-stx (stx:make-list-syntax (list a b c)))
         (rest (stx-cst:stx-rest list-stx)))
    (is (stx:syntax-object-p rest))
    (is (= 2 (stx-cst:stx-length rest)))
    (is (eq b (stx-cst:stx-first rest)))))

(deftest stx-second ()
  "stx-second returns second element"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (list-stx (stx:make-list-syntax (list a b))))
    (is (eq b (stx-cst:stx-second list-stx)))))

(deftest stx-third ()
  "stx-third returns third element"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (c (stx:make-identifier-syntax 'c))
         (list-stx (stx:make-list-syntax (list a b c))))
    (is (eq c (stx-cst:stx-third list-stx)))))

(deftest stx-nth ()
  "stx-nth returns nth element (0-indexed)"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (c (stx:make-identifier-syntax 'c))
         (list-stx (stx:make-list-syntax (list a b c))))
    (is (eq a (stx-cst:stx-nth 0 list-stx)))
    (is (eq b (stx-cst:stx-nth 1 list-stx)))
    (is (eq c (stx-cst:stx-nth 2 list-stx)))))

(deftest stx-length ()
  "stx-length returns correct count"
  (let ((empty (stx:make-syntax-object nil))
        (one (stx:make-list-syntax (list (stx:make-identifier-syntax 'a))))
        (three (stx:make-list-syntax (list (stx:make-identifier-syntax 'a)
                                            (stx:make-identifier-syntax 'b)
                                            (stx:make-identifier-syntax 'c)))))
    (is (= 0 (stx-cst:stx-length empty)))
    (is (= 1 (stx-cst:stx-length one)))
    (is (= 3 (stx-cst:stx-length three)))))

(deftest stx-list ()
  "stx-list creates list syntax from elements"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (result (stx-cst:stx-list a b)))
    (is (stx:syntax-object-p result))
    (is (= 2 (stx-cst:stx-length result)))
    (is (eq a (stx-cst:stx-first result)))
    (is (eq b (stx-cst:stx-second result)))))

(deftest stx-list* ()
  "stx-list* creates list with tail"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (c (stx:make-identifier-syntax 'c))
         (result (stx-cst:stx-list* a b c)))
    ;; Result should be (a b . c) which as a proper list would be (a b c)
    ;; but list* creates improper list, so we just check it's a syntax object
    (is (stx:syntax-object-p result))))

(deftest stx-append ()
  "stx-append concatenates list syntaxes"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (c (stx:make-identifier-syntax 'c))
         (list1 (stx:make-list-syntax (list a b)))
         (list2 (stx:make-list-syntax (list c)))
         (result (stx-cst:stx-append list1 list2)))
    (is (= 3 (stx-cst:stx-length result)))
    (is (eq a (stx-cst:stx-nth 0 result)))
    (is (eq b (stx-cst:stx-nth 1 result)))
    (is (eq c (stx-cst:stx-nth 2 result)))))

;;;
;;; Traversal Tests
;;;

(deftest stx-map ()
  "stx-map applies function to elements"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (list-stx (stx:make-list-syntax (list a b)))
         (result (stx-cst:stx-map
                  (lambda (elem)
                    (stx:make-syntax-object (list 'wrapped (stx:syntax-e elem))))
                  list-stx)))
    (is (stx:syntax-object-p result))
    (is (= 2 (stx-cst:stx-length result)))))

(deftest stx-for-each ()
  "stx-for-each applies function for side effects"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (list-stx (stx:make-list-syntax (list a b)))
         (collected nil))
    (stx-cst:stx-for-each
     (lambda (elem)
       (push (stx:syntax-e elem) collected))
     list-stx)
    (is (equal '(b a) collected))))

(deftest stx-fold ()
  "stx-fold accumulates result"
  (let* ((a (stx:make-atom-syntax 1))
         (b (stx:make-atom-syntax 2))
         (c (stx:make-atom-syntax 3))
         (list-stx (stx:make-list-syntax (list a b c)))
         (sum (stx-cst:stx-fold
               (lambda (acc elem)
                 (+ acc (stx:syntax-e elem)))
               0
               list-stx)))
    (is (= 6 sum))))

;;;
;;; Source and Scopes Tests
;;;

(deftest stx-source ()
  "stx-source returns source location"
  (let* ((source (cons 10 20))
         (stx (stx:make-syntax-object 'foo :source source)))
    (is (equal source (stx-cst:stx-source stx)))))

(deftest stx-scopes ()
  "stx-scopes returns scope set"
  (let* ((token (scope:make-scope-token))
         (scopes (scope:scope-set-add (scope:empty-scope-set) token))
         (stx (stx:make-syntax-object 'foo :scopes scopes)))
    (is (scope:scope-set-member-p (stx-cst:stx-scopes stx) token))))

;;;
;;; Symbol Operation Tests
;;;

(deftest stx-symbol ()
  "stx-symbol returns symbol datum"
  (let ((stx (stx:make-identifier-syntax 'my-symbol)))
    (is (eq 'my-symbol (stx-cst:stx-symbol stx)))))

(deftest stx-symbol-name ()
  "stx-symbol-name returns symbol name string"
  (let ((stx (stx:make-identifier-syntax 'my-symbol)))
    (is (string= "MY-SYMBOL" (stx-cst:stx-symbol-name stx)))))

(deftest stx-keyword ()
  "stx-keyword returns keyword datum"
  (let ((stx (stx:make-syntax-object :my-keyword)))
    (is (eq :my-keyword (stx-cst:stx-keyword stx)))))

;;;
;;; CST Conversion Tests
;;;

(deftest cst->syntax-atom ()
  "cst->syntax converts atomic CST to syntax"
  (let* ((cst (make-atom-cst 42))
         (stx (stx-cst:cst->syntax cst)))
    (is (stx:syntax-object-p stx))
    (is (eql 42 (stx:syntax-e stx)))
    (is (scope:scope-set-empty-p (stx:syntax-object-scopes stx)))))

(deftest cst->syntax-symbol ()
  "cst->syntax converts symbol CST to syntax"
  (let* ((cst (make-atom-cst 'foo))
         (stx (stx-cst:cst->syntax cst)))
    (is (stx:syntax-object-p stx))
    (is (symbolp (stx:syntax-e stx)))
    (is (eq 'foo (stx:syntax-e stx)))))

(deftest cst->syntax-list ()
  "cst->syntax converts list CST to syntax"
  (let* ((cst (make-list-cst (list (make-atom-cst 'a)
                                    (make-atom-cst 'b)
                                    (make-atom-cst 'c))))
         (stx (stx-cst:cst->syntax cst)))
    (is (stx:syntax-object-p stx))
    (is (listp (stx:syntax-e stx)))
    (is (= 3 (stx-cst:stx-length stx)))
    ;; Elements are also syntax objects
    (dolist (elem (stx:syntax-e stx))
      (is (stx:syntax-object-p elem)))))

(deftest cst->syntax-nested ()
  "cst->syntax handles nested lists"
  (let* ((inner (make-list-cst (list (make-atom-cst 'b) (make-atom-cst 'c))))
         (cst (make-list-cst (list (make-atom-cst 'a)
                                    inner
                                    (make-atom-cst 'd))))
         (stx (stx-cst:cst->syntax cst)))
    (is (= 3 (stx-cst:stx-length stx)))
    ;; Second element is a nested list
    (let ((inner-stx (stx-cst:stx-second stx)))
      (is (stx:syntax-object-p inner-stx))
      (is (stx-cst:stx-list-p inner-stx))
      (is (= 2 (stx-cst:stx-length inner-stx))))))

(deftest cst->syntax-preserves-source ()
  "cst->syntax preserves source location"
  (let* ((source (cons 0 10))
         (cst (make-atom-cst 'foo source))
         (stx (stx-cst:cst->syntax cst)))
    ;; Source info should be preserved
    (is (equal source (stx:syntax-object-source stx)))))

(deftest cst->syntax-with-scopes ()
  "cst->syntax-with-scopes applies provided scopes"
  (let* ((token (scope:make-scope-token))
         (scopes (scope:scope-set-add (scope:empty-scope-set) token))
         (cst (make-list-cst (list (make-atom-cst 'a) (make-atom-cst 'b))))
         (stx (stx-cst:cst->syntax-with-scopes cst scopes)))
    ;; Outer syntax has scopes
    (is (scope:scope-set-member-p (stx:syntax-object-scopes stx) token))
    ;; Inner elements also have scopes
    (dolist (elem (stx:syntax-e stx))
      (is (scope:scope-set-member-p (stx:syntax-object-scopes elem) token)))))

;;;
;;; Error Condition Tests
;;;

(deftest stx-first-empty-error ()
  "stx-first on empty list signals error"
  (let ((empty (stx:make-syntax-object nil)))
    (signals error (stx-cst:stx-first empty))))

(deftest stx-rest-empty-error ()
  "stx-rest on empty list signals error"
  (let ((empty (stx:make-syntax-object nil)))
    (signals error (stx-cst:stx-rest empty))))

(deftest stx-nth-out-of-bounds-error ()
  "stx-nth out of bounds signals error"
  (let ((list-stx (stx:make-list-syntax (list (stx:make-identifier-syntax 'a)))))
    (signals error (stx-cst:stx-nth 5 list-stx))))

(deftest stx-symbol-non-symbol-error ()
  "stx-symbol on non-symbol signals error"
  (let ((num-stx (stx:make-atom-syntax 42)))
    (signals error (stx-cst:stx-symbol num-stx))))

(deftest stx-keyword-non-keyword-error ()
  "stx-keyword on non-keyword signals error"
  (let ((sym-stx (stx:make-identifier-syntax 'foo)))
    (signals error (stx-cst:stx-keyword sym-stx))))

(deftest stx-first-non-list-error ()
  "stx-first on non-list signals error"
  (let ((atom-stx (stx:make-identifier-syntax 'foo)))
    (signals error (stx-cst:stx-first atom-stx))))

(deftest stx-map-non-list-error ()
  "stx-map on non-list signals error"
  (let ((atom-stx (stx:make-identifier-syntax 'foo)))
    (signals error (stx-cst:stx-map #'identity atom-stx))))

(deftest stx-fold-non-list-error ()
  "stx-fold on non-list signals error"
  (let ((atom-stx (stx:make-identifier-syntax 'foo)))
    (signals error (stx-cst:stx-fold #'+ 0 atom-stx))))

(deftest stx-length-non-list-error ()
  "stx-length on non-list signals error"
  (let ((atom-stx (stx:make-identifier-syntax 'foo)))
    (signals error (stx-cst:stx-length atom-stx))))
