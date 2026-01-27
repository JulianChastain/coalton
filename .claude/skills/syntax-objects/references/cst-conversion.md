# CST Conversion

This documents the utilities for converting between Concrete Syntax Trees (CST) and syntax objects.

## Package

```lisp
(defpackage #:coalton-impl/parser/syntax-cst
  (:use #:cl)
  (:nicknames #:stx-cst)
  (:local-nicknames
   (#:cst #:concrete-syntax-tree)
   (#:scope #:coalton-impl/parser/scope)
   (#:stx #:coalton-impl/parser/syntax-object))
  (:export
   ;; CST to syntax conversion
   #:cst->syntax
   #:cst->syntax-with-scopes
   ;; List operations on syntax objects
   #:stx-first
   #:stx-rest
   #:stx-second
   #:stx-third
   #:stx-nth
   #:stx-length
   #:stx-map
   #:stx-append
   #:stx->list
   #:list->stx))
```

## CST to Syntax Conversion

### Basic Conversion

```lisp
(defun cst->syntax (cst)
  "Convert a CST to a syntax object with empty scopes."
  (cst->syntax-with-scopes cst (scope:empty-scope-set)))
```

### Conversion with Scopes

```lisp
(defun cst->syntax-with-scopes (cst scopes)
  "Convert a CST to a syntax object with the given SCOPES."
  (cond
    ((cst:null cst)
     (stx:make-syntax-object nil
                             :scopes scopes
                             :source (cst:source cst)))
    ((cst:atom cst)
     (stx:make-syntax-object (cst:raw cst)
                             :scopes scopes
                             :source (cst:source cst)))
    ((cst:consp cst)
     (stx:make-syntax-object
      (loop :for tail := cst :then (cst:rest tail)
            :while (cst:consp tail)
            :collect (cst->syntax-with-scopes (cst:first tail) scopes)
            :finally
               (unless (cst:null tail)
                 ;; Handle improper lists
                 (return (cst->syntax-with-scopes tail scopes))))
      :scopes scopes
      :source (cst:source cst)))))
```

### Key Points

1. **Source preservation**: Source location from CST is preserved in syntax objects
2. **Scope propagation**: All nested syntax objects get the same initial scopes
3. **List handling**: Proper lists become lists of syntax objects; improper lists are handled

## Syntax to CST Conversion

This is in `macro.lisp` rather than `syntax-cst.lisp`:

```lisp
(defun syntax->cst (stx fallback-source)
  "Convert a syntax object back to a CST."
  (let ((datum (stx:syntax-e stx))
        (source (or (stx:syntax-object-source stx) fallback-source)))
    (cond
      ((null datum)
       (make-instance 'cst:atom-cst :raw nil :source source))
      ((atom datum)
       (make-instance 'cst:atom-cst :raw datum :source source))
      (t
       ;; List: recursively convert
       (labels ((convert-list (elements)
                  (if (null elements)
                      (make-instance 'cst:atom-cst :raw nil :source source)
                      (make-instance 'cst:cons-cst
                                     :raw (mapcar #'stx:syntax->datum elements)
                                     :source source
                                     :first (if (stx:syntax-object-p (car elements))
                                                (syntax->cst (car elements) fallback-source)
                                                (make-instance 'cst:atom-cst
                                                               :raw (car elements)
                                                               :source source))
                                     :rest (convert-list (cdr elements))))))
         (convert-list datum))))))
```

## List Operations

Syntax objects containing lists support list-like operations:

### Accessors

```lisp
;; Get first element
(stx-first stx) → syntax-object

;; Get rest (tail)
(stx-rest stx) → syntax-object

;; Get nth element (0-indexed)
(stx-nth n stx) → syntax-object

;; Convenience accessors
(stx-second stx) → syntax-object  ; (stx-nth 1 stx)
(stx-third stx)  → syntax-object  ; (stx-nth 2 stx)
```

### Queries

```lisp
;; Get length of list
(stx-length stx) → integer
```

### Transformation

```lisp
;; Map function over syntax list, returning new syntax object
(stx-map fn stx) → syntax-object

;; Append two syntax lists
(stx-append stx1 stx2) → syntax-object

;; Convert syntax list to regular list
(stx->list stx) → list

;; Convert regular list to syntax object
(list->stx lst context-stx) → syntax-object
```

### Implementation Example

```lisp
(defun stx-first (stx)
  "Return the first element of syntax list STX."
  (let ((datum (stx:syntax-e stx)))
    (unless (listp datum)
      (error "stx-first: expected list, got ~S" datum))
    (car datum)))

(defun stx-rest (stx)
  "Return the rest of syntax list STX."
  (let ((datum (stx:syntax-e stx)))
    (unless (listp datum)
      (error "stx-rest: expected list, got ~S" datum))
    (stx:make-syntax-object
     (cdr datum)
     :scopes (stx:syntax-object-scopes stx)
     :source (stx:syntax-object-source stx))))

(defun stx-map (fn stx)
  "Map FN over syntax list STX, returning new syntax object."
  (let ((datum (stx:syntax-e stx)))
    (stx:make-syntax-object
     (mapcar fn datum)
     :scopes (stx:syntax-object-scopes stx)
     :source (stx:syntax-object-source stx))))
```

## Usage in Parser

Typical pattern for parsing a macro form:

```lisp
;; Input: CST representing (my-macro arg1 arg2)
(let* ((stx (cst->syntax form))
       (macro-name (stx:identifier-symbol (stx-first stx)))
       (args (stx-rest stx)))
  ;; Process args...
  )
```

## Source Location Flow

```
Source Code
    │
    ▼
┌─────────┐
│  CST    │ ← Source locations from reader
└────┬────┘
     │ cst->syntax
     ▼
┌─────────────┐
│ Syntax Obj  │ ← Preserves source locations
└──────┬──────┘
       │ macro expansion (datum->syntax preserves source)
       ▼
┌─────────────┐
│ Syntax Obj  │ ← Expanded, but source info intact for errors
└──────┬──────┘
       │ syntax->cst
       ▼
┌─────────┐
│  CST    │ ← Back to CST for existing parser
└─────────┘
```

## File Location

`src/parser/syntax-cst.lisp` (list operations, cst->syntax)
`src/parser/macro.lisp` (syntax->cst)
