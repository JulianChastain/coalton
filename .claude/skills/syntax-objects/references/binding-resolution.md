# Binding Resolution

The binding table maps identifiers to their bindings using scope sets. Resolution uses the **maximal subset rule** to find the most specific applicable binding.

## Package

```lisp
(defpackage #:coalton-impl/parser/binding-table
  (:use #:cl)
  (:nicknames #:bt)
  (:export
   ;; Binding table type
   #:binding-table
   #:make-binding-table
   #:binding-table-add
   #:binding-table-resolve
   #:binding-table-resolve-syntax
   ;; Scope binding type
   #:scope-binding
   #:make-scope-binding
   #:scope-binding-scopes
   #:scope-binding-value
   ;; Resolution result type
   #:resolution-result
   #:resolution-result-status
   #:resolution-result-binding
   #:resolution-result-candidates
   #:resolution-unbound-p
   #:resolution-bound-p
   #:resolution-ambiguous-p))
```

## Scope Binding

A scope binding associates a scope set with a value:

```lisp
(defstruct (scope-binding
            (:copier nil)
            (:constructor make-scope-binding (scopes value)))
  (scopes (scope:empty-scope-set) :type scope:scope-set :read-only t)
  (value nil :type t :read-only t))
```

The `value` can be anything - a variable name, a type, a macro transformer, etc.

## Binding Table

The binding table stores bindings indexed by symbol:

```lisp
(defstruct (binding-table
            (:copier nil)
            (:constructor %make-binding-table))
  (entries (make-hash-table :test #'eq) :type hash-table))

(defun make-binding-table ()
  (%make-binding-table))
```

Each symbol maps to a list of `scope-binding` objects with different scope sets.

### Adding Bindings

```lisp
(defun binding-table-add (table symbol scopes value)
  "Add a binding for SYMBOL with SCOPES to TABLE.
   Returns a new table (immutable)."
  (let ((new-table (copy-binding-table table))
        (binding (make-scope-binding scopes value)))
    (push binding (gethash symbol (binding-table-entries new-table)))
    new-table))
```

## The Maximal Subset Rule

When resolving an identifier, we find all bindings whose scopes are a **subset** of the reference's scopes. Among these candidates, we select the one with the **maximal** (largest) scope set.

### Why This Works

Consider:

```
(let ((x 1))           ; binding has scopes {s1}
  (let ((x 2))         ; binding has scopes {s1, s2}
    x))                ; reference has scopes {s1, s2}
```

At the reference `x`:
- Binding 1 scopes `{s1}` ⊆ `{s1, s2}` ✓
- Binding 2 scopes `{s1, s2}` ⊆ `{s1, s2}` ✓

Both are candidates. We choose binding 2 because `{s1, s2}` is larger than `{s1}`.

This correctly implements shadowing: inner bindings have more scopes and thus "win".

### Resolution Algorithm

```lisp
(defun binding-table-resolve (table symbol scopes)
  "Resolve SYMBOL with SCOPES in TABLE.
   Returns a resolution-result."
  (let* ((bindings (gethash symbol (binding-table-entries table)))
         (candidates
           (remove-if-not
            (lambda (binding)
              (scope:scope-set-subset-p
               (scope-binding-scopes binding)
               scopes))
            bindings)))
    (cond
      ((null candidates)
       (make-resolution-result :unbound))
      ((= 1 (length candidates))
       (make-resolution-result :bound (first candidates)))
      (t
       ;; Multiple candidates - find maximal
       (let ((maximal (find-maximal-binding candidates)))
         (if maximal
             (make-resolution-result :bound maximal)
             (make-resolution-result :ambiguous candidates)))))))
```

### Finding the Maximal Binding

```lisp
(defun find-maximal-binding (candidates)
  "Find the binding with the maximal scope set, or NIL if ambiguous."
  (let ((sorted (sort (copy-list candidates)
                      #'>
                      :key (lambda (b)
                             (scope:scope-set-size
                              (scope-binding-scopes b))))))
    (let ((first (first sorted))
          (second (second sorted)))
      (if (or (null second)
              (> (scope:scope-set-size (scope-binding-scopes first))
                 (scope:scope-set-size (scope-binding-scopes second))))
          first
          ;; Same size means ambiguous
          nil))))
```

## Resolution Results

Resolution returns one of three statuses:

| Status | Meaning |
|--------|---------|
| `:unbound` | No binding found |
| `:bound` | Unique binding found |
| `:ambiguous` | Multiple incomparable bindings |

```lisp
(defstruct (resolution-result
            (:copier nil)
            (:constructor %make-resolution-result))
  (status :unbound :type (member :unbound :bound :ambiguous))
  (binding nil :type (or null scope-binding))
  (candidates nil :type list))

;; Predicates
(defun resolution-unbound-p (result)
  (eq :unbound (resolution-result-status result)))

(defun resolution-bound-p (result)
  (eq :bound (resolution-result-status result)))

(defun resolution-ambiguous-p (result)
  (eq :ambiguous (resolution-result-status result)))
```

## Resolving Syntax Objects

For convenience, there's a function that extracts the symbol and scopes from a syntax object:

```lisp
(defun binding-table-resolve-syntax (table stx)
  "Resolve syntax object STX in TABLE."
  (binding-table-resolve
   table
   (stx:identifier-symbol stx)
   (stx:syntax-object-scopes stx)))
```

## Ambiguity

Ambiguity occurs when two bindings have the same scope set size but neither is a subset of the other. This can happen with:

1. **Definition contexts** - Interleaved macro-introduced and user definitions
2. **Cross-phase bindings** - Different expansion phases

```
Binding A: scopes {s1, s2}
Binding B: scopes {s1, s3}
Reference: scopes {s1, s2, s3}

Both A and B are subsets of reference.
Neither is a subset of the other.
Size of both is 2.
→ AMBIGUOUS
```

The parser should report an error for ambiguous bindings.

## Example Usage

```lisp
(let* ((table (make-binding-table))
       (scope-outer (scope:make-scope-token))
       (scope-inner (scope:make-scope-token))
       (outer-scopes (scope:scope-set-add (scope:empty-scope-set) scope-outer))
       (inner-scopes (scope:scope-set-add outer-scopes scope-inner)))

  ;; Add outer binding
  (setf table (binding-table-add table 'x outer-scopes 'outer-x))

  ;; Add inner binding
  (setf table (binding-table-add table 'x inner-scopes 'inner-x))

  ;; Resolve from inner scope
  (let ((result (binding-table-resolve table 'x inner-scopes)))
    (resolution-bound-p result)  ; → T
    (scope-binding-value (resolution-result-binding result)))  ; → INNER-X

  ;; Resolve from outer scope
  (let ((result (binding-table-resolve table 'x outer-scopes)))
    (resolution-bound-p result)  ; → T
    (scope-binding-value (resolution-result-binding result))))  ; → OUTER-X
```

## File Location

`src/parser/binding-table.lisp`
