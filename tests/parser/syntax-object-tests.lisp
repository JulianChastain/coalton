;;;; Tests for syntax object operations
;;;;
;;;; These tests verify the core syntax object functionality used in hygienic
;;;; macro expansion: construction, extraction, and scope manipulation.

(fiasco:define-test-package #:coalton-impl/parser/syntax-object-tests
  (:use #:cl)
  (:local-nicknames
   (#:scope #:coalton-impl/parser/scope)
   (#:stx #:coalton-impl/parser/syntax-object)))

(in-package #:coalton-impl/parser/syntax-object-tests)

;;;
;;; Construction Tests
;;;

(deftest make-syntax-object-basic ()
  "make-syntax-object creates syntax object with defaults"
  (let ((stx (stx:make-syntax-object 'foo)))
    (is (stx:syntax-object-p stx))
    (is (eq 'foo (stx:syntax-object-datum stx)))
    (is (scope:scope-set-empty-p (stx:syntax-object-scopes stx)))
    (is (null (stx:syntax-object-source stx)))
    (is (null (stx:syntax-object-properties stx)))))

(deftest make-syntax-object-with-scopes ()
  "make-syntax-object accepts custom scopes"
  (let* ((token (scope:make-scope-token))
         (scopes (scope:scope-set-add (scope:empty-scope-set) token))
         (stx (stx:make-syntax-object 'foo :scopes scopes)))
    (is (scope:scope-set-member-p (stx:syntax-object-scopes stx) token))))

(deftest make-syntax-object-with-source ()
  "make-syntax-object accepts source location"
  (let* ((source (cons 10 20))
         (stx (stx:make-syntax-object 'foo :source source)))
    (is (equal source (stx:syntax-object-source stx)))))

(deftest make-syntax-object-with-properties ()
  "make-syntax-object accepts properties"
  (let* ((props '((key1 . val1) (key2 . val2)))
         (stx (stx:make-syntax-object 'foo :properties props)))
    (is (equal props (stx:syntax-object-properties stx)))))

(deftest make-identifier-syntax ()
  "make-identifier-syntax creates identifier syntax objects"
  (let* ((token (scope:make-scope-token))
         (scopes (scope:scope-set-add (scope:empty-scope-set) token))
         (source (cons 5 10))
         (stx (stx:make-identifier-syntax 'my-var :scopes scopes :source source)))
    (is (stx:syntax-object-p stx))
    (is (eq 'my-var (stx:syntax-object-datum stx)))
    (is (scope:scope-set-member-p (stx:syntax-object-scopes stx) token))
    (is (equal source (stx:syntax-object-source stx)))))

(deftest make-atom-syntax ()
  "make-atom-syntax creates atomic value syntax objects"
  (let ((num-stx (stx:make-atom-syntax 42))
        (str-stx (stx:make-atom-syntax "hello"))
        (char-stx (stx:make-atom-syntax #\a)))
    (is (eql 42 (stx:syntax-object-datum num-stx)))
    (is (equal "hello" (stx:syntax-object-datum str-stx)))
    (is (eql #\a (stx:syntax-object-datum char-stx)))))

(deftest make-list-syntax ()
  "make-list-syntax creates list syntax objects"
  (let* ((elem1 (stx:make-identifier-syntax 'a))
         (elem2 (stx:make-identifier-syntax 'b))
         (list-stx (stx:make-list-syntax (list elem1 elem2))))
    (is (stx:syntax-object-p list-stx))
    (is (listp (stx:syntax-object-datum list-stx)))
    (is (= 2 (length (stx:syntax-object-datum list-stx))))))

;;;
;;; Core Operation Tests
;;;

(deftest syntax-e-extracts-datum ()
  "syntax-e extracts the datum from syntax object"
  (let ((stx (stx:make-syntax-object 'foo)))
    (is (eq 'foo (stx:syntax-e stx)))))

(deftest syntax-e-shallow-extraction ()
  "syntax-e does not unwrap nested syntax objects"
  (let* ((inner (stx:make-identifier-syntax 'inner))
         (outer (stx:make-list-syntax (list inner))))
    (let ((datum (stx:syntax-e outer)))
      (is (listp datum))
      (is (stx:syntax-object-p (first datum))))))

(deftest syntax->datum-strips-wrappers ()
  "syntax->datum recursively strips syntax wrappers"
  (let ((stx (stx:make-syntax-object 'foo)))
    (is (eq 'foo (stx:syntax->datum stx)))))

(deftest syntax->datum-recursive ()
  "syntax->datum unwraps nested syntax objects in lists"
  (let* ((a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (inner (stx:make-list-syntax (list a b)))
         (outer (stx:make-list-syntax (list inner)))
         (datum (stx:syntax->datum outer)))
    (is (equal '((a b)) datum))))

(deftest datum->syntax-copies-scopes ()
  "datum->syntax copies scopes from context"
  (let* ((token (scope:make-scope-token))
         (scopes (scope:scope-set-add (scope:empty-scope-set) token))
         (context (stx:make-syntax-object 'context :scopes scopes))
         (result (stx:datum->syntax context 'new-datum)))
    (is (stx:syntax-object-p result))
    (is (eq 'new-datum (stx:syntax-e result)))
    (is (scope:scope-set-member-p (stx:syntax-object-scopes result) token))))

(deftest datum->syntax-handles-lists ()
  "datum->syntax recursively wraps list elements"
  (let* ((token (scope:make-scope-token))
         (scopes (scope:scope-set-add (scope:empty-scope-set) token))
         (context (stx:make-syntax-object 'context :scopes scopes))
         (result (stx:datum->syntax context '(a b c))))
    (is (listp (stx:syntax-e result)))
    (is (= 3 (length (stx:syntax-e result))))
    ;; Each element should have the context's scopes
    (dolist (elem (stx:syntax-e result))
      (is (stx:syntax-object-p elem))
      (is (scope:scope-set-member-p (stx:syntax-object-scopes elem) token)))))

(deftest datum->syntax-preserves-existing-syntax ()
  "datum->syntax preserves existing syntax objects in input"
  (let* ((token1 (scope:make-scope-token))
         (token2 (scope:make-scope-token))
         (scopes1 (scope:scope-set-add (scope:empty-scope-set) token1))
         (scopes2 (scope:scope-set-add (scope:empty-scope-set) token2))
         (existing (stx:make-syntax-object 'existing :scopes scopes1))
         (context (stx:make-syntax-object 'context :scopes scopes2))
         (result (stx:datum->syntax context (list existing 'raw))))
    (let ((elements (stx:syntax-e result)))
      ;; First element should be the preserved syntax object
      (is (eq existing (first elements)))
      ;; Second element should be wrapped with context's scopes
      (is (scope:scope-set-member-p
           (stx:syntax-object-scopes (second elements))
           token2)))))

;;;
;;; Scope Manipulation Tests
;;;

(deftest stx-add-scope-adds-to-identifier ()
  "stx-add-scope adds scope to identifier syntax"
  (let* ((token (scope:make-scope-token))
         (stx (stx:make-identifier-syntax 'foo))
         (result (stx:stx-add-scope stx token)))
    (is (scope:scope-set-member-p (stx:syntax-object-scopes result) token))
    ;; Original unchanged
    (is (not (scope:scope-set-member-p (stx:syntax-object-scopes stx) token)))))

(deftest stx-add-scope-recursive ()
  "stx-add-scope adds scope recursively to nested lists"
  (let* ((token (scope:make-scope-token))
         (a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (inner (stx:make-list-syntax (list a b)))
         (outer (stx:make-list-syntax (list inner)))
         (result (stx:stx-add-scope outer token)))
    ;; Outer list has scope
    (is (scope:scope-set-member-p (stx:syntax-object-scopes result) token))
    ;; Inner list has scope
    (let ((inner-result (first (stx:syntax-e result))))
      (is (scope:scope-set-member-p (stx:syntax-object-scopes inner-result) token))
      ;; Inner elements have scope
      (dolist (elem (stx:syntax-e inner-result))
        (is (scope:scope-set-member-p (stx:syntax-object-scopes elem) token))))))

(deftest stx-add-scope-preserves-properties ()
  "stx-add-scope preserves source and properties"
  (let* ((token (scope:make-scope-token))
         (source (cons 1 5))
         (props '((key . value)))
         (stx (stx:make-syntax-object 'foo :source source :properties props))
         (result (stx:stx-add-scope stx token)))
    (is (equal source (stx:syntax-object-source result)))
    (is (equal props (stx:syntax-object-properties result)))))

(deftest stx-remove-scope-removes ()
  "stx-remove-scope removes scope from syntax"
  (let* ((token (scope:make-scope-token))
         (scopes (scope:scope-set-add (scope:empty-scope-set) token))
         (stx (stx:make-syntax-object 'foo :scopes scopes))
         (result (stx:stx-remove-scope stx token)))
    (is (not (scope:scope-set-member-p (stx:syntax-object-scopes result) token)))))

(deftest stx-remove-scope-recursive ()
  "stx-remove-scope removes scope recursively"
  (let* ((token (scope:make-scope-token))
         (scopes (scope:scope-set-add (scope:empty-scope-set) token))
         (a (stx:make-identifier-syntax 'a :scopes scopes))
         (b (stx:make-identifier-syntax 'b :scopes scopes))
         (list-stx (stx:make-list-syntax (list a b) :scopes scopes))
         (result (stx:stx-remove-scope list-stx token)))
    ;; List has scope removed
    (is (not (scope:scope-set-member-p (stx:syntax-object-scopes result) token)))
    ;; Elements have scope removed
    (dolist (elem (stx:syntax-e result))
      (is (not (scope:scope-set-member-p (stx:syntax-object-scopes elem) token))))))

(deftest stx-flip-scope-adds-when-absent ()
  "stx-flip-scope adds scope when absent"
  (let* ((token (scope:make-scope-token))
         (stx (stx:make-identifier-syntax 'foo))
         (result (stx:stx-flip-scope stx token)))
    (is (scope:scope-set-member-p (stx:syntax-object-scopes result) token))))

(deftest stx-flip-scope-removes-when-present ()
  "stx-flip-scope removes scope when present"
  (let* ((token (scope:make-scope-token))
         (scopes (scope:scope-set-add (scope:empty-scope-set) token))
         (stx (stx:make-syntax-object 'foo :scopes scopes))
         (result (stx:stx-flip-scope stx token)))
    (is (not (scope:scope-set-member-p (stx:syntax-object-scopes result) token)))))

(deftest stx-flip-scope-recursive ()
  "stx-flip-scope flips scope recursively"
  (let* ((token (scope:make-scope-token))
         (a (stx:make-identifier-syntax 'a))
         (b (stx:make-identifier-syntax 'b))
         (inner (stx:make-list-syntax (list a b)))
         (outer (stx:make-list-syntax (list inner)))
         (result (stx:stx-flip-scope outer token)))
    ;; All levels should have the scope added
    (is (scope:scope-set-member-p (stx:syntax-object-scopes result) token))
    (let ((inner-result (first (stx:syntax-e result))))
      (is (scope:scope-set-member-p (stx:syntax-object-scopes inner-result) token))
      (dolist (elem (stx:syntax-e inner-result))
        (is (scope:scope-set-member-p (stx:syntax-object-scopes elem) token))))))

(deftest stx-flip-scope-hygiene-example ()
  "Demonstrates hygiene: add then flip restores original scopes"
  ;; Simulate what happens to input syntax during expansion:
  ;; 1. Use-scope added
  ;; 2. Use-scope flipped (removes it)
  (let* ((use-scope (scope:make-scope-token))
         (original (stx:make-identifier-syntax 'x))
         (with-use (stx:stx-add-scope original use-scope))
         (after-flip (stx:stx-flip-scope with-use use-scope)))
    (is (scope:scope-set-equal
         (stx:syntax-object-scopes original)
         (stx:syntax-object-scopes after-flip)))))

;;;
;;; Property Tests
;;;

(deftest stx-property-retrieves ()
  "stx-property retrieves property values"
  (let* ((props '((key1 . val1) (key2 . val2)))
         (stx (stx:make-syntax-object 'foo :properties props)))
    (is (eq 'val1 (stx:stx-property stx 'key1)))
    (is (eq 'val2 (stx:stx-property stx 'key2)))))

(deftest stx-property-default ()
  "stx-property returns default for missing key"
  (let ((stx (stx:make-syntax-object 'foo)))
    (is (null (stx:stx-property stx 'missing)))
    (is (eq 'default (stx:stx-property stx 'missing 'default)))))

(deftest stx-with-property-adds ()
  "stx-with-property adds new property"
  (let* ((stx (stx:make-syntax-object 'foo))
         (result (stx:stx-with-property stx 'key 'value)))
    (is (eq 'value (stx:stx-property result 'key)))
    ;; Original unchanged
    (is (null (stx:stx-property stx 'key)))))

(deftest stx-with-property-replaces ()
  "stx-with-property replaces existing property"
  (let* ((stx (stx:make-syntax-object 'foo :properties '((key . old))))
         (result (stx:stx-with-property stx 'key 'new)))
    (is (eq 'new (stx:stx-property result 'key)))))

(deftest stx-with-property-preserves-other-properties ()
  "stx-with-property preserves other properties"
  (let* ((stx (stx:make-syntax-object 'foo :properties '((other . val))))
         (result (stx:stx-with-property stx 'key 'value)))
    (is (eq 'val (stx:stx-property result 'other)))
    (is (eq 'value (stx:stx-property result 'key)))))

;;;
;;; Identifier Predicate Tests
;;;

(deftest identifier?-symbol ()
  "identifier? returns T for regular symbols"
  (let ((stx (stx:make-identifier-syntax 'foo)))
    (is (stx:identifier? stx))))

(deftest identifier?-excludes-keywords ()
  "identifier? returns NIL for keywords"
  (let ((stx (stx:make-syntax-object :keyword)))
    (is (not (stx:identifier? stx)))))

(deftest identifier?-excludes-booleans ()
  "identifier? returns NIL for t and nil"
  (let ((true-stx (stx:make-syntax-object t))
        (nil-stx (stx:make-syntax-object nil)))
    (is (not (stx:identifier? true-stx)))
    (is (not (stx:identifier? nil-stx)))))

(deftest identifier?-excludes-non-symbols ()
  "identifier? returns NIL for non-symbols"
  (let ((num-stx (stx:make-atom-syntax 42))
        (str-stx (stx:make-atom-syntax "hello"))
        (list-stx (stx:make-list-syntax (list (stx:make-identifier-syntax 'a)))))
    (is (not (stx:identifier? num-stx)))
    (is (not (stx:identifier? str-stx)))
    (is (not (stx:identifier? list-stx)))))

(deftest identifier-symbol-extracts ()
  "identifier-symbol extracts the symbol from an identifier"
  (let ((stx (stx:make-identifier-syntax 'my-var)))
    (is (eq 'my-var (stx:identifier-symbol stx)))))

(deftest identifier-symbol-errors-on-non-identifier ()
  "identifier-symbol signals error for non-identifiers"
  (let ((num-stx (stx:make-atom-syntax 42)))
    (signals error (stx:identifier-symbol num-stx))))

;;;
;;; Identifier Comparison Tests (Phase 1 of Racket Parity)
;;;

(deftest free-identifier=?-same-symbol-same-scopes ()
  "free-identifier=? returns T for same symbol and same scopes"
  (let* ((scope1 (scope:make-scope-token))
         (scopes (scope:scope-set-add (scope:empty-scope-set) scope1))
         (id1 (stx:make-identifier-syntax 'x :scopes scopes))
         (id2 (stx:make-identifier-syntax 'x :scopes scopes)))
    (is (stx:free-identifier=? id1 id2))))

(deftest free-identifier=?-same-symbol-different-scopes ()
  "free-identifier=? returns NIL for same symbol but different scopes"
  (let* ((scope1 (scope:make-scope-token))
         (scope2 (scope:make-scope-token))
         (scopes1 (scope:scope-set-add (scope:empty-scope-set) scope1))
         (scopes2 (scope:scope-set-add (scope:empty-scope-set) scope2))
         (id1 (stx:make-identifier-syntax 'x :scopes scopes1))
         (id2 (stx:make-identifier-syntax 'x :scopes scopes2)))
    (is (not (stx:free-identifier=? id1 id2)))))

(deftest free-identifier=?-different-symbol-same-scopes ()
  "free-identifier=? returns NIL for different symbols"
  (let* ((scope1 (scope:make-scope-token))
         (scopes (scope:scope-set-add (scope:empty-scope-set) scope1))
         (id1 (stx:make-identifier-syntax 'x :scopes scopes))
         (id2 (stx:make-identifier-syntax 'y :scopes scopes)))
    (is (not (stx:free-identifier=? id1 id2)))))

(deftest free-identifier=?-empty-scopes ()
  "free-identifier=? works with empty scopes"
  (let ((id1 (stx:make-identifier-syntax 'x))
        (id2 (stx:make-identifier-syntax 'x)))
    (is (stx:free-identifier=? id1 id2))))

(deftest free-identifier=?-multiple-scopes ()
  "free-identifier=? compares full scope sets"
  (let* ((s1 (scope:make-scope-token))
         (s2 (scope:make-scope-token))
         (scopes-both (scope:scope-set-add
                       (scope:scope-set-add (scope:empty-scope-set) s1)
                       s2))
         (scopes-one (scope:scope-set-add (scope:empty-scope-set) s1))
         (id1 (stx:make-identifier-syntax 'x :scopes scopes-both))
         (id2 (stx:make-identifier-syntax 'x :scopes scopes-both))
         (id3 (stx:make-identifier-syntax 'x :scopes scopes-one)))
    (is (stx:free-identifier=? id1 id2))
    (is (not (stx:free-identifier=? id1 id3)))))

(deftest free-identifier=?-non-identifiers ()
  "free-identifier=? returns NIL for non-identifiers"
  (let ((num (stx:make-atom-syntax 42))
        (id (stx:make-identifier-syntax 'x)))
    (is (not (stx:free-identifier=? num id)))
    (is (not (stx:free-identifier=? id num)))))

(deftest bound-identifier=?-same-as-free ()
  "bound-identifier=? returns same result as free-identifier=?"
  (let* ((s1 (scope:make-scope-token))
         (s2 (scope:make-scope-token))
         (scopes1 (scope:scope-set-add (scope:empty-scope-set) s1))
         (scopes2 (scope:scope-set-add (scope:empty-scope-set) s2))
         (id1 (stx:make-identifier-syntax 'x :scopes scopes1))
         (id2 (stx:make-identifier-syntax 'x :scopes scopes1))
         (id3 (stx:make-identifier-syntax 'x :scopes scopes2)))
    ;; Same scopes -> both return T
    (is (stx:bound-identifier=? id1 id2))
    (is (stx:free-identifier=? id1 id2))
    ;; Different scopes -> both return NIL
    (is (not (stx:bound-identifier=? id1 id3)))
    (is (not (stx:free-identifier=? id1 id3)))))

(deftest free-identifier=?-hygiene-scenario ()
  "Demonstrates hygiene: identifiers before/after macro expansion differ"
  ;; Simulate: macro expansion adds then flips a scope
  (let* ((use-scope (scope:make-scope-token))
         (intro-scope (scope:make-scope-token))
         ;; User's identifier with no scopes
         (user-id (stx:make-identifier-syntax 'x))
         ;; After macro adds use-scope and flips intro-scope on passed-through id
         (passed-through (stx:stx-flip-scope
                          (stx:stx-add-scope user-id use-scope)
                          use-scope))
         ;; Macro introduces a new 'x - gets intro scope flipped on
         (introduced (stx:stx-flip-scope
                      (stx:make-identifier-syntax 'x)
                      intro-scope)))
    ;; Passed-through returns to original scopes
    (is (stx:free-identifier=? user-id passed-through))
    ;; Introduced has different scopes (intro-scope)
    (is (not (stx:free-identifier=? user-id introduced)))
    ;; They have the same symbol but different scope sets
    (is (eq (stx:identifier-symbol user-id)
            (stx:identifier-symbol introduced)))))
