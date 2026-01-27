# Theoretical Background

This documents the theoretical foundations of Coalton's hygiene system, based on Flatt's "Binding as Sets of Scopes" (POPL 2016).

## The Hygiene Problem

### What is Hygiene?

A macro system is **hygienic** if:

1. Macro-introduced bindings don't capture references in macro arguments
2. Macro-introduced references aren't captured by bindings in the macro use site

### Classic Example

```lisp
(defmacro or2 (a b)
  `(let ((tmp ,a))
     (if tmp tmp ,b)))

(let ((tmp 5))
  (or2 #f tmp))  ; Should return 5, not #f!
```

Without hygiene, the macro's `tmp` captures the user's `tmp`.

### Traditional Solutions

1. **Gensym (CL approach)**: Generate unique symbols for macro-introduced bindings
   - Limitation: Doesn't help with macro-introduced *references*
   - Limitation: Can't express intentional capture

2. **Alpha-renaming (early Scheme)**: Rename based on lexical structure
   - Limitation: Breaks with `local-expand` and definition contexts

3. **Marks/anti-marks (syntax-case)**: Track macro introduction with marks
   - Complex cancellation semantics
   - Difficult to reason about

## Sets of Scopes Model

Flatt's insight: treat hygiene as a **binding resolution** problem, not a renaming problem.

### Core Ideas

1. **Scope**: A unique token representing a binding context
2. **Scope Set**: Each identifier carries a set of scopes
3. **Binding Resolution**: Find the binding whose scopes are a maximal subset of the reference's scopes

### Scope Creation

Scopes are created at:

| Context | Purpose |
|---------|---------|
| Binding forms (`let`, `fn`) | Mark the binding's extent |
| Macro expansion (use-site) | Mark syntax from the call site |
| Macro expansion (intro) | Mark syntax introduced by macro |
| Module boundaries | Separate definition contexts |

### The Flip Operation

**Key insight**: Use symmetric difference (XOR) instead of add/remove.

For a scope `s` and set `S`:
- `flip(S, s) = S ∪ {s}` if `s ∉ S`
- `flip(S, s) = S \ {s}` if `s ∈ S`

**Why flip works for hygiene:**

During macro expansion:
1. Add use-site scope to input: every identifier gets `+use`
2. Transformer runs, may create new identifiers with `+use` (via `datum->syntax`)
3. Flip intro scope: everyone gets `+intro` (because no one had it)
4. Flip use-site scope:
   - Input identifiers: had `use`, now `-use` (back to original!)
   - Macro-introduced: had `use`, now `-use`

Both end up without use-site scope, but **macro-introduced identifiers have intro scope** on their bindings while user identifiers don't.

### Binding Resolution

For reference `r` with scopes `Sr`, find binding `b` with scopes `Sb` where:

1. `Sb ⊆ Sr` (binding's scopes are subset of reference's)
2. `Sb` is **maximal** among all such bindings

This implements shadowing naturally: inner bindings have more scopes.

## Comparison with Syntax-Case

| Aspect | Syntax-Case | Sets of Scopes |
|--------|-------------|----------------|
| Model | Marks that cancel | Scopes that accumulate |
| Binding | Phase-specific | Scope-set based |
| `local-expand` | Tricky mark handling | Natural scope addition |
| Definition contexts | Complex | Inside/outside edge scopes |
| Implementation | Track mark history | Simple set operations |

## Phases and Modules

### Compile-Time vs Runtime

In Racket, macros run at compile time with their own scope. In Coalton's CL embedding:

- CL macros run at compile time naturally
- The hygiene layer wraps CL expansion
- No explicit phase separation needed (CL handles it)

### Definition Contexts

For interleaved definitions:

```lisp
(define x 1)
(define-syntax m ...)  ; m can reference x
(define y ...)         ; y shouldn't shadow x in m's expansion
```

Solution: **Outside-edge** and **inside-edge** scopes:

1. Outside-edge: Added to all forms before expansion
2. Inside-edge: Added incrementally to each form as it's processed

## Lisp-1 vs Lisp-2 Considerations

Racket is Lisp-1 (one namespace). Common Lisp is Lisp-2 (separate function/value namespaces).

For Coalton (Lisp-1 on CL):
- Variable bindings and function bindings share namespace
- Hygiene applies uniformly
- CL macros may still use `#'function` syntax (handled by CL, not Coalton hygiene)

## Intentional Capture

Sometimes macros *want* to capture:

```lisp
(define-syntax-rule (aif test then else)
  (let ((it test))
    (if it then else)))

;; Usage:
(aif (find-thing) (use it) (default))
```

The Sets of Scopes model supports this through `syntax-local-introduce`:
- Remove intro scope from specific identifiers
- Allows controlled unhygiene

Coalton's current implementation doesn't expose this, but the model supports it.

## Implementation Simplifications

Coalton's implementation makes pragmatic simplifications:

1. **No explicit phases**: CL's compile-time/runtime distinction suffices
2. **CL macro integration**: Wrap existing macros rather than replace them
3. **Feature flag**: Gradual rollout via `*use-hygienic-macros*`
4. **Binding table optional**: Can resolve via scopes without full table

## References

1. **Flatt, Matthew.** "Binding as Sets of Scopes." POPL 2016.
   - The foundational paper for this algorithm
   - Available at: https://www.cs.utah.edu/~mflatt/scope-sets/

2. **Dybvig, Hieb, Bruggeman.** "Syntactic Abstraction in Scheme." L&FP 1992.
   - Original syntax-case system

3. **Clinger, Rees.** "Macros That Work." POPL 1991.
   - Early hygiene formalization

4. **Kohlbecker et al.** "Hygienic Macro Expansion." LFP 1986.
   - First hygienic macro paper

## Summary

The Sets of Scopes model provides:

- **Simplicity**: Just sets and subset operations
- **Flexibility**: Handles all known macro patterns
- **Composability**: Local-expand, definition contexts work naturally
- **Implementability**: Straightforward to implement on top of CL
