---
name: coalton-syntax-objects
description: Reference for Coalton's Racket-inspired syntax objects implementing the "Sets of Scopes" hygiene algorithm
version: 1.0.0
triggers:
  - syntax object
  - syntax-object
  - hygienic macro
  - scope set
  - binding table
  - macro hygiene
  - sets of scopes
---

# Coalton Syntax Objects

Coalton implements Racket-inspired syntax objects to enable hygienic macro expansion using the "Sets of Scopes" algorithm from Flatt (POPL 2016). This skill documents the interface, functionality, implementation, and semantics of this system.

## Overview

Syntax objects solve a fundamental problem in macro systems: distinguishing between identifiers introduced by macros versus those written by users. Traditional Common Lisp macros use `gensym` for this, but that approach:

1. Doesn't handle macro-introduced references to user bindings
2. Requires manual tracking of identifier origins
3. Can't distinguish shadowing contexts automatically

The Sets of Scopes approach instead:

1. Attaches a **scope set** to each identifier
2. Creates fresh scopes at binding sites and during macro expansion
3. Uses the **flip** operation to mark macro-introduced syntax
4. Resolves bindings using the **maximal subset rule**

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Parser Pipeline                           │
├─────────────────────────────────────────────────────────────┤
│  CST (Source) ──► cst->syntax ──► Syntax Objects            │
│                                          │                   │
│                                    expand-macro-hygienic     │
│                                          │                   │
│  Syntax Objects ──► syntax->cst ──► CST (Expanded)          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Core Components                           │
├─────────────────────────────────────────────────────────────┤
│  scope.lisp          - Scope tokens and immutable scope sets │
│  syntax-object.lisp  - Syntax object structure & operations  │
│  binding-table.lisp  - Binding resolution with maximal subset│
│  syntax-cst.lisp     - CST ↔ syntax object conversion        │
│  macro.lisp          - Hygienic expansion algorithm          │
└─────────────────────────────────────────────────────────────┘
```

## Quick Reference

### Packages

| Package | Purpose |
|---------|---------|
| `coalton-impl/parser/scope` | Scope tokens and scope sets |
| `coalton-impl/parser/syntax-object` | Syntax object type and operations |
| `coalton-impl/parser/binding-table` | Binding table and resolution |
| `coalton-impl/parser/syntax-cst` | CST conversion utilities |
| `coalton-impl/parser/macro` | Hygienic expansion entry points |

### Key Types

| Type | Description |
|------|-------------|
| `scope-token` | Unique identifier for a lexical scope |
| `scope-set` | Immutable set of scope tokens |
| `syntax-object` | Datum + scope set + source + properties |
| `scope-binding` | Binding entry (scopes + value) |
| `binding-table` | Maps (symbol, scopes) → binding |
| `resolution-result` | Binding lookup result |

### Essential Functions

| Function | Purpose |
|----------|---------|
| `make-scope-token` | Create fresh scope |
| `scope-set-flip` | Symmetric difference (core of hygiene) |
| `datum->syntax` | Wrap datum in syntax object |
| `syntax->datum` | Extract datum from syntax object |
| `stx-flip-scope` | Apply flip recursively to syntax |
| `expand-macro-hygienic` | Expand macro with hygiene |
| `binding-table-resolve-syntax` | Resolve identifier to binding |

## Feature Flag

Hygienic expansion is gated by:

```lisp
(defvar *use-hygienic-macros* nil)
```

When `t`, the parser uses `expand-macro-hygienic-wrapper` instead of `expand-macro`.

## References

See the `references/` directory for detailed documentation:

- `scope-system.md` - Scope tokens and scope sets
- `syntax-objects.md` - Syntax object structure and operations
- `binding-resolution.md` - Binding table and maximal subset rule
- `hygienic-expansion.md` - The flip algorithm for hygiene
- `cst-conversion.md` - Converting between CST and syntax objects
- `theory.md` - Theoretical background and the Sets of Scopes paper
