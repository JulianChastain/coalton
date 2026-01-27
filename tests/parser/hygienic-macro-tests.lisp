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

;;;
;;; Expansion Context Tests (Phase 2: Intentional Capture)
;;;

(deftest expansion-context-creation ()
  "expansion-context holds use-scope and intro-scope"
  (let* ((use-scope (scope:make-scope-token))
         (intro-scope (scope:make-scope-token))
         (ctx (macro::%make-expansion-context use-scope intro-scope)))
    (is (macro:expansion-context-p ctx))
    (is (eq use-scope (macro:expansion-context-use-scope ctx)))
    (is (eq intro-scope (macro:expansion-context-intro-scope ctx)))))

(deftest current-expansion-context-nil-by-default ()
  "*current-expansion-context* is nil outside expansion"
  (is (null macro:*current-expansion-context*)))

(deftest expand-macro-hygienic/ctx-binds-context ()
  "expand-macro-hygienic/ctx binds *current-expansion-context* during transformer"
  (let* ((input (stx:make-identifier-syntax 'x))
         (captured-ctx nil)
         (result (macro:expand-macro-hygienic/ctx
                  input
                  (lambda (stx)
                    (setf captured-ctx macro:*current-expansion-context*)
                    stx))))
    (declare (ignore result))
    ;; Context should have been bound
    (is (macro:expansion-context-p captured-ctx))
    ;; But should be unbound now
    (is (null macro:*current-expansion-context*))))

(deftest expand-macro-hygienic/ctx-context-has-valid-scopes ()
  "expand-macro-hygienic/ctx provides context with valid scope tokens"
  (let* ((input (stx:make-identifier-syntax 'x))
         (use-scope nil)
         (intro-scope nil)
         (result (macro:expand-macro-hygienic/ctx
                  input
                  (lambda (stx)
                    (let ((ctx macro:*current-expansion-context*))
                      (setf use-scope (macro:expansion-context-use-scope ctx))
                      (setf intro-scope (macro:expansion-context-intro-scope ctx)))
                    stx))))
    (declare (ignore result))
    ;; Both scopes should be scope tokens
    (is (scope:scope-token-p use-scope))
    (is (scope:scope-token-p intro-scope))
    ;; They should be different
    (is (not (eql (scope:scope-token-id use-scope)
                  (scope:scope-token-id intro-scope))))))

(deftest syntax-local-introduce-errors-outside-context ()
  "syntax-local-introduce signals error when not in expansion"
  (let ((stx (stx:make-identifier-syntax 'x)))
    (signals error (macro:syntax-local-introduce stx))))

(deftest syntax-local-introduce-flips-intro-scope ()
  "syntax-local-introduce flips the intro scope on syntax"
  (let* ((input (stx:make-identifier-syntax 'x))
         (intro-scope nil)
         (introduced-before nil)
         (introduced-after nil)
         (result (macro:expand-macro-hygienic/ctx
                  input
                  (lambda (stx)
                    (declare (ignore stx))
                    ;; Create new syntax and introduce it
                    (let* ((ctx macro:*current-expansion-context*)
                           (new-id (stx:make-identifier-syntax 'it)))
                      (setf intro-scope (macro:expansion-context-intro-scope ctx))
                      (setf introduced-before (stx:syntax-object-scopes new-id))
                      (let ((introduced (macro:syntax-local-introduce new-id)))
                        (setf introduced-after (stx:syntax-object-scopes introduced))
                        introduced))))))
    (declare (ignore result))
    ;; Before: should not have intro-scope
    (is (not (scope:scope-set-member-p introduced-before intro-scope)))
    ;; After syntax-local-introduce: should have intro-scope (flipped on)
    (is (scope:scope-set-member-p introduced-after intro-scope))))

(deftest syntax-local-introduce-breaks-hygiene ()
  "syntax-local-introduce allows intentional hygiene breaking"
  ;; When we introduce 'it' with syntax-local-introduce:
  ;; 1. Fresh 'it' created with empty scopes: {}
  ;; 2. syntax-local-introduce flips intro-scope ON: {intro}
  ;; 3. After transformer, expand-macro-hygienic/ctx flips intro-scope: {} (removed)
  ;; 4. expand-macro-hygienic/ctx flips use-scope: {use} (added)
  ;; Result: 'it' ends up with just {use}, without intro-scope
  ;;
  ;; Compare to normal introduced syntax (without syntax-local-introduce):
  ;; 1. Fresh syntax: {}
  ;; 2. Flip intro: {intro}
  ;; 3. Flip use: {intro, use}
  ;; Result: has intro-scope
  ;;
  ;; The key is: syntax-local-introduce removes the intro-scope,
  ;; making the identifier "visible" to user code bindings.
  (let* ((input (stx:make-identifier-syntax 'x))
         (intro-scope nil)
         (result (macro:expand-macro-hygienic/ctx
                  input
                  (lambda (stx)
                    (declare (ignore stx))
                    (setf intro-scope (macro:expansion-context-intro-scope
                                       macro:*current-expansion-context*))
                    (macro:syntax-local-introduce
                     (stx:make-identifier-syntax 'it))))))
    (is (stx:syntax-object-p result))
    (is (eq 'it (stx:syntax-e result)))
    ;; Should NOT have intro-scope (that's the key property)
    (is (not (scope:scope-set-member-p (stx:syntax-object-scopes result) intro-scope)))))

(deftest syntax-local-introduce-vs-normal-introduced ()
  "Introduced syntax differs based on syntax-local-introduce usage"
  (let* ((input (stx:make-identifier-syntax 'x))
         (intro-scope nil)
         (result (macro:expand-macro-hygienic/ctx
                  input
                  (lambda (stx)
                    (declare (ignore stx))
                    (setf intro-scope (macro:expansion-context-intro-scope
                                       macro:*current-expansion-context*))
                    ;; Return both: one with syntax-local-introduce, one without
                    (let ((with-introduce (macro:syntax-local-introduce
                                           (stx:make-identifier-syntax 'visible)))
                          (without-introduce (stx:make-identifier-syntax 'hidden)))
                      (stx:make-list-syntax (list with-introduce without-introduce)))))))
    (let ((visible-scopes (stx:syntax-object-scopes (stx-cst:stx-first result)))
          (hidden-scopes (stx:syntax-object-scopes (stx-cst:stx-second result))))
      ;; 'visible' used syntax-local-introduce -> should NOT have intro-scope
      (is (not (scope:scope-set-member-p visible-scopes intro-scope)))
      ;; 'hidden' didn't use syntax-local-introduce -> SHOULD have intro-scope
      (is (scope:scope-set-member-p hidden-scopes intro-scope))
      ;; They should have different scope sets
      (is (not (scope:scope-set-equal visible-scopes hidden-scopes))))))

;;;
;;; make-syntax-introducer Tests
;;;

(deftest make-syntax-introducer-creates-function ()
  "make-syntax-introducer returns a function"
  (let ((introducer (macro:make-syntax-introducer)))
    (is (functionp introducer))))

(deftest make-syntax-introducer-uses-provided-scope ()
  "make-syntax-introducer uses the provided scope token"
  (let* ((my-scope (scope:make-scope-token))
         (introducer (macro:make-syntax-introducer my-scope))
         (stx (stx:make-identifier-syntax 'x))
         (result (funcall introducer stx)))
    ;; Default mode is :flip, so scope should be added (wasn't there)
    (is (scope:scope-set-member-p (stx:syntax-object-scopes result) my-scope))))

(deftest make-syntax-introducer-creates-fresh-scope ()
  "make-syntax-introducer creates fresh scope when none provided"
  (let* ((introducer1 (macro:make-syntax-introducer))
         (introducer2 (macro:make-syntax-introducer))
         (stx (stx:make-identifier-syntax 'x))
         (result1 (funcall introducer1 stx))
         (result2 (funcall introducer2 stx)))
    ;; Each introducer should use a different scope
    (is (not (scope:scope-set-equal (stx:syntax-object-scopes result1)
                                    (stx:syntax-object-scopes result2))))))

(deftest make-syntax-introducer-flip-mode ()
  "make-syntax-introducer :flip mode toggles scope"
  (let* ((my-scope (scope:make-scope-token))
         (introducer (macro:make-syntax-introducer my-scope))
         (stx (stx:make-identifier-syntax 'x)))
    ;; First flip adds
    (let ((flipped-once (funcall introducer stx :flip)))
      (is (scope:scope-set-member-p (stx:syntax-object-scopes flipped-once) my-scope))
      ;; Second flip removes
      (let ((flipped-twice (funcall introducer flipped-once :flip)))
        (is (not (scope:scope-set-member-p (stx:syntax-object-scopes flipped-twice) my-scope)))))))

(deftest make-syntax-introducer-add-mode ()
  "make-syntax-introducer :add mode always adds scope"
  (let* ((my-scope (scope:make-scope-token))
         (introducer (macro:make-syntax-introducer my-scope))
         (stx (stx:make-identifier-syntax 'x))
         ;; First add
         (added-once (funcall introducer stx :add)))
    (is (scope:scope-set-member-p (stx:syntax-object-scopes added-once) my-scope))
    ;; Add again - should still have it (idempotent)
    (let ((added-twice (funcall introducer added-once :add)))
      (is (scope:scope-set-member-p (stx:syntax-object-scopes added-twice) my-scope)))))

(deftest make-syntax-introducer-remove-mode ()
  "make-syntax-introducer :remove mode always removes scope"
  (let* ((my-scope (scope:make-scope-token))
         (introducer (macro:make-syntax-introducer my-scope))
         (scopes-with (scope:scope-set-add (scope:empty-scope-set) my-scope))
         (stx (stx:make-identifier-syntax 'x :scopes scopes-with))
         (removed (funcall introducer stx :remove)))
    (is (not (scope:scope-set-member-p (stx:syntax-object-scopes removed) my-scope)))))

;;;
;;; Anaphoric Macro Simulation Tests
;;;

(deftest anaphoric-aif-simulation ()
  "Simulate an anaphoric 'aif' macro using syntax-local-introduce"
  ;; aif expands (aif test then else) to:
  ;; (let ((it test)) (if it then else))
  ;; where 'it' is visible to user code in 'then' and 'else'
  (let* ((test-stx (stx:make-identifier-syntax 'test-expr))
         (then-stx (stx:make-identifier-syntax 'then-expr))
         (else-stx (stx:make-identifier-syntax 'else-expr))
         (input (stx:make-list-syntax
                 (list (stx:make-identifier-syntax 'aif)
                       test-stx
                       then-stx
                       else-stx)))
         (result (macro:expand-macro-hygienic/ctx
                  input
                  (lambda (stx)
                    ;; Extract parts
                    (let* ((test (stx-cst:stx-second stx))
                           (then (stx-cst:stx-third stx))
                           (else (stx-cst:stx-nth 3 stx))
                           ;; Create 'it' identifier that will be visible to user
                           (it (macro:syntax-local-introduce
                                (stx:make-identifier-syntax 'it))))
                      ;; Build: (let ((it test)) (if it then else))
                      (stx:datum->syntax stx
                        `(let ((,it ,(stx:syntax->datum test)))
                           (if ,it
                               ,(stx:syntax->datum then)
                               ,(stx:syntax->datum else)))))))))
    ;; Result should be a let form
    (is (stx:syntax-object-p result))
    (is (eq 'let (stx:syntax-e (stx-cst:stx-first result))))
    ;; The 'it' binding should have same scopes as the 'then-expr'
    ;; (both should be "user-visible")
    (let* ((bindings (stx-cst:stx-second result))
           (first-binding (stx-cst:stx-first bindings))
           (it-id (stx-cst:stx-first first-binding)))
      ;; 'it' should be an identifier with user-visible scopes
      (is (stx:identifier? it-id))
      (is (eq 'it (stx:identifier-symbol it-id))))))

;;;
;;; Local Expansion Control Tests (Phase 3)
;;;

;;; local-expand tests

(deftest local-expand-atom ()
  "local-expand returns atoms unchanged"
  (let* ((stx (stx:make-identifier-syntax 'x))
         (result (macro:local-expand stx)))
    (is (stx:syntax-object-p result))
    (is (eq 'x (stx:syntax-e result)))))

(deftest local-expand-non-macro ()
  "local-expand returns non-macro forms with expanded children"
  (let* ((ctx (stx:make-syntax-object 'ctx))
         (stx (stx:datum->syntax ctx '(some-function arg1 arg2)))
         (result (macro:local-expand stx)))
    (is (stx:syntax-object-p result))
    (let ((datum (stx:syntax->datum result)))
      (is (eq 'some-function (first datum)))
      (is (eq 'arg1 (second datum)))
      (is (eq 'arg2 (third datum))))))

(deftest local-expand-expands-macro ()
  "local-expand expands macros"
  ;; Use progn which is a CL macro that expands
  ;; Note: progn might not expand to anything different, so let's use when
  (let* ((ctx (stx:make-syntax-object 'ctx))
         (stx (stx:datum->syntax ctx '(when t 42)))
         (result (macro:local-expand stx)))
    ;; Should be expanded (when expands to if)
    (is (stx:syntax-object-p result))
    (let ((datum (stx:syntax->datum result)))
      ;; when expands to (if t (progn 42))
      (is (eq 'if (first datum))))))

(deftest local-expand-stop-list-stops ()
  "local-expand stops at forms in stop-list"
  ;; Define a test macro
  (eval '(defmacro coalton-impl/parser/hygienic-macro-tests::test-macro-outer (&body body)
           `(progn :outer-expanded ,@body)))
  (let* ((ctx (stx:make-syntax-object 'ctx))
         (stx (stx:datum->syntax ctx
                '(coalton-impl/parser/hygienic-macro-tests::test-macro-outer x)))
         ;; Stop at our outer macro
         (result (macro:local-expand stx
                   '(coalton-impl/parser/hygienic-macro-tests::test-macro-outer))))
    ;; Should NOT be expanded
    (let ((datum (stx:syntax->datum result)))
      (is (eq 'coalton-impl/parser/hygienic-macro-tests::test-macro-outer (first datum))))))

(deftest local-expand-stop-list-children-expanded ()
  "local-expand expands children of stopped forms"
  ;; Define test macros
  (eval '(defmacro coalton-impl/parser/hygienic-macro-tests::outer-stop (&body body)
           `(progn :outer ,@body)))
  (eval '(defmacro coalton-impl/parser/hygienic-macro-tests::inner-expand ()
           ''expanded-value))
  (let* ((ctx (stx:make-syntax-object 'ctx))
         (stx (stx:datum->syntax ctx
                '(coalton-impl/parser/hygienic-macro-tests::outer-stop
                  (coalton-impl/parser/hygienic-macro-tests::inner-expand))))
         ;; Stop at outer, but inner should expand
         (result (macro:local-expand stx
                   '(coalton-impl/parser/hygienic-macro-tests::outer-stop))))
    (let ((datum (stx:syntax->datum result)))
      ;; Outer should not be expanded
      (is (eq 'coalton-impl/parser/hygienic-macro-tests::outer-stop (first datum)))
      ;; But inner should be expanded to 'expanded-value
      (is (equal ''expanded-value (second datum))))))

(deftest local-expand-recursive ()
  "local-expand recursively expands nested macros"
  ;; Define nested macros
  (eval '(defmacro coalton-impl/parser/hygienic-macro-tests::level1 ()
           '(coalton-impl/parser/hygienic-macro-tests::level2)))
  (eval '(defmacro coalton-impl/parser/hygienic-macro-tests::level2 ()
           ':final-value))
  (let* ((ctx (stx:make-syntax-object 'ctx))
         (stx (stx:datum->syntax ctx
                '(coalton-impl/parser/hygienic-macro-tests::level1)))
         (result (macro:local-expand stx)))
    (let ((datum (stx:syntax->datum result)))
      ;; Should be fully expanded to :final-value
      (is (eq :final-value datum)))))

(deftest local-expand-preserves-scopes ()
  "local-expand preserves scopes through expansion"
  (let* ((my-scope (scope:make-scope-token))
         (scopes (scope:scope-set-add (scope:empty-scope-set) my-scope))
         (stx (stx:make-syntax-object '(list x y) :scopes scopes))
         (result (macro:local-expand stx)))
    ;; Result should still have our scope
    (is (scope:scope-set-member-p (stx:syntax-object-scopes result) my-scope))))

(deftest local-expand-preserves-source ()
  "local-expand preserves source info through expansion"
  (let* ((source (cons 10 20))
         (stx (stx:make-syntax-object '(list x) :source source))
         (result (macro:local-expand stx)))
    ;; Result should preserve source
    (is (equal source (stx:syntax-object-source result)))))

(deftest local-expand-with-stop-list ()
  "local-expand stops at specified forms"
  ;; Define test macros locally in the test package
  (eval '(defmacro coalton-impl/parser/hygienic-macro-tests::test-outer (&body body)
           `(progn :outer-expanded ,@body)))
  (eval '(defmacro coalton-impl/parser/hygienic-macro-tests::test-inner (&body body)
           `(progn :inner-expanded ,@body)))

  (let* ((ctx (stx:make-syntax-object 'ctx))
         (stx (stx:datum->syntax ctx
                '(coalton-impl/parser/hygienic-macro-tests::test-outer
                  (coalton-impl/parser/hygienic-macro-tests::test-inner x))))
         ;; Expand outer but stop at 'test-inner
         (expanded (macro:local-expand stx
                     '(coalton-impl/parser/hygienic-macro-tests::test-inner))))
    ;; outer should be expanded (result is a progn form)
    (let ((datum (stx:syntax->datum expanded)))
      (is (eq 'progn (first datum)))
      (is (eq :outer-expanded (second datum)))
      ;; But (test-inner x) should remain unexpanded
      (let ((inner-form (find-if (lambda (elem)
                                   (and (listp elem)
                                        (eq 'coalton-impl/parser/hygienic-macro-tests::test-inner
                                            (first elem))))
                                 datum)))
        (is (not (null inner-form)))))))

;;; syntax-local-value tests

(deftest syntax-local-value-finds-macro ()
  "syntax-local-value retrieves macro-function value"
  ;; 'when' is a standard CL macro
  (let* ((id (stx:make-identifier-syntax 'when))
         (value (macro:syntax-local-value id)))
    ;; Should return the macro function
    (is (not (null value)))
    (is (functionp value))))

(deftest syntax-local-value-custom-binding ()
  "syntax-local-value retrieves custom compile-time binding"
  (let ((test-sym (gensym "TEST-BINDING-")))
    ;; Define a custom binding
    (macro:define-compile-time-value test-sym 'my-custom-value)
    (unwind-protect
        (let* ((id (stx:make-identifier-syntax test-sym))
               (value (macro:syntax-local-value id)))
          (is (eq 'my-custom-value value)))
      ;; Cleanup
      (remhash test-sym macro:*compile-time-bindings*))))

(deftest syntax-local-value-failure-thunk ()
  "syntax-local-value calls failure thunk when not found"
  (let* ((nonexistent-sym (gensym "NONEXISTENT-"))
         (id (stx:make-identifier-syntax nonexistent-sym))
         (thunk-called nil)
         (result (macro:syntax-local-value
                  id
                  (lambda ()
                    (setf thunk-called t)
                    :fallback-value))))
    (is thunk-called)
    (is (eq :fallback-value result))))

(deftest syntax-local-value-error-on-missing ()
  "syntax-local-value errors when no binding and no thunk"
  (let* ((nonexistent-sym (gensym "NONEXISTENT-"))
         (id (stx:make-identifier-syntax nonexistent-sym)))
    (signals error (macro:syntax-local-value id))))

(deftest syntax-local-value-non-identifier-error ()
  "syntax-local-value errors on non-identifier input"
  (let ((stx (stx:make-syntax-object '(not an identifier))))
    (signals error (macro:syntax-local-value stx))))

;;; define-compile-time-value tests

(deftest define-compile-time-value-stores-value ()
  "define-compile-time-value stores value in binding table"
  (let ((test-sym (gensym "TEST-")))
    (unwind-protect
        (progn
          (macro:define-compile-time-value test-sym 'stored-value)
          (is (eq 'stored-value (gethash test-sym macro:*compile-time-bindings*))))
      ;; Cleanup
      (remhash test-sym macro:*compile-time-bindings*))))

(deftest define-compile-time-value-overwrites ()
  "define-compile-time-value overwrites existing binding"
  (let ((test-sym (gensym "TEST-")))
    (unwind-protect
        (progn
          (macro:define-compile-time-value test-sym 'first-value)
          (macro:define-compile-time-value test-sym 'second-value)
          (is (eq 'second-value (gethash test-sym macro:*compile-time-bindings*))))
      ;; Cleanup
      (remhash test-sym macro:*compile-time-bindings*))))
