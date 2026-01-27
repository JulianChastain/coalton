# Scope System

The scope system provides the foundation for hygienic macro expansion. It implements scope tokens (unique identifiers for lexical scopes) and scope sets (immutable collections of tokens).

## Package

```lisp
(defpackage #:coalton-impl/parser/scope
  (:use #:cl)
  (:export
   ;; Scope tokens
   #:scope-token
   #:make-scope-token
   #:scope-token-id
   ;; Scope sets
   #:scope-set
   #:empty-scope-set
   #:scope-set-add
   #:scope-set-remove
   #:scope-set-flip
   #:scope-set-subset-p
   #:scope-set-empty-p
   #:scope-set-size
   #:scope-set-equal
   #:scope-set-union
   #:scope-set-intersection
   #:scope-set-member-p
   #:scope-set->list))
```

## Scope Tokens

A scope token is a unique identifier created at:

1. **Binding sites** - `let`, `fn`, `match`, `define`
2. **Macro expansion** - Use-site scope and intro scope

### API

```lisp
;; Create a fresh scope token
(make-scope-token) → scope-token

;; Access the unique ID
(scope-token-id token) → (integer 0)
```

### Implementation

```lisp
(defstruct (scope-token
            (:copier nil)
            (:constructor %make-scope-token (id)))
  (id (util:required 'id) :type (integer 0) :read-only t))

(defvar *next-scope-id* 0)

(defun make-scope-token ()
  (%make-scope-token (prog1 *next-scope-id*
                       (incf *next-scope-id*))))
```

Tokens are created with monotonically increasing IDs for uniqueness.

## Scope Sets

A scope set is an immutable collection of scope tokens, implemented using FSet for efficient persistent data structures.

### Core Operations

| Operation | Description |
|-----------|-------------|
| `empty-scope-set` | Create empty set |
| `scope-set-add` | Add token to set |
| `scope-set-remove` | Remove token from set |
| `scope-set-flip` | **Symmetric difference** - add if absent, remove if present |

### The Flip Operation

The flip operation is **crucial for hygiene**:

```lisp
(defun scope-set-flip (set token)
  "Add TOKEN if absent, remove if present."
  (let ((data (scope-set-data set)))
    (if (fset:contains? data token)
        (%make-scope-set (fset:less data token))
        (%make-scope-set (fset:with data token)))))
```

**Why flip matters:**

During macro expansion:
1. Use-site scope is **added** to all input syntax
2. Transformer runs, producing output
3. Intro scope is **flipped** on all output

For syntax that passed through from input:
- It has the use-site scope (added in step 1)
- Flip removes use-site scope → returns to original state

For syntax introduced by macro:
- It doesn't have use-site scope
- Flip adds intro scope → distinguished from user code

### Query Operations

```lisp
;; Check if set1 is subset of set2 (used in binding resolution)
(scope-set-subset-p set1 set2) → boolean

;; Check membership
(scope-set-member-p set token) → boolean

;; Set comparison
(scope-set-equal set1 set2) → boolean

;; Size queries
(scope-set-empty-p set) → boolean
(scope-set-size set) → integer
```

### Set Operations

```lisp
(scope-set-union set1 set2) → scope-set
(scope-set-intersection set1 set2) → scope-set
(scope-set->list set) → list
```

## Immutability

Scope sets are immutable - all operations return new sets. This is essential because:

1. Syntax objects may be shared across macro expansions
2. The binding table caches scope sets as keys
3. Backtracking during parsing shouldn't mutate scope state

## Example Usage

```lisp
(let* ((scope1 (make-scope-token))
       (scope2 (make-scope-token))
       (empty (empty-scope-set))
       (set1 (scope-set-add empty scope1))
       (set2 (scope-set-add set1 scope2)))

  ;; set2 contains both scope1 and scope2
  (scope-set-member-p set2 scope1)  ; → T
  (scope-set-member-p set2 scope2)  ; → T

  ;; Flip removes if present
  (scope-set-member-p (scope-set-flip set2 scope1) scope1)  ; → NIL

  ;; Flip adds if absent
  (let ((scope3 (make-scope-token)))
    (scope-set-member-p (scope-set-flip set2 scope3) scope3))  ; → T

  ;; Subset relationship (used in binding resolution)
  (scope-set-subset-p set1 set2)   ; → T (set1 ⊆ set2)
  (scope-set-subset-p set2 set1))  ; → NIL
```

## File Location

`src/parser/scope.lisp`
