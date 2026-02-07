<p align="center">
  <a href="https://coalton-lang.github.io/">
    <img alt="Coalton" src="docs/assets/coalton-logotype-gray.svg" style="zoom:45%;" />
  </a>
</p>

<p align="center"><em>Extended Fork</em></p>

This is an experimental fork of [Coalton](https://github.com/coalton-lang/coalton) that extends the language with algebraic subtyping, hygienic macros, delimited continuations, an algebraic effect system, and interactive tooling.

Coalton is an efficient, statically typed functional programming language that supercharges Common Lisp.

## What's New in This Fork

This fork adds several major features on top of upstream Coalton:

| Feature | Status | Description |
|---------|--------|-------------|
| [Algebraic Subtyping](#algebraic-subtyping) | Integrated | Constraint-based type inference with union/intersection types |
| [Hygienic Macros](#hygienic-macros) | Integrated | Racket-style sets-of-scopes macro system |
| [Delimited Continuations](#delimited-continuations) | Integrated | `shift`/`reset`/`call/cc` with CPS standard library |
| [Algebraic Effects](#algebraic-effects) | Experimental | Effect rows, perform/handle, state/reader/writer effects |
| [Interactive REPL](#interactive-repl) | Functional | Standalone REPL with line editing and type display |
| [coalton-run](#coalton-run) | Functional | Command-line tool for executing `.coal` source files |

### Algebraic Subtyping

The type system has been replaced with constraint-based inference based on Parreaux's *The Simple Essence of Algebraic Subtyping* (ICFP 2020). Instead of unifying type variables, the system accumulates upper and lower bounds through constraint propagation.

This adds:

- **Union types** (`(Or Integer String)`) and **intersection types** for more expressive typing
- **Top and bottom types** (`ty-top`, `ty-bot`) as universal super/subtypes
- **Level-based let-polymorphism** for sound generalization
- **CL type interoperability** -- bidirectional mapping between CL type specifiers and Coalton types, with `cl:subtypep`-based subtype checking integrated into constraint propagation

See [docs/internals/design-docs/algebraic-subtyping.md](docs/internals/design-docs/algebraic-subtyping.md) for the full design.

### Hygienic Macros

A complete implementation of Racket-style hygienic macros based on Flatt's *Binding as Sets of Scopes* (POPL 2016). Every identifier carries a set of scope tokens, and binding resolution uses a maximal-subset algorithm to determine which binding an identifier refers to.

Key features:

- **`syntax-case`** pattern matching on syntax objects with ellipsis support
- **`with-syntax`** for binding pattern variables
- **`syntax` / `quasisyntax`** template construction
- **`syntax-local-introduce`** for intentional variable capture
- **`local-expand`** for controlling macro expansion order
- **`free-identifier=?` / `bound-identifier=?`** for identifier comparison
- **Definition contexts** with inside/outside edge scopes

The parser has been fully migrated from raw CST (Concrete Syntax Tree) operations to syntax objects, establishing the foundation for the hygiene system throughout the compiler pipeline.

See [docs/internals/syntax-objects.md](docs/internals/syntax-objects.md) for implementation details.

### Delimited Continuations

A continuation-based computation type with classic control operators:

```
;; The Cont type wraps CPS computations
(define-type (Cont :r :a)
  (ContFn ((:a -> :r) -> :r)))

;; Control operators
(run-cont computation)           ;; Execute with identity continuation
(cont-reset body)                ;; Establish a reset delimiter
(cont-shift (fn (k) ...))       ;; Capture up to nearest reset
(cont-callcc (fn (k) ...))      ;; Call with current continuation
```

Includes a CPS standard library (`coalton-library/continuations`) with CPS-transformed versions of common operations: `cps-map`, `cps-fold`, `cps-filter`, `cps-find`, `cps-sequence`, `cps-compose`, and more.

### Algebraic Effects

> **Experimental** -- the effect system is architecturally complete but under active development.

An algebraic effect system with effect rows tracked in the type system:

```
;; Effect-annotated function types
(declare get (Unit -> :s ! (State :s)))
(declare put (:s -> Unit ! (State :s)))

;; Performing effects
(perform state.get)
(perform (state.put new-value))

;; Handling effects
(handle (computation)
  (state.get (resume)
    (resume current-state))
  (state.put (new-state resume)
    ...))
```

Built-in effects include **State**, **Reader**, and **Writer**. The runtime layer provides a trampoline-based async execution model with lightweight fibers, a cooperative scheduler, and structured concurrency primitives (`fork`, `await-fiber`, `race`, `with-scope`).

### Interactive REPL

A standalone REPL for evaluating Coalton expressions with type inference display:

```bash
./scripts/coalton-repl
```

```
coalton> (+ 1 2)
;; :: Integer
3

coalton> (fn (x) (+ x 1))
;; :: (Integer -> Integer)
#<FUNCTION ...>
```

Features:
- Type inference shown for every expression
- History navigation with arrow keys
- Persistent history (`~/.coalton_history`)
- `--ast` flag to display syntax trees
- `--no-type` flag to suppress type display
- Built-in line editor with no external dependencies

### coalton-run

Compile and execute Coalton source files from the command line:

```bash
./scripts/coalton-run myprogram.coal
```

Source files must begin with a `(package name)` header. If the package defines a `main` function, it is called automatically. Also accepts source from stdin:

```bash
echo '(package hello)
(define (main) (print "Hello, world!"))' | ./scripts/coalton-run
```

## Getting Started

> [!WARNING]
> This is an experimental fork. Features beyond upstream Coalton are under active development and APIs may change.

### With qlot (recommended for this fork)

This fork uses [qlot](https://github.com/fukamachi/qlot) for reproducible dependency management.

**Install qlot**: Follow [qlot installation instructions](https://github.com/fukamachi/qlot#installation).

**Install dependencies**:

```bash
git clone https://github.com/JulianChastain/coalton.git
cd coalton
qlot install
```

**Compile**:

```bash
qlot exec sbcl --noinform --non-interactive --eval "(asdf:load-system :coalton)"
```

**Run tests**:

```bash
# Full test suite
qlot exec sbcl --noinform --non-interactive --eval "(asdf:test-system :coalton/tests)"

# Parser/syntax-object tests only (faster)
qlot exec sbcl --noinform --non-interactive --load scripts/run-parser-tests.lisp
```

**Start a REPL**:

```bash
# CL REPL with Coalton loaded
qlot exec sbcl --eval "(asdf:load-system :coalton)"

# Coalton REPL (standalone)
./scripts/coalton-repl
```

### With Quicklisp (standard)

**Prepare**: Install [SBCL](http://www.sbcl.org/platform-table.html) (on macOS with Homebrew: `brew install sbcl`). Install Quicklisp by following instructions [here](https://www.quicklisp.org/beta/#installation).

**Install**: Clone this repository into `~/quicklisp/local-projects/`.

**Use**: Either run `(ql:quickload :coalton)`, or add `#:coalton` to your ASD's `:depends-on` list.

**Test**: Compile the tests with `(ql:quickload :coalton/tests)`, then run the tests with `(asdf:test-system :coalton)`.

> [!NOTE]
> Running the Coalton test suite on SBCL requires [GNU MPFR](https://www.mpfr.org/mpfr-current/mpfr.html#Installing-MPFR) in order to run `Big-Float` tests. If you would like to run tests without installing `gnu-mpfr`, you can use Coalton's portable `Big-Float` implementation by running `(pushnew :coalton-portable-bigfloat *features*)` before loading Coalton.

**Learn**: Start with [*Intro to Coalton*](docs/intro-to-coalton.md) and the [standard library reference](https://coalton-lang.github.io/reference/).

## What's Here?

This repository contains the source code to the [Coalton compiler](src/) and the [standard library](library/).

### Compiler Modules

| Directory | Description |
|-----------|-------------|
| `src/parser/` | Parser with syntax-object abstraction and hygienic macro infrastructure |
| `src/typechecker/` | Type checker with algebraic subtyping, constraint propagation, and effect rows |
| `src/codegen/` | Code generation targeting Common Lisp |
| `src/algorithm/` | Compiler algorithms (Tarjan SCC, immutable maps) |

### Library Modules

| Directory | Description |
|-----------|-------------|
| `library/` | Standard library (prelude, classes, collections, math, IO) |
| `library/continuations/` | Delimited continuations and CPS standard library |
| `library/effects/` | Algebraic effect definitions (State, Reader, Writer) |
| `library/effects/runtime/` | Effect runtime (trampoline, fibers, scheduler, structured concurrency) |

### Documentation

| Path | Description |
|------|-------------|
| `docs/intro-to-coalton.md` | Language introduction and tutorial |
| `docs/internals/design-docs/algebraic-subtyping.md` | Algebraic subtyping design document |
| `docs/internals/syntax-objects.md` | Syntax objects implementation status |
| `docs/internals/` | Additional internal design documents |

### Examples

- Some [simple pedagogical programs](examples/small-coalton-programs/)
- An [implementation](examples/thih/) of Jones's *Typing Haskell in Haskell*
- An [implementation](examples/quil-coalton/) of a simple [Quil](https://en.wikipedia.org/wiki/Quil_(instruction_set_architecture)) parser using parser combinators

## Upstream

This fork is based on [coalton-lang/coalton](https://github.com/coalton-lang/coalton). Upstream Coalton is used in production to build defense and [quantum computing software](https://coalton-lang.github.io/20220906-quantum-compiler/).
