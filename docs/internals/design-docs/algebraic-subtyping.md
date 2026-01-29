# Algebraic Subtyping (Simple-sub)

This document describes the implementation of algebraic subtyping in Coalton's type system, based on the Simple-sub algorithm from Parreaux (ICFP 2020).

## Overview

Coalton's type system extends Hindley-Milner type inference with algebraic subtyping. This allows:

1. **Constraint-based inference**: Instead of computing most general unifiers, the type checker propagates subtyping constraints
2. **Union and intersection types**: These emerge naturally during inference at positive and negative positions
3. **Top and bottom types**: ⊤ (top) is the supertype of all types; ⊥ (bottom) is the subtype of all types
4. **Level-based let-polymorphism**: Variables are generalized based on levels rather than free variable analysis

## Key Data Structures

### Type Variables with Bounds (tyvar-sub)

File: `src/typechecker/types-sub.lisp`

```lisp
(defstruct (tyvar-sub (:include ty))
  (id           fixnum)           ; unique identifier
  (kind         kind)             ; for higher-kinded types
  (level        fixnum)           ; for let-polymorphism
  (lower-bounds ty-list)          ; S where S <= this
  (upper-bounds ty-list))         ; U where this <= U
```

Unlike traditional type variables that get substituted during unification, `tyvar-sub` variables accumulate bounds during constraint propagation.

### Union and Intersection Types

```lisp
(defstruct (ty-union (:include ty))
  (members ty-list))

(defstruct (ty-intersection (:include ty))
  (members ty-list))

(defstruct (ty-top (:include ty)) (kind kind))
(defstruct (ty-bot (:include ty)) (kind kind))
```

- **Union types** appear in covariant (output) positions
- **Intersection types** appear in contravariant (input) positions
- **Top (⊤)** is the identity for intersections and absorbing for unions
- **Bottom (⊥)** is the identity for unions and absorbing for intersections

## Constraint Propagation

File: `src/typechecker/constrain.lisp`

The core operation is `constrain`, which enforces that one type is a subtype of another:

```lisp
(defun constrain (lhs rhs)
  "Enforce LHS <= RHS (lhs is subtype of rhs)"
  ...)
```

### Rules

1. **Reflexivity**: `T <= T` always holds
2. **Bottom**: `⊥ <= T` for any T
3. **Top**: `T <= ⊤` for any T
4. **Variable bounds**:
   - `α <= T` adds T as upper bound of α
   - `T <= α` adds T as lower bound of α
5. **Function types**: contravariant in argument, covariant in return
   - `(A → B) <= (C → D)` requires `C <= A` and `B <= D`
6. **Type constructors**: must match exactly (invariant)
7. **Type applications**: follows constructor variance (currently all covariant)

### Bound Propagation

When bounds are added to a variable, constraints are immediately propagated:

```lisp
(defun add-upper-bound (var bound)
  (push bound (tyvar-sub-upper-bounds var))
  ;; Propagate: for all lower bounds L, enforce L <= bound
  (dolist (lb (tyvar-sub-lower-bounds var))
    (constrain lb bound)))
```

This ensures the constraint graph remains consistent.

## Level-Based Let-Polymorphism

File: `src/typechecker/levels.lisp`

Variables are created at specific "levels" that correspond to let-binding depth:

```lisp
(defparameter *current-level* 0)

(defmacro with-new-level (&body body)
  `(let ((*current-level* (1+ *current-level*)))
     ,@body))

(defun make-variable-at-level (&optional (kind +kstar+))
  (make-tyvar-sub :level *current-level* ...))
```

### Generalization

Variables can only be generalized if they were created at a level higher than (or equal to) the current generalization level:

```lisp
(defun can-generalize-p (var)
  (and (tyvar-sub-p var)
       (>= (tyvar-sub-level var) *current-level*)))
```

This replaces the traditional "does not appear free in environment" check.

## Type Simplification

File: `src/typechecker/simplify.lisp`

After inference, types are simplified for readability and efficiency:

### Union/Intersection Simplification

```lisp
(defun simplify-union (members)
  ;; 1. Flatten nested unions
  ;; 2. Remove duplicates
  ;; 3. Remove ⊥ (identity element)
  ;; 4. If ⊤ present, return ⊤ (absorbing)
  ;; 5. If single element, return it directly
  ...)
