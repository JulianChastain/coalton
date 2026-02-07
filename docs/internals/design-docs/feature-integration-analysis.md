# Coalton Feature Integration Analysis

## Context

Coalton's extended fork introduces five major features: syntax objects / hygienic macros, delimited continuations, algebraic effects, algebraic subtyping, and interactive tooling. This report analyzes whether these features are actually used as primitives, how well they compose with each other, and where integration opportunities exist.

---

## Feature Integration Matrix

| | Subtyping | Syntax Objects | Continuations | Effects | Type Classes |
|---|---|---|---|---|---|
| **Subtyping** | — | Not connected | Not connected | **Integrated** (effect rows are unions) | Partially (predicates, not subtype bounds) |
| **Syntax Objects** | — | — | Not connected | Not connected | Not connected |
| **Continuations** | — | — | — | **NOT connected** (parallel systems) | Cont has Monad instance |
| **Effects** | **Integrated** | Not connected | **NOT connected** | — | **NOT connected** |
| **Type Classes** | Partial | Not connected | Cont has instances | **NOT connected** | — |

---

## Per-Feature Assessment

### 1. Syntax Objects & Hygienic Macros

**Status: Fully implemented internally, completely invisible to users**

- The parser has been fully migrated from CST to syntax objects (`src/parser/`)
- A complete sets-of-scopes hygiene algorithm exists (`src/parser/macro.lisp`)
- `syntax-case`, `with-syntax`, `quasisyntax` are implemented (`src/parser/syntax-case.lisp`)
- Binding tables, definition contexts, and scope propagation all work
- **368 tests pass** covering the syntax object infrastructure

**But:**

- **Hygienic macros are disabled by default** — `*use-hygienic-macros*` is `nil` (`macro.lisp:152`)
- The flag is checked in **exactly one place**: `expression.lisp:1596`
- **No user-facing API exists** — `syntax-case`, `define-syntax`, `syntax-object` are all in internal `coalton-impl/parser/*` packages, not exported from `coalton`
- **No `define-syntax` form exists** — users cannot define hygienic macros in Coalton
- Syntax objects are **stripped at the parser boundary** — they don't reach the type checker or codegen
- Users write CL `defmacro` forms, which get traditional (unhygienic) expansion

**Verdict: The largest investment in the codebase (~368 tests, ~2000 lines) is currently inert infrastructure.** The syntax object migration establishes the foundation, but no user can actually write a hygienic macro.

---

### 2. Delimited Continuations

**Status: Two independent continuation systems exist side-by-side**

**System A — Compiler-level (`cont/reset`, `cont/shift`, `call/cc`):**
- Special syntax forms parsed by the compiler (`expression.lisp:1025-1086`)
- Typed AST nodes: `node-reset`, `node-shift`, `node-call/cc` (`expression.lisp:728-769`)
- Compiled to `cl-cont` primitives: `cl-cont:with-call/cc`, `cl-cont:let/cc` (`codegen-expression.lisp:410-459`)
- Exported from the `coalton` package (`package.lisp:113-118`)

**System B — Library-level (`Cont` monad):**
- A pure algebraic data type: `(ContFn ((:a -> :r) -> :r))` (`continuations.lisp:29-37`)
- Provides `run-cont`, `cont-pure`, `cont-bind`, `control`, `control0`, `shift0`
- Has `Functor`, `Applicative`, `Monad` instances
- Includes a CPS standard library: `cps-map`, `cps-fold`, `cps-filter`, etc. (`cps-stdlib.lisp`)

**These two systems are completely independent:**
- System A compiles to real `cl-cont` CPS transforms
- System B is a pure encoding that simulates continuations via closures
- System B's `Cont` type has no special compiler support
- System A's `cont/shift` doesn't produce `Cont` values

**Neither system is used by anything else:**
- The standard library (`library/`) doesn't import continuations
- The effect system doesn't use continuations (see below)
- No other language feature builds on either continuation system

**Verdict: Two parallel continuation mechanisms that don't compose with each other or with anything else.** The CPS stdlib duplicates standard library functions (`cps-map` vs `map`, `cps-fold` vs `fold`) rather than abstracting over evaluation strategy.

---

### 3. Algebraic Effects

**Status: The best-integrated feature — deeply connected to subtyping, disconnected from everything else**

**Integration with subtyping (strong):**
- Effect rows are union types in the subtyping lattice (`types-sub.lisp:305-317`)
- Pure = `ty-bot` (bottom type), making pure functions subtypes of effectful ones
- Covariant effect subtyping in `constrain.lisp:420-478`: `(A -> B ! Pure) <: (A -> B ! (State S))`
- Effect row simplification reuses union simplification (`simplify.lisp:262-292`)

**Integration with parser (strong):**
- `perform` and `handle` are first-class special forms (`expression.lisp:933-1023`)
- `!` syntax for effect-annotated types (`types.lisp:138-148`)
- Full AST node hierarchy: `node-perform`, `node-handle`, `node-handle-branch`

**Disconnections:**
- **Not built on continuations** — The effect runtime uses a `Step` trampoline (`effects/runtime/continuation.lisp:91-117`), not `Cont` or `cont/shift`. The `Step` type (`StepContinue`, `StepYield`, `StepPerform`, `StepDone`, `StepFail`, `StepAsync`) is a completely separate evaluation model.
- **No type class interaction** — Cannot declare effect-polymorphic class methods. No `define-class` method can mention `!` in its type.
- **No syntax object interaction** — Effect forms are parsed by hand-written code, not via macro expansion or syntax-case patterns.

**Verdict: Effects are architecturally sound and well-typed, but they exist as an island.** The runtime reinvents continuation-passing (the `Step` trampoline) rather than building on the existing continuation infrastructure.

