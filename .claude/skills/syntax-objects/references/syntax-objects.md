# Syntax Objects

Syntax objects wrap datums (raw Lisp values) with lexical context information. They are the core data structure for hygienic macro expansion.

## Package

```lisp
(defpackage #:coalton-impl/parser/syntax-object
  (:use #:cl)
  (:nicknames #:stx)
  (:export
   ;; Type
   #:syntax-object
   #:syntax-object-p
   ;; Accessors
   #:syntax-e
   #:syntax-object-datum
   #:syntax-object-scopes
   #:syntax-object-source
   #:syntax-object-properties
   ;; Constructors
   #:make-syntax-object
   #:datum->syntax
   #:syntax->datum
   ;; Scope manipulation
   #:stx-add-scope
   #:stx-remove-scope
   #:stx-flip-scope
   ;; Predicates
   #:stx-null?
   #:stx-atom?
   #:stx-list?
   #:stx-pair?
   #:identifier?
   ;; Identifier operations
   #:identifier-symbol
   #:free-identifier=?
   #:bound-identifier=?))
```

## Structure

A syntax object contains:

| Field | Type | Description |
|-------|------|-------------|
| `datum` | `t` | The underlying Lisp value |
| `scopes` | `scope-set` | Set of scopes for hygiene |
| `source` | `t` | Source location information |
| `properties` | `hash-table` | Extensible property storage |

### Constructor

```lisp
(defstruct (syntax-object
            (:copier nil)
            (:constructor %make-syntax-object))
  (datum nil :type t)
  (scopes (scope:empty-scope-set) :type scope:scope-set)
  (source nil :type t)
  (properties nil :type (or null hash-table)))

(defun make-syntax-object (datum &key scopes source properties)
  (%make-syntax-object
   :datum datum
   :scopes (or scopes (scope:empty-scope-set))
   :source source
   :properties properties))
```

## Core Operations

### Accessing the Datum

```lisp
;; Get the datum (unwrapped value)
(syntax-e stx) → datum

;; Alias for syntax-e
(syntax-object-datum stx) → datum
```

### Conversion Functions

```lisp
;; Wrap a datum in a syntax object, inheriting context from another
(datum->syntax context-stx datum) → syntax-object

;; Recursively extract the raw datum
(syntax->datum stx) → datum
```

**datum->syntax** is the key function for macro output:

```lisp
(defun datum->syntax (stx datum)
  "Wrap DATUM with lexical context from STX."
  (cond
    ((syntax-object-p datum)
     datum)  ; Already wrapped
    ((null datum)
     (make-syntax-object nil
                         :scopes (syntax-object-scopes stx)
                         :source (syntax-object-source stx)))
    ((atom datum)
     (make-syntax-object datum
                         :scopes (syntax-object-scopes stx)
                         :source (syntax-object-source stx)))
    ((listp datum)
     ;; Recursively wrap list elements
     (make-syntax-object
      (mapcar (lambda (elem) (datum->syntax stx elem)) datum)
      :scopes (syntax-object-scopes stx)
      :source (syntax-object-source stx)))))
```

**syntax->datum** strips all syntax wrappers:

```lisp
(defun syntax->datum (stx)
  "Recursively extract raw datum from STX."
  (if (syntax-object-p stx)
      (let ((datum (syntax-object-datum stx)))
        (if (listp datum)
            (mapcar #'syntax->datum datum)
            datum))
      stx))
```

## Scope Manipulation

These functions recursively apply scope operations to syntax objects and their contents.

### Adding Scopes

```lisp
(defun stx-add-scope (stx scope)
  "Add SCOPE to STX and all nested syntax objects."
  (let ((new-scopes (scope:scope-set-add (syntax-object-scopes stx) scope)))
    (make-syntax-object
     (if (listp (syntax-object-datum stx))
         (mapcar (lambda (e)
                   (if (syntax-object-p e)
                       (stx-add-scope e scope)
                       e))
                 (syntax-object-datum stx))
         (syntax-object-datum stx))
     :scopes new-scopes
     :source (syntax-object-source stx)
     :properties (syntax-object-properties stx))))
```

