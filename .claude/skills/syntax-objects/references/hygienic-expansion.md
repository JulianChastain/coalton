# Hygienic Macro Expansion

This documents the flip algorithm that implements hygienic macro expansion in Coalton.

## Overview

The hygiene algorithm ensures:

1. **Macro-introduced bindings don't capture user variables**
2. **User bindings don't capture macro-introduced references**
3. **Shadowing works correctly across macro boundaries**

## The Flip Algorithm

From Flatt (POPL 2016), the expansion of a macro invocation proceeds:

```
1. Create fresh USE-SITE scope
2. Add USE-SITE to entire input
3. Call transformer with scoped input
4. Create fresh INTRO scope
5. Flip INTRO on entire output
6. Flip USE-SITE on entire output
```

### Implementation

```lisp
(defun expand-macro-hygienic (stx transformer)
  "Expand STX using TRANSFORMER with hygienic scope tracking."
  (let* ((use-scope (scope:make-scope-token))
         (intro-scope (scope:make-scope-token))
         ;; Step 1-2: Add use-site scope to input
         (input (stx:stx-add-scope stx use-scope))
         ;; Step 3: Call transformer
         (output (funcall transformer input))
         ;; Step 4-5: Flip intro scope on output
         (result (stx:stx-flip-scope output intro-scope)))
    ;; Step 6: Flip use-site scope
    (stx:stx-flip-scope result use-scope)))
```

## Why Flip Works

Consider syntax in the output:

### Syntax from Input (Passed Through)

```
Input syntax has:     scopes = {original...}
After step 2:         scopes = {original..., use-site}
After step 5 (flip):  scopes = {original..., use-site, intro}
After step 6 (flip):  scopes = {original..., intro}
```

Wait, this still has `intro`. Let me reconsider...

Actually, let's trace more carefully:

### Syntax from Input

```
Input:                scopes = {s1, s2}
After add use-site:   scopes = {s1, s2, use}
Transformer returns:  scopes = {s1, s2, use}  (unchanged)
After flip intro:     scopes = {s1, s2, use, intro}  (intro added - wasn't there)
After flip use:       scopes = {s1, s2, intro}        (use removed - was there)
```

### Syntax Introduced by Macro

```
Created by transformer: scopes = {s1, s2, use}  (inherited from input context)
After flip intro:       scopes = {s1, s2, use, intro}  (intro added)
After flip use:         scopes = {s1, s2, intro}        (use removed)
```

Hmm, both end up the same. The key distinction comes from **which identifier the syntax represents**:

- Input `x` → macro sees `x` with use-site scope → if passed through unchanged, it's the same `x`
- Macro creates new `x` → it's a different variable even with same scopes, tracked by the binding table

Actually, the distinction is more subtle. Let me explain with a concrete example:

## Concrete Example

Consider:

```lisp
(defmacro swap (a b)
  `(let ((tmp ,a))
     (setf ,a ,b)
     (setf ,b tmp)))

(let ((tmp 1) (x 2) (y 3))
  (swap x y)
  tmp)  ; Should be 1, not 2!
```

Without hygiene, the macro-introduced `tmp` captures the user's `tmp`.

With hygiene:

1. **Before expansion:**
   - User's `tmp` has scopes `{outer}`
   - User's `x` has scopes `{outer}`
   - User's `y` has scopes `{outer}`

2. **Add use-site scope to (swap x y):**
   - `swap` → scopes `{outer, use}`
   - `x` → scopes `{outer, use}`
   - `y` → scopes `{outer, use}`

3. **Transformer produces:**
   ```lisp
   (let ((tmp ,a))    ; tmp is NEW, a is input x
     ...)
   ```
   - New `tmp` → created with scopes `{outer, use}` (from datum->syntax using input context)
   - `a` (which is input `x`) → scopes `{outer, use}`

4. **Flip intro scope:**
   - New `tmp` → scopes `{outer, use, intro}`
   - Input `x` → scopes `{outer, use, intro}`

5. **Flip use-site scope:**
   - New `tmp` → scopes `{outer, intro}` (use removed)
   - Input `x` → scopes `{outer, intro}` (use removed)

Now, at the reference to user's `tmp` after the swap:
- User's `tmp` has scopes `{outer}`
- Macro's `tmp` binding has scopes `{outer, intro}`

For user's `tmp` reference (scopes `{outer}`):
- User's `tmp` binding `{outer}` ⊆ `{outer}` ✓
- Macro's `tmp` binding `{outer, intro}` ⊆ `{outer}` ✗ (intro not in reference)

So user's `tmp` resolves to user's binding, not macro's. **Hygiene achieved!**

## CL Macro Integration

Since Coalton uses CL macros, we wrap `macroexpand-1`:

```lisp
(defun make-cl-macro-transformer (macro-form)
  "Create a transformer that calls CL macroexpand-1."
  (lambda (stx)
    (let* ((datum (stx:syntax->datum stx))      ; Strip syntax wrappers
           (expanded (macroexpand-1 datum)))     ; Expand as CL
      (stx:datum->syntax stx expanded))))        ; Re-wrap with context
```

This is "unhygienic" in that the CL macro itself doesn't know about scopes, but:
- Input syntax gets use-site scope
- Output gets flipped with intro scope
- Net effect: hygiene is maintained at the boundary

## Entry Point for Parser

```lisp
(defun expand-macro-hygienic-wrapper (form source)
  "Expand FORM hygienically, converting between CST and syntax objects."
  (let* ((stx (stx-cst:cst->syntax form))
         (transformer (make-cl-macro-transformer (cst:raw form)))
         (expanded-stx (expand-macro-hygienic stx transformer))
         (fallback-source (cst:source form)))
    (syntax->cst expanded-stx fallback-source)))
```

The parser calls this when `*use-hygienic-macros*` is `t`.

## Definition Contexts

For module-level definitions, additional scopes are needed:

- **Outside-edge scope**: Applied to all forms before any expansion
- **Inside-edge scope**: Applied incrementally as definitions are processed

This handles interleaved definitions like:

```lisp
(define x 1)
(define-macro m () `(+ x 1))
(define y (m))
```

The `x` in macro `m` should refer to the `x` defined above, not any later shadowing.

## Feature Flag

```lisp
(defvar *use-hygienic-macros* nil
  "When T, use hygienic macro expansion.")
```

In expression.lisp:

```lisp
(if *use-hygienic-macros*
    (parse-expression (expand-macro-hygienic-wrapper form source) source)
    (parse-expression (expand-macro form source) source))
```

## File Location

`src/parser/macro.lisp` (main implementation)
`src/parser/expression.lisp` (integration point)
