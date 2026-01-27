# Coalton Syntax Objects: Implementation Status and Roadmap

This document describes the implementation of Racket-style hygienic macros in Coalton using the "sets of scopes" algorithm from [Flatt (POPL 2016)](https://www.cs.utah.edu/plt/publications/popl16-f.pdf).

## Overview

The syntax objects system enables hygienic macro expansion where macro-introduced bindings don't accidentally capture user code, while still allowing intentional capture patterns (like anaphoric macros).

**Current Status:** 258 tests passing across 8 test files.

## Implementation Status

| Phase | Feature | Status | Tests |
|-------|---------|--------|-------|
| 1 | Identifier Comparison | Complete | 14 |
| 2 | Intentional Capture | Complete | 14 |
| 3 | Local Expansion Control | Complete | 16 |
| 4 | Definition Contexts | Complete | 19 |
| 5 | Syntax Patterns | Complete | 27 |
| 6 | Advanced Features | Complete | 22 |

## Architecture

```
src/parser/
├── scope.lisp              # Scope tokens and scope sets (FSet-based)
├── syntax-object.lisp      # Core syntax objects with datum/scopes/source/properties
├── binding-table.lisp      # Binding resolution with maximal subset rule
├── definition-context.lisp # Definition contexts for toplevel hygiene
├── syntax-cst.lisp         # CST ↔ syntax object conversion
├── macro.lisp              # Hygienic expansion, local-expand, syntax-local-introduce
└── syntax-case.lisp        # Pattern matching (syntax-case, with-syntax, syntax templates)

tests/parser/
├── scope-tests.lisp                # 29 tests
├── syntax-object-tests.lisp        # 43 tests
├── binding-table-tests.lisp        # 31 tests
├── definition-context-tests.lisp   # 19 tests
├── syntax-cst-tests.lisp           # 41 tests
├── hygienic-macro-tests.lisp       # 72 tests
├── hygienic-integration-tests.lisp # 16 tests
└── syntax-case-tests.lisp          # 27 tests
```

---

## Completed Phases

### Phase 1: Identifier Comparison Primitives

**Purpose:** Enable macros to compare identifiers while respecting hygiene.

**Key Functions:**
- `identifier?` - Predicate for symbol-wrapping syntax objects
- `identifier-symbol` - Extract symbol from identifier
- `free-identifier=?` - Do two identifiers refer to the same binding?
- `bound-identifier=?` - Would two identifiers create the same binding?

**Core Test Cases:**

```lisp
;; free-identifier=? respects scopes
(deftest free-identifier=?-same-symbol-different-scopes ()
  "Same symbol with different scopes are NOT free-identifier=?"
  (let* ((scope1 (scope:make-scope-token))
         (scope2 (scope:make-scope-token))
         (id1 (stx:make-identifier-syntax 'x
                :scopes (scope:scope-set-add (scope:empty-scope-set) scope1)))
         (id2 (stx:make-identifier-syntax 'x
                :scopes (scope:scope-set-add (scope:empty-scope-set) scope2))))
    (is (not (stx:free-identifier=? id1 id2)))))

;; Hygiene scenario: macro-introduced vs user identifiers
(deftest free-identifier=?-hygiene-scenario ()
  "Macro-introduced identifier differs from user identifier"
  (let* ((use-scope (scope:make-scope-token))
         (intro-scope (scope:make-scope-token))
         ;; User 'x' has use-scope
         (user-x (stx:make-identifier-syntax 'x
                   :scopes (scope:scope-set-add (scope:empty-scope-set) use-scope)))
         ;; Macro-introduced 'x' has intro-scope
         (macro-x (stx:make-identifier-syntax 'x
                    :scopes (scope:scope-set-add (scope:empty-scope-set) intro-scope))))
    (is (not (stx:free-identifier=? user-x macro-x)))))
```

---

### Phase 2: Intentional Capture (syntax-local-introduce)

**Purpose:** Allow macros to intentionally break hygiene for patterns like anaphoric `aif`.

**Key Functions:**
- `expansion-context` - Struct holding use-scope and intro-scope
- `*current-expansion-context*` - Dynamic variable during expansion
- `syntax-local-introduce` - Flip intro scope to break hygiene
- `make-syntax-introducer` - Create custom introducer functions
- `expand-macro-hygienic/ctx` - Expansion that binds context

**Core Test Cases:**

```lisp
;; syntax-local-introduce flips the intro scope
(deftest syntax-local-introduce-flips-intro-scope ()
  "syntax-local-introduce flips the intro scope on syntax"
  (let* ((use-scope (scope:make-scope-token))
         (intro-scope (scope:make-scope-token))
         (ctx (macro:make-expansion-context use-scope intro-scope))
         (stx (stx:make-identifier-syntax 'x)))
    (let ((macro:*current-expansion-context* ctx))
      (let ((result (macro:syntax-local-introduce stx)))
        ;; Should have intro-scope flipped (added, since it wasn't there)
        (is (scope:scope-set-member-p (stx:syntax-object-scopes result) intro-scope))))))

;; Anaphoric aif simulation
(deftest anaphoric-aif-simulation ()
  "Simulate anaphoric if pattern with syntax-local-introduce"
  (let* ((use-scope (scope:make-scope-token))
         (intro-scope (scope:make-scope-token))
         (ctx (macro:make-expansion-context use-scope intro-scope)))
    (let ((macro:*current-expansion-context* ctx))
      ;; Create 'it' using syntax-local-introduce to make it visible
      (let ((it-id (macro:syntax-local-introduce
                    (stx:make-identifier-syntax 'it))))
        ;; The 'it' identifier should be usable by macro user
        ;; because it has the intro-scope flipped (making it match user code)
        (is (stx:identifier? it-id))
        (is (eq 'it (stx:identifier-symbol it-id)))))))
```

---

### Phase 3: Local Expansion Control

**Purpose:** Enable macros to partially expand code, stopping at specified forms.

**Key Functions:**
- `local-expand` - Expand macros with stop list support
- `syntax-local-value` - Get compile-time value of identifier
- `define-compile-time-value` - Register custom compile-time bindings

**Core Test Cases:**

```lisp
;; local-expand with stop list
(deftest local-expand-with-stop-list ()
  "local-expand stops at specified forms"
  (eval '(defmacro test-outer (&body body)
           `(progn :outer-expanded ,@body)))
  (eval '(defmacro test-inner (&body body)
           `(progn :inner-expanded ,@body)))
  (let* ((ctx (stx:make-syntax-object 'ctx))
         (stx (stx:datum->syntax ctx
                '(coalton-impl/parser/hygienic-macro-tests::test-outer
                  (coalton-impl/parser/hygienic-macro-tests::test-inner x))))
         (expanded (macro:local-expand stx
                     '(coalton-impl/parser/hygienic-macro-tests::test-inner))))
    (let ((datum (stx:syntax->datum expanded)))
      (is (eq 'progn (first datum)))
      (is (eq :outer-expanded (second datum)))
      ;; (test-inner x) remains unexpanded
      (let ((inner-form (find-if (lambda (elem)
                                   (and (listp elem)
                                        (eq 'coalton-impl/parser/hygienic-macro-tests::test-inner
                                            (first elem))))
                                 datum)))
        (is (not (null inner-form)))))))

;; syntax-local-value retrieves compile-time bindings
(deftest syntax-local-value-finds-macro ()
  "syntax-local-value finds macro-function bindings"
  (let* ((id (stx:make-identifier-syntax 'when)))
    (is (functionp (macro:syntax-local-value id)))))

;; Custom compile-time bindings
(deftest syntax-local-value-custom-binding ()
  "syntax-local-value finds custom compile-time bindings"
  (macro:define-compile-time-value 'my-test-binding :test-value)
  (let* ((id (stx:make-identifier-syntax 'my-test-binding)))
    (is (eq :test-value (macro:syntax-local-value id))))
  (remhash 'my-test-binding macro:*compile-time-bindings*))
```

---

### Phase 5: Syntax Patterns and Templates

**Purpose:** Provide declarative pattern matching for macro definitions.

**Key Functions:**
- `syntax-case` - Pattern matching macro with clause dispatch
- `with-syntax` - Bind pattern variables for templates
- `syntax` - Template construction with hygiene
- `syntax-match` - Core pattern matching with ellipsis
- `expand-template` - Template expansion with variable substitution

**Core Test Cases:**

```lisp
;; syntax-case basic pattern matching
(deftest syntax-case-basic-match ()
  "syntax-case matches basic patterns"
  (let* ((ctx (stx:make-syntax-object 'ctx))
         (stx (stx:datum->syntax ctx '(foo 1 2 3))))
    (is (equal '(1 2 3)
               (syntax-case:syntax-case stx ()
                 ((_ a b c) (list (stx:syntax->datum a)
                                  (stx:syntax->datum b)
                                  (stx:syntax->datum c))))))))

;; Ellipsis pattern matching
(deftest syntax-match-ellipsis-multiple ()
  "syntax-match handles ellipsis with multiple elements"
  (let* ((ctx (stx:make-syntax-object 'ctx))
         (stx (stx:datum->syntax ctx '(a b c))))
    (multiple-value-bind (match bindings)
        (syntax-case:syntax-match stx '(x ...) nil)
      (is match)
      (let ((x-vals (cdr (assoc 'x bindings))))
        (is (= 3 (length x-vals)))))))

;; Template expansion with ellipsis
(deftest template-expands-ellipsis ()
  "expand-template handles ellipsis repetition"
  (let* ((ctx (stx:make-syntax-object 'ctx))
         (bindings `((x . (,(stx:datum->syntax ctx 'a)
                           ,(stx:datum->syntax ctx 'b)
                           ,(stx:datum->syntax ctx 'c))))))
    (let ((result (syntax-case:expand-template '(list x ...) bindings ctx)))
      (is (stx:syntax-object-p result))
      (is (equal '(list a b c) (stx:syntax->datum result))))))

;; with-syntax binds pattern variables
(deftest with-syntax-binds-pattern-vars ()
  "with-syntax binds pattern variables for use in body"
  (let* ((ctx (stx:make-syntax-object 'ctx))
         (stx (stx:datum->syntax ctx '(1 2 3))))
    (is (equal '(1 2 3)
               (syntax-case:with-syntax (((a b c) stx))
                 (list (stx:syntax->datum a)
                       (stx:syntax->datum b)
                       (stx:syntax->datum c)))))))
```

---

## Pending Phases

### Phase 4: Definition Contexts

**Purpose:** Handle hygiene in interleaved definitions where later definitions might shadow names referenced by earlier macros.

**Key Concepts:**
- Inside-edge and outside-edge scopes for definition blocks
- `syntax-local-make-definition-context` for creating nested definition contexts
- Proper binding timing to prevent hygiene violations

**Why It Matters:** Without definition contexts, code like this can break:

```lisp
(coalton-toplevel
  (define helper (fn (x) (+ x 1)))
  (define-macro use-helper (stx)
    `(helper ,(stx-second stx)))
  (define helper (fn (x) (* x 2)))  ; shadows!
  (define result (use-helper 5)))
;; Should be 6 (+ 5 1), not 10 (* 5 2)
```

**Proposed Test Cases:**

```lisp
;; Definition context creation
(deftest definition-context-creation ()
  "syntax-local-make-definition-context creates valid context"
  (let ((ctx (syntax-local-make-definition-context)))
    (is (definition-context-p ctx))
    (is (scope:scope-token-p (definition-context-inside-scope ctx)))
    (is (scope:scope-token-p (definition-context-outside-scope ctx)))))

;; Inside/outside edge scopes differ
(deftest definition-context-scopes-differ ()
  "Inside and outside scopes are distinct"
  (let ((ctx (syntax-local-make-definition-context)))
    (is (not (eq (definition-context-inside-scope ctx)
                 (definition-context-outside-scope ctx))))))

;; Hygiene preserved across interleaved definitions
(deftest definition-context-hygiene ()
  "Later definitions don't capture earlier macro references"
  ;; This test requires integration with toplevel processing
  ;; to properly track definition order and binding scopes
  ...)

;; Nested definition contexts
(deftest nested-definition-contexts ()
  "Definition contexts can be nested"
  (let* ((outer (syntax-local-make-definition-context))
         (inner (syntax-local-make-definition-context outer)))
    (is (definition-context-p inner))
    (is (eq outer (definition-context-parent inner)))))
```

**Implementation Outline:**

```lisp
(defstruct definition-context
  "Context for a block of interleaved definitions."
  (inside-scope (make-scope-token) :type scope-token)
  (outside-scope (make-scope-token) :type scope-token)
  (parent nil :type (or null definition-context))
  (bindings nil :type list))

(defun syntax-local-make-definition-context (&optional parent)
  "Create a new definition context, optionally nested in PARENT.")

(defun definition-context-bind (ctx id binding)
  "Add a binding to the definition context CTX.")

(defun definition-context-lookup (ctx id)
  "Look up ID in CTX and its parents.")
```

**Files to Modify:**
- New: `src/parser/definition-context.lisp`
- Modify: `src/parser/toplevel.lisp` (integrate with definition processing)
- Modify: `coalton-compiler.asd` (add new file)

---

### Phase 6: Advanced Features and Debugging

**Purpose:** Production polish with better error messages, debugging tools, and identifier aliasing.

**Key Features:**
- `syntax-track-origin` - Propagate macro origin for error messages
- `syntax-debug-info` - Introspection for debugging hygiene issues
- `make-rename-transformer` - Create identifier aliases
- Property propagation through expansion

**Proposed Test Cases:**

```lisp
;; syntax-track-origin
(deftest syntax-track-origin-sets-property ()
  "syntax-track-origin sets origin property"
  (let* ((original (stx:make-identifier-syntax 'my-macro))
         (expanded (stx:make-identifier-syntax 'result))
         (tracked (syntax-track-origin expanded original)))
    (is (eq original (stx:stx-property tracked 'origin)))))

(deftest syntax-track-origin-propagates ()
  "Origin is propagated through nested expansion"
  (let* ((original (stx:make-list-syntax
                    (list (stx:make-identifier-syntax 'my-macro)
                          (stx:make-atom-syntax 1))))
         (expanded (expand-tracking-origin original some-transformer)))
    (let ((origin (stx:stx-property expanded 'origin)))
      (is (not (null origin)))
      (is (eq 'my-macro (stx:syntax-e (first (stx:syntax-e origin))))))))

;; syntax-debug-info
(deftest syntax-debug-info-shows-scopes ()
  "syntax-debug-info displays scope information"
  (let* ((scope1 (scope:make-scope-token))
         (scope2 (scope:make-scope-token))
         (stx (stx:make-identifier-syntax 'x
                :scopes (scope:scope-set-add
                         (scope:scope-set-add (scope:empty-scope-set) scope1)
                         scope2))))
    (let ((info (syntax-debug-info stx)))
      (is (stringp info))
      (is (search "scope" info :test #'char-equal)))))

;; make-rename-transformer
(deftest make-rename-transformer-creates-alias ()
  "make-rename-transformer creates working alias"
  (let* ((target-id (stx:make-identifier-syntax 'original-name))
         (transformer (make-rename-transformer target-id)))
    (is (functionp transformer))))

(deftest rename-transformer-expands-to-target ()
  "Rename transformer expands alias to target"
  (let* ((target-id (stx:make-identifier-syntax 'original-name))
         (transformer (make-rename-transformer target-id))
         (alias-use (stx:make-list-syntax
                     (list (stx:make-identifier-syntax 'my-alias)
                           (stx:make-atom-syntax 1)))))
    (let ((expanded (funcall transformer alias-use)))
      ;; Should expand to (original-name 1)
      (is (eq 'original-name
              (stx:syntax-e (first (stx:syntax-e expanded))))))))

;; Property propagation
(deftest properties-propagate-through-expansion ()
  "Properties are maintained through macro expansion"
  (let* ((stx (stx:stx-with-property
               (stx:make-list-syntax
                (list (stx:make-identifier-syntax 'progn)
                      (stx:make-atom-syntax 1)))
               'source-macro 'my-macro))
         (expanded (macro:local-expand stx)))
    ;; Properties should be preserved or propagated
    (is (or (stx:stx-property expanded 'source-macro)
            (stx:stx-property expanded 'origin)))))
```

**Implementation Outline:**

```lisp
(defun syntax-track-origin (result-stx origin-stx)
  "Attach ORIGIN-STX as the origin of RESULT-STX.

   This is used to track where macro-expanded code came from,
   enabling better error messages that point to the macro use site."
  (stx:stx-with-property result-stx 'origin origin-stx))

(defun syntax-debug-info (stx &optional (stream nil))
  "Return a string describing STX's hygiene information.

   Useful for debugging macro hygiene issues. Shows:
   - The datum
   - All scopes and their IDs
   - Source location if available
   - Properties"
  ...)

(defun make-rename-transformer (target-id)
  "Create a transformer that redirects uses of an identifier to TARGET-ID.

   This is useful for creating aliases and for implementing certain
   forms of identifier macros."
  (lambda (stx)
    (let ((args (rest (stx:syntax-e stx))))
      (stx:make-list-syntax (cons target-id args)
        :scopes (stx:syntax-object-scopes stx)
        :source (stx:syntax-object-source stx)))))
```

**Files to Modify:**
- `src/parser/macro.lisp` (add syntax-track-origin, syntax-debug-info)
- `src/parser/syntax-object.lisp` (add make-rename-transformer)
- `tests/parser/hygienic-macro-tests.lisp` (add tests)

---

## Features Explicitly Deferred

| Feature | Reason |
|---------|--------|
| Module system scopes | Coalton uses CL packages; separate module scopes would duplicate |
| Phase tower (for-syntax) | CL's `eval-when` handles compile-time distinction |
| Tamper status | Security feature for compiled modules; not applicable to CL embedding |
| `syntax-rules` | `syntax-case` provides equivalent functionality with more flexibility |

---

## Running Tests

### Quick Test (Summary Output)

```bash
qlot exec sbcl --noinform --non-interactive --load scripts/run-parser-tests.lisp
```

### Verbose Test Output

```bash
qlot exec sbcl --noinform --non-interactive \
  --eval "(require :asdf)" \
  --eval "(asdf:load-system :fiasco :verbose nil)" \
  --eval "(asdf:load-system :coalton :verbose nil)" \
  --eval "(load \"tests/parser/scope-tests.lisp\")" \
  --eval "(load \"tests/parser/syntax-object-tests.lisp\")" \
  --eval "(load \"tests/parser/binding-table-tests.lisp\")" \
  --eval "(load \"tests/parser/syntax-cst-tests.lisp\")" \
  --eval "(load \"tests/parser/hygienic-macro-tests.lisp\")" \
  --eval "(load \"tests/parser/hygienic-integration-tests.lisp\")" \
  --eval "(load \"tests/parser/syntax-case-tests.lisp\")" \
  --eval "(fiasco:run-tests '(coalton-impl/parser/scope-tests
                              coalton-impl/parser/syntax-object-tests
                              coalton-impl/parser/binding-table-tests
                              coalton-impl/parser/syntax-cst-tests
                              coalton-impl/parser/hygienic-macro-tests
                              coalton-impl/parser/hygienic-integration-tests
                              coalton/tests/parser/syntax-case-tests))"
```

### Test with Hygienic Mode Enabled

```lisp
(let ((coalton-impl/parser/macro:*use-hygienic-macros* t))
  (asdf:test-system "coalton/tests"))
```

---

## References

1. Flatt, Matthew. "Binding as Sets of Scopes." POPL 2016.
   https://www.cs.utah.edu/plt/publications/popl16-f.pdf

2. Racket Documentation: Syntax Model
   https://docs.racket-lang.org/reference/syntax-model.html

3. Racket Documentation: Syntax Objects
   https://docs.racket-lang.org/reference/stxobj.html
