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
| Check compilation | `qlot exec sbcl --noinform --non-interactive --eval "(asdf:load-system :coalton)"` |
| Run all tests | `qlot exec sbcl --noinform --non-interactive --eval "(asdf:test-system :coalton/tests)"` |
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
  --eval "(asdf:load-system :coalton)" \
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

The script returns exit code 0 on success, 1 on failure.

### Parser/Syntax Object Tests 
```bash
qlot exec sbcl --noinform --non-interactive --load scripts/run-parser-tests.lisp
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

**Maintainer Note:** This skill is self-updating. When you discover a useful command or fix an error, edit this file at `.claude/skills/coalton-dev/SKILL.md` to keep it current.