### Removing Scopes

```lisp
(defun stx-remove-scope (stx scope)
  "Remove SCOPE from STX and all nested syntax objects."
  ;; Similar structure to stx-add-scope
  ...)
```

### Flipping Scopes

```lisp
(defun stx-flip-scope (stx scope)
  "Flip SCOPE on STX and all nested syntax objects.
   This is the key operation for hygienic expansion."
  (let ((new-scopes (scope:scope-set-flip (syntax-object-scopes stx) scope)))
    (make-syntax-object
     (if (listp (syntax-object-datum stx))
         (mapcar (lambda (e)
                   (if (syntax-object-p e)
                       (stx-flip-scope e scope)
                       e))
                 (syntax-object-datum stx))
         (syntax-object-datum stx))
     :scopes new-scopes
     :source (syntax-object-source stx)
     :properties (syntax-object-properties stx))))
```

## Predicates

```lisp
;; Check if syntax object wraps nil
(stx-null? stx) → boolean

;; Check if syntax object wraps an atom
(stx-atom? stx) → boolean

;; Check if syntax object wraps a list
(stx-list? stx) → boolean

;; Check if syntax object wraps a cons
(stx-pair? stx) → boolean

;; Check if syntax object wraps a symbol (is an identifier)
(identifier? stx) → boolean
```

## Identifier Operations

Identifiers are syntax objects wrapping symbols. They have special operations for comparison.

### Getting the Symbol

```lisp
(identifier-symbol stx) → symbol
;; Signals error if stx is not an identifier
```

### Identifier Equality

Two notions of equality exist:

**free-identifier=?** - Same binding?

```lisp
(defun free-identifier=? (id1 id2)
  "Return T if ID1 and ID2 refer to the same binding."
  (and (eq (identifier-symbol id1) (identifier-symbol id2))
       (scope:scope-set-equal (syntax-object-scopes id1)
                              (syntax-object-scopes id2))))
```

**bound-identifier=?** - Identical for binding purposes?

```lisp
(defun bound-identifier=? (id1 id2)
  "Return T if ID1 and ID2 would bind the same identifier."
  (and (eq (identifier-symbol id1) (identifier-symbol id2))
       (scope:scope-set-equal (syntax-object-scopes id1)
                              (syntax-object-scopes id2))))
```

In the current implementation, these are equivalent. In more sophisticated systems, they differ for handling `syntax-local-value` and similar features.

## Example Usage

```lisp
;; Create a syntax object
(let* ((scope1 (scope:make-scope-token))
       (stx (make-syntax-object 'foo
                                :scopes (scope:scope-set-add
                                         (scope:empty-scope-set)
                                         scope1)
                                :source '("test.coal" 1 0))))

  ;; Check if it's an identifier
  (identifier? stx)  ; → T

  ;; Get the symbol
  (identifier-symbol stx)  ; → FOO

  ;; Add another scope
  (let* ((scope2 (scope:make-scope-token))
         (stx2 (stx-add-scope stx scope2)))

    ;; Original unchanged (immutable)
    (scope:scope-set-size (syntax-object-scopes stx))   ; → 1
    (scope:scope-set-size (syntax-object-scopes stx2))  ; → 2

    ;; Different scopes means different identifiers
    (free-identifier=? stx stx2)))  ; → NIL
```

## Preserving Syntax Through Transformations

When writing macros, use `datum->syntax` to preserve lexical context:

```lisp
(lambda (stx)
  (let* ((datum (syntax->datum stx))
         (expanded `(begin ,@(cdr datum))))
    ;; Use stx as context for the expansion
    (datum->syntax stx expanded)))
```

This ensures introduced syntax inherits appropriate scopes.

## File Location

`src/parser/syntax-object.lisp`