```

### Sandwich Removal

When a variable has identical upper and lower bounds, it can be replaced:

```lisp
(defun sandwiched-type-p (var)
  "If VAR has bounds T <= var <= T for some T, return T."
  (let ((lbs (tyvar-sub-lower-bounds var))
        (ubs (tyvar-sub-upper-bounds var)))
    (when (and (= 1 (length lbs))
               (= 1 (length ubs))
               (ty= (first lbs) (first ubs)))
      (first lbs))))
```

### Polar Variable Removal

Variables that appear only in positive or only in negative position can be simplified:

- **Positive-only** (covariant): Replace with union of lower bounds
- **Negative-only** (contravariant): Replace with intersection of upper bounds

```lisp
(defun polar-variable-p (type var)
  "Return :POSITIVE, :NEGATIVE, or NIL based on where VAR appears in TYPE."
  ...)
```

## Integration with Type Classes

File: `src/typechecker/predicate.lisp`

Type class constraints interact with algebraic subtyping:

### Predicate Matching

The `match-sub` operation handles matching predicates when `tyvar-sub` variables are involved:

```lisp
(defun predicate-match-sub (pred1 pred2)
  "Match PRED1 against PRED2, adding constraints for tyvar-sub variables."
  (unless (eq (ty-predicate-class pred1) (ty-predicate-class pred2))
    (error 'predicate-unification-error ...))
  (mapcan #'match-sub
          (ty-predicate-types pred1)
          (ty-predicate-types pred2)))
```

### Context Reduction

File: `src/typechecker/context-reduction.lisp`

The `entail-sub` function checks entailment using subtyping constraints:

```lisp
(defun entail-sub (env preds pred)
  "Check if PRED is entailed by PREDS using subtyping constraints."
  ...)
```

## Backward Compatibility

The implementation maintains full backward compatibility with existing Coalton code:

1. Traditional `tyvar` variables still work via unification
2. Existing type class instances are preserved
3. All existing tests pass without modification
4. Standard library compiles unchanged

New `tyvar-sub` variables are used during inference but get simplified or generalized to traditional forms in the final type.

## Files Modified/Added

| File | Changes |
|------|---------|
| `src/typechecker/types-sub.lisp` | NEW: tyvar-sub, ty-union, ty-intersection, ty-top, ty-bot |
| `src/typechecker/constrain.lisp` | NEW: Constraint propagation |
| `src/typechecker/levels.lisp` | NEW: Level management |
| `src/typechecker/simplify.lisp` | NEW: Type simplification |
| `src/typechecker/scheme.lisp` | Level-based quantification |
| `src/typechecker/predicate.lisp` | predicate-match-sub support |
| `src/typechecker/context-reduction.lisp` | entail-sub, by-inst-sub |
| `src/typechecker/environment.lisp` | lookup-class-instance-sub |

## Glossary of Internal Terms

| Term | Definition |
|------|------------|
| **tyvar** | Traditional type variable that gets substituted during unification |
| **tyvar-sub** | Type variable with bounds; accumulates constraints during inference |
| **ty-union** | Union type (A ∨ B); value is one of the member types |
| **ty-intersection** | Intersection type (A ∧ B); value satisfies all member types |
| **ty-top (⊤)** | Top type; supertype of all types |
| **ty-bot (⊥)** | Bottom type; subtype of all types |
| **constrain** | Operation that enforces LHS ≤ RHS subtyping relation |
| **level** | Integer tracking let-binding depth for generalization |
| **polarity** | Whether a type position is covariant (+) or contravariant (-) |
| **sandwich** | Variable with identical upper and lower bounds (can be eliminated) |
| **extrusion** | When a variable escapes its creation scope via constraints |

## References

- Parreaux, L. "The Simple Essence of Algebraic Subtyping" (ICFP 2020)
- Dolan, S. "Algebraic Subtyping" (PhD thesis, 2017)
- `reports/simplesub.md` - Algorithm theory notes
- `reports/subtyping.md` - Type classes vs subtyping comparison