---

### 4. Algebraic Subtyping

**Status: The deepest primitive — everything types through it, but users can't directly exploit it**

- Union/intersection types exist in the type system but have no surface syntax for users
- Effect rows leverage union types internally
- CL type interop maps `cl:subtypep` into the constraint system
- Level-based let-polymorphism for sound generalization

**Verdict: Working well as plumbing, but union/intersection types aren't user-facing features yet.**

---

## Integration Opportunities

### Opportunity 1: Effects Should Be Built on Continuations

**Problem:** The effect system's `Step` trampoline (`StepContinue (Unit -> (Step :a))`) is a hand-rolled continuation-passing mechanism. Meanwhile, the compiler has real `cont/shift`/`cont/reset` that compile to `cl-cont` CPS transforms, and the library has a `Cont` monad — neither of which is used by effects.

**What this looks like in the code:**
- `effects/runtime/continuation.lisp`: Defines `Step` with 6 variants for trampolining
- `effects/runtime/fiber.lisp`: Fibers store `Step` values
- `effects/runtime/handlers.lisp`: Handlers manipulate `Step` continuations
- None of this references `coalton-library/continuations` or `cont/reset`

**Opportunity:** In the algebraic effects literature (Plotkin & Pretnar, Hillerström & Lindley, Leijen), effect handlers are defined as delimited continuation transforms — `perform` is `shift` and `handle` is `reset` with a dispatch table. Coalton has `shift`/`reset` already. Unifying these would:
- Eliminate the redundant `Step` trampoline mechanism
- Make effects and continuations compose (use continuations inside handlers, use effects inside reset blocks)
- Reduce code (~500 lines in effects/runtime could be simplified)
- Give continuations a purpose as a true language primitive

### Opportunity 2: Enable User-Facing Hygienic Macros

**Problem:** 368 tests, ~2000 lines of syntax object infrastructure, and a complete sets-of-scopes algorithm — all behind a `nil` feature flag with no user API.

**What's missing:**
- `*use-hygienic-macros*` defaults to `nil` (`macro.lisp:152`)
- No `define-syntax` form in the parser or toplevel
- `syntax-case`, `with-syntax`, `syntax` are internal-only
- No documentation for users on writing hygienic macros

**Opportunity:** Expose the hygiene system:
1. Enable `*use-hygienic-macros*` by default (or remove the flag)
2. Add a `define-syntax` toplevel form that registers a transformer function
3. Export `syntax-case`, `with-syntax`, `syntax` from the `coalton` package
4. Allow transformers to be written in Coalton (not just CL) using `syntax-case`

This would make the existing investment productive and give Coalton a macro system superior to most typed functional languages.

### Opportunity 3: Unify the Two Continuation Systems

**Problem:** Compiler-level `cont/reset`/`cont/shift` and library-level `Cont` monad are disconnected.

**What this looks like:**
- `cont/shift` compiles to `cl-cont:let/cc` — captures a real continuation
- `Cont` is `(ContFn ((:a -> :r) -> :r))` — a pure closure wrapper
- You can't pass a `cont/shift`-captured continuation to `Cont`-aware code
- The CPS stdlib (`cps-map`, etc.) only works with `Cont`, not with `cont/shift`

**Opportunity:** Make `cont/shift`/`cont/reset` produce/consume `Cont` values, or make `Cont` a newtype that the compiler recognizes. This would let the CPS stdlib compose with real continuation capture.

### Opportunity 4: Effect-Polymorphic Type Classes

**Problem:** Effects and type classes are completely independent. You cannot write:
```
(define-class (MonadState :s :m)
  (declare get (Unit -> :s ! (State :s)))
  (declare put (:s -> Unit ! (State :s))))
```

**Opportunity:** Allow `!` effect annotations in class method signatures. This would enable:
- MTL-style effect abstractions (MonadState, MonadReader, etc.)
- Effect-polymorphic code that works across different effect handler implementations
- A bridge between the Haskell-style class system and the algebraic effects system

### Opportunity 5: Syntax Objects as the Macro Interface for Effects

**Problem:** `perform` and `handle` are parsed by hand-written pattern matching in `expression.lisp` (~90 lines each). Adding new effect-related syntax requires modifying the compiler.

**Opportunity:** If hygienic macros were user-facing, `perform` and `handle` could potentially be defined as syntax transformations rather than hardcoded special forms. This would:
- Allow users to define custom effect syntax (e.g., do-notation for effects)
- Reduce the parser's complexity
- Demonstrate that syntax objects are a productive primitive

---

## Summary: What's a Primitive vs. What's an Island

| Feature | Used as primitive by others? | Composes with other features? |
|---------|------------------------------|-------------------------------|
| **Algebraic Subtyping** | Yes (effects use unions) | Partially (effects yes, classes partially) |
| **Syntax Objects** | No (internal infrastructure only) | No (disabled, no user API) |
| **Continuations (compiler)** | No (nothing uses cont/shift) | No (not used by effects or Cont monad) |
| **Continuations (library)** | No (not used by stdlib) | Minimal (has Monad instance, that's it) |
| **Effects** | No (standalone feature) | Partially (subtyping yes, continuations/classes no) |

**The core insight:** Coalton has five ambitious features that are each individually well-implemented, but they form **islands** rather than composing into something greater than the sum of their parts. The highest-leverage integration opportunities are:

1. **Build effects on continuations** — makes both features stronger
2. **Enable hygienic macros for users** — activates dormant infrastructure
3. **Connect effects and type classes** — enables abstraction over effects

These three changes would transform the feature set from "five independent experiments" into "a coherent language where the primitives reinforce each other."
