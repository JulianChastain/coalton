(uiop:define-package #:coalton-impl/typechecker/stage-1
  (:mix-reexport
   #:coalton-impl/typechecker/base
   #:coalton-impl/typechecker/kinds
   #:coalton-impl/typechecker/types
   #:coalton-impl/typechecker/types-sub       ; Algebraic subtyping types
   #:coalton-impl/typechecker/substitutions
   #:coalton-impl/typechecker/predicate
   #:coalton-impl/typechecker/scheme
   #:coalton-impl/typechecker/type-errors
   #:coalton-impl/typechecker/unify
   #:coalton-impl/typechecker/constrain       ; Constraint propagation
   #:coalton-impl/typechecker/levels          ; Level-based let-poly
   #:coalton-impl/typechecker/simplify        ; Type simplification
   #:coalton-impl/typechecker/fundeps
   #:coalton-impl/typechecker/environment
   #:coalton-impl/typechecker/lisp-type
   #:coalton-impl/typechecker/context-reduction))
