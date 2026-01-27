---
name: coalton-dev
description: |
  Development workflow commands for the Coalton project using qlot dependency management.
  Use this skill when working on Coalton, especially for: installing dependencies, compiling,
  running tests, loading the system in a REPL, or any development task in this repository.

  This skill is editable - update it when you discover new useful commands or fix errors.
---

# Coalton Development Workflow

This project uses **qlot** for dependency management. All commands should be run from the project root.

## Quick Reference

| Task | Command |
|------|---------|
| Install dependencies | `qlot install` |
| Check compilation | `qlot exec sbcl --eval "(asdf:load-system :coalton)"` |
| Run all tests | `qlot exec sbcl --eval "(asdf:test-system :coalton/tests)"` |
| **Run parser tests (summary)** | `qlot exec sbcl --noinform --non-interactive --load scripts/run-parser-tests.lisp` |
| Run parser tests (verbose) | See [Running Specific Tests](#running-specific-tests) |
| Start REPL | `qlot exec sbcl` |
| Update dependencies | `qlot update` |

## Essential Commands

### Install Dependencies

```bash
qlot install
```

Run this after cloning the repo or when `qlfile` changes. Creates `.qlot/` directory with project-local Quicklisp.

### Check for Compilation Errors

```bash
qlot exec sbcl --noinform --non-interactive \
  --eval "(require :asdf)" \
  --eval "(asdf:load-system :coalton :verbose nil)" \
  --eval "(format t \"~&Coalton compiled successfully.~%\")"
```

### Start Interactive REPL

```bash
qlot exec sbcl
```

Then in the REPL:
```lisp
(asdf:load-system :coalton)
```

### Run All Tests

```bash
qlot exec sbcl --noinform --non-interactive \
  --eval "(asdf:test-system :coalton/tests)"
```

Note: This may fail on the thih-coalton example due to a known issue. Use parser-specific tests instead.

## Running Specific Tests

### Parser Tests with Summary Output (Recommended)

The `scripts/run-parser-tests.lisp` script runs all parser tests and outputs a compact summary showing total tests, passing tests, and names of any failing tests:

```bash
qlot exec sbcl --noinform --non-interactive --load scripts/run-parser-tests.lisp
```

Example output:
```
========================================
Parser Test Summary
========================================
Total:  237
Passed: 237
Failed: 0
========================================
```

The script returns exit code 0 on success, 1 on failure.

### Parser/Syntax Object Tests (Verbose)

Load fiasco first, then the test file, then run:

```bash
qlot exec sbcl --noinform --non-interactive \
  --eval "(require :asdf)" \
  --eval "(asdf:load-system :fiasco :verbose nil)" \
  --eval "(asdf:load-system :coalton :verbose nil)" \
  --eval "(load \"tests/parser/TESTFILE.lisp\")" \
  --eval "(fiasco:run-tests 'PACKAGE-NAME)"
```

### Available Parser Test Files

| Test File | Package Name |
|-----------|--------------|
| `scope-tests.lisp` | `coalton-impl/parser/scope-tests` |
| `syntax-object-tests.lisp` | `coalton-impl/parser/syntax-object-tests` |
| `binding-table-tests.lisp` | `coalton-impl/parser/binding-table-tests` |
| `syntax-cst-tests.lisp` | `coalton-impl/parser/syntax-cst-tests` |
| `hygienic-macro-tests.lisp` | `coalton-impl/parser/hygienic-macro-tests` |
| `hygienic-integration-tests.lisp` | `coalton-impl/parser/hygienic-integration-tests` |
| `syntax-case-tests.lisp` | `coalton/tests/parser/syntax-case-tests` |

### Example: Run syntax-case tests

```bash
qlot exec sbcl --noinform --non-interactive \
  --eval "(require :asdf)" \
  --eval "(asdf:load-system :fiasco :verbose nil)" \
  --eval "(asdf:load-system :coalton :verbose nil)" \
  --eval "(load \"tests/parser/syntax-case-tests.lisp\")" \
  --eval "(fiasco:run-tests 'coalton/tests/parser/syntax-case-tests)"
```

### Run All Parser Tests Together

**Preferred method** - use the summary script:
```bash
qlot exec sbcl --noinform --non-interactive --load scripts/run-parser-tests.lisp
```

**Verbose method** - shows each test result:
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
  --eval "(fiasco:run-tests '(coalton-impl/parser/scope-tests coalton-impl/parser/syntax-object-tests coalton-impl/parser/binding-table-tests coalton-impl/parser/syntax-cst-tests coalton-impl/parser/hygienic-macro-tests coalton-impl/parser/hygienic-integration-tests coalton/tests/parser/syntax-case-tests))"
```

## Dependency Management

### Update All Dependencies

```bash
qlot update
```

### Update Specific Dependency

```bash
qlot update <package-name>
```

### Add New Dependency

```bash
qlot add <package-name>
# Or from GitHub:
qlot add username/repo
```

### Clear and Reinstall

```bash
rm -rf .qlot qlfile.lock && qlot install
```

## Project Structure

Key files for syntax object implementation:

```
src/parser/
├── scope.lisp           # Scope tokens and sets
├── syntax-object.lisp   # Core syntax objects
├── binding-table.lisp   # Binding resolution
├── syntax-cst.lisp      # CST conversion utilities
├── macro.lisp           # Hygienic expansion (local-expand, syntax-local-value)
└── syntax-case.lisp     # Pattern matching

tests/parser/
├── scope-tests.lisp
├── syntax-object-tests.lisp
├── binding-table-tests.lisp
├── syntax-cst-tests.lisp
├── hygienic-macro-tests.lisp
├── hygienic-integration-tests.lisp
└── syntax-case-tests.lisp

scripts/
└── run-parser-tests.lisp  # Test runner with summary output
```

## Troubleshooting

### "Package X does not exist" error when loading tests

Ensure fiasco is loaded before loading test files:
```lisp
(asdf:load-system :fiasco :verbose nil)
```

### Tests loading from Quicklisp instead of local

Use `qlot exec` to ensure project-local dependencies are used.

### Compilation warnings about unused variables

Style warnings about unused bindings variables in syntax-case are expected and harmless.

---

**Maintainer Note:** This skill is self-updating. When you discover a useful command or fix an error, edit this file at `.claude/skills/coalton-dev/SKILL.md` to keep it current.
