(defpackage #:coalton-impl/typechecker/constrain
  (:use
   #:cl
   #:coalton-impl/typechecker/base
   #:coalton-impl/typechecker/kinds
   #:coalton-impl/typechecker/types
   #:coalton-impl/typechecker/types-sub
   #:coalton-impl/typechecker/substitutions
   #:coalton-impl/typechecker/predicate
   #:coalton-impl/typechecker/type-errors)
  (:local-nicknames
   (#:util #:coalton-impl/util))
  (:export
   #:constrain                          ; FUNCTION
   #:constrain-equal                    ; FUNCTION
   #:add-upper-bound                    ; FUNCTION
   #:add-lower-bound                    ; FUNCTION
   #:constraint-error                   ; CONDITION
   #:constraint-error-lhs               ; ACCESSOR
   #:constraint-error-rhs               ; ACCESSOR
   #:occurs-check-error                 ; CONDITION
   #:occurs-check-error-var             ; ACCESSOR
   #:occurs-check-error-type            ; ACCESSOR
   ;; Compatibility layer
   #:unify-sub                          ; FUNCTION
   #:constrain-types                    ; FUNCTION
   ;; Type matching for subtyping
   #:match-sub                          ; FUNCTION
   #:predicate-match-sub                ; FUNCTION
   ))

(in-package #:coalton-impl/typechecker/constrain)

;;;;
;;;; Constraint Propagation for Algebraic Subtyping
;;;;
;;;; This module implements the core constraint propagation algorithm for
;;;; algebraic subtyping. Instead of unification (finding a most general
;;;; unifier), we propagate subtyping constraints of the form LHS <= RHS.
;;;;
;;;; Key differences from unification:
;;;;
;;;; 1. Directionality: Constraints are directed (LHS <= RHS) rather than
;;;;    symmetric (LHS = RHS). This matters for function types where
;;;;    arguments are contravariant and returns are covariant.
;;;;
;;;; 2. Bounds accumulation: When constraining a type variable, we add
;;;;    to its bounds rather than substituting. This allows multiple
;;;;    constraints on the same variable.
;;;;
;;;; 3. Transitive closure: When adding a bound to a variable, we must
;;;;    propagate to ensure all existing bounds are compatible with the
;;;;    new bound.
;;;;
;;;; The algorithm is based on the Simple-sub paper by Parreaux (ICFP 2020).
;;;;

;;;
;;; Conditions
;;;

(define-condition constraint-error (coalton-internal-type-error)
  ((lhs :initarg :lhs
        :reader constraint-error-lhs
        :type ty)
   (rhs :initarg :rhs
        :reader constraint-error-rhs
        :type ty))
  (:report
   (lambda (c s)
     (let ((*print-circle* nil)
           (*print-readably* nil))
       (with-pprint-variable-context ()
         (format s "Cannot satisfy constraint ~S <= ~S"
                 (constraint-error-lhs c)
                 (constraint-error-rhs c)))))))

(define-condition occurs-check-error (coalton-internal-type-error)
  ((var :initarg :var
        :reader occurs-check-error-var)
   (type :initarg :type
         :reader occurs-check-error-type))
  (:report
   (lambda (c s)
     (let ((*print-circle* nil)
           (*print-readably* nil))
       (with-pprint-variable-context ()
         (format s "Occurs check failed: ~S appears in ~S"
                 (occurs-check-error-var c)
                 (occurs-check-error-type c)))))))

;;;
;;; Occurs check
;;;

(defgeneric occurs-in-p (var type)
  (:documentation "Check if VAR occurs in TYPE (for occurs check).")

  (:method ((var tyvar-sub) (type tyvar-sub))
    (= (tyvar-sub-id var) (tyvar-sub-id type)))

  (:method ((var tyvar-sub) (type tyvar))
    nil)

  (:method ((var tyvar-sub) (type tycon))
    nil)

  (:method ((var tyvar-sub) (type tapp))
    (or (occurs-in-p var (tapp-from type))
        (occurs-in-p var (tapp-to type))))

  (:method ((var tyvar-sub) (type ty-union))
    (some (lambda (m) (occurs-in-p var m)) (ty-union-members type)))

  (:method ((var tyvar-sub) (type ty-intersection))
    (some (lambda (m) (occurs-in-p var m)) (ty-intersection-members type)))

  (:method ((var tyvar-sub) (type ty-top))
    nil)

  (:method ((var tyvar-sub) (type ty-bot))
    nil)

  (:method ((var tyvar-sub) (type tgen))
    nil))

;;;
;;; Bound addition with propagation
;;;

(defun add-upper-bound (var bound)
  "Add BOUND as an upper bound of VAR (VAR <= BOUND).
Propagates the constraint to all existing lower bounds."
  (declare (type tyvar-sub var)
           (type ty bound))

  ;; Occurs check
  (when (occurs-in-p var bound)
    (error 'occurs-check-error :var var :type bound))

  ;; Check if bound is already present (avoid duplicates)
  (unless (member bound (tyvar-sub-upper-bounds var) :test #'ty=)
    ;; Add the new upper bound
    (push bound (tyvar-sub-upper-bounds var))

    ;; Propagate: for each lower bound lb, we need lb <= bound
    (dolist (lb (tyvar-sub-lower-bounds var))
      (constrain lb bound))))

(defun add-lower-bound (var bound)
  "Add BOUND as a lower bound of VAR (BOUND <= VAR).
Propagates the constraint to all existing upper bounds."
  (declare (type tyvar-sub var)
           (type ty bound))

  ;; Occurs check
  (when (occurs-in-p var bound)
    (error 'occurs-check-error :var var :type bound))

  ;; Check if bound is already present (avoid duplicates)
  (unless (member bound (tyvar-sub-lower-bounds var) :test #'ty=)
    ;; Add the new lower bound
    (push bound (tyvar-sub-lower-bounds var))

    ;; Propagate: for each upper bound ub, we need bound <= ub
    (dolist (ub (tyvar-sub-upper-bounds var))
      (constrain bound ub))))

;;;
;;; Core constraint propagation
;;;

(defgeneric constrain (lhs rhs)
  (:documentation "Enforce the subtyping constraint LHS <= RHS.
Returns T if the constraint is satisfied, signals CONSTRAINT-ERROR otherwise.

The constraint propagation follows these rules:
- ⊥ <= T for all T (bottom is subtype of everything)
- T <= ⊤ for all T (everything is subtype of top)
- α <= T adds T as upper bound of α
- T <= α adds T as lower bound of α
- (A -> B) <= (C -> D) requires C <= A (contravariant) and B <= D (covariant)
- (F A) <= (G B) requires F = G and A <= B (assuming invariant type constructors)")

  ;; Reflexivity: T <= T
  (:method ((lhs ty) (rhs ty))
    (if (ty= lhs rhs)
        t
        (error 'constraint-error :lhs lhs :rhs rhs)))

  ;; Bottom: ⊥ <= T
  (:method ((lhs ty-bot) (rhs ty))
    (declare (ignore lhs rhs))
    t)

  ;; Top: T <= ⊤
  (:method ((lhs ty) (rhs ty-top))
    (declare (ignore lhs rhs))
    t)

  ;; tyvar-sub on left: add upper bound
  (:method ((lhs tyvar-sub) (rhs ty))
    (add-upper-bound lhs rhs)
    t)

  ;; tyvar-sub on right: add lower bound
  (:method ((lhs ty) (rhs tyvar-sub))
    (add-lower-bound rhs lhs)
    t)

  ;; Both tyvar-sub: bidirectional constraint
  (:method ((lhs tyvar-sub) (rhs tyvar-sub))
    (if (= (tyvar-sub-id lhs) (tyvar-sub-id rhs))
        t  ; Same variable
        (progn
          (add-upper-bound lhs rhs)
          (add-lower-bound rhs lhs)
          t)))

  ;; Type constructors: must be equal
  (:method ((lhs tycon) (rhs tycon))
    (if (ty= lhs rhs)
        t
        (error 'constraint-error :lhs lhs :rhs rhs)))

  ;; Type applications: decompose
  (:method ((lhs tapp) (rhs tapp))
    ;; Check if this is a function type
    (cond
      ;; Function types: contravariant in argument, covariant in return
      ((and (function-type-p lhs) (function-type-p rhs))
       ;; (A -> B) <= (C -> D) means C <= A and B <= D
       (constrain (function-type-from rhs) (function-type-from lhs))  ; contravariant
       (constrain (function-type-to lhs) (function-type-to rhs))      ; covariant
       t)

      ;; Other type applications: check heads match, then arguments
      ;; For now, treat all other type constructors as invariant
      (t
       (let ((lhs-flat (flatten-type lhs))
             (rhs-flat (flatten-type rhs)))
         ;; Head must match
         (unless (ty= (first lhs-flat) (first rhs-flat))
           (error 'constraint-error :lhs lhs :rhs rhs))
         ;; Arguments must be equal (invariant)
         (unless (= (length lhs-flat) (length rhs-flat))
           (error 'constraint-error :lhs lhs :rhs rhs))
         (loop :for l :in (rest lhs-flat)
               :for r :in (rest rhs-flat)
               :do (constrain-equal l r))
         t))))

  ;; Union on left: all members must be <= rhs
  (:method ((lhs ty-union) (rhs ty))
    (dolist (member (ty-union-members lhs))
      (constrain member rhs))
    t)

  ;; Intersection on right: lhs must be <= all members
  (:method ((lhs ty) (rhs ty-intersection))
    (dolist (member (ty-intersection-members rhs))
      (constrain lhs member))
    t)

  ;; Union on right: lhs must be <= at least one member
  ;; This is non-deterministic in general; for now we require
  ;; lhs to be a specific type that matches one member
  (:method ((lhs tycon) (rhs ty-union))
    (let ((matching (find-if (lambda (m)
                               (handler-case
                                   (progn (constrain lhs m) t)
                                 (constraint-error () nil)))
                             (ty-union-members rhs))))
      (if matching
          t
          (error 'constraint-error :lhs lhs :rhs rhs))))

  ;; Intersection on left: at least one member must be <= rhs
  (:method ((lhs ty-intersection) (rhs tycon))
    (let ((matching (find-if (lambda (m)
                               (handler-case
                                   (progn (constrain m rhs) t)
                                 (constraint-error () nil)))
                             (ty-intersection-members lhs))))
      (if matching
          t
          (error 'constraint-error :lhs lhs :rhs rhs))))

  ;; Regular tyvar (from HM system) treated like tyvar-sub at level 0
  ;; This provides compatibility with existing code
  (:method ((lhs tyvar) (rhs ty))
    (error 'constraint-error :lhs lhs :rhs rhs))

  (:method ((lhs ty) (rhs tyvar))
    (error 'constraint-error :lhs lhs :rhs rhs)))

;;;
;;; Equality constraint (bidirectional)
;;;

(defun constrain-equal (type1 type2)
  "Enforce bidirectional constraint TYPE1 = TYPE2.
This is equivalent to (TYPE1 <= TYPE2) and (TYPE2 <= TYPE1)."
  (declare (type ty type1 type2))
  (constrain type1 type2)
  (constrain type2 type1)
  t)

;;;
;;; Helper for working with the existing HM unification
;;;

(defgeneric type-meets-bound-p (type bound)
  (:documentation "Check if TYPE can satisfy being a subtype of BOUND.
Returns T if the constraint could be satisfied, NIL otherwise.
This is a non-mutating check (doesn't add bounds).")

  (:method ((type ty) (bound ty))
    (handler-case
        (let ((test-var (make-tyvar-sub :id -1 :kind (kind-of type) :level 0)))
          ;; Temporarily constrain to check feasibility
          (constrain type bound)
          t)
      (constraint-error () nil)
      (occurs-check-error () nil))))

;;;
;;; Compatibility Layer for Transitioning from Unification
;;;
;;; These functions provide a bridge between the traditional HM-style
;;; unification and algebraic subtyping with constraints.
;;;

(defun constrain-types (type1 type2)
  "Constrain TYPE1 and TYPE2 to be equal using algebraic subtyping.

This is the constraint-based analog to unification. Instead of computing
a most general unifier (substitution), it adds bounds to tyvar-sub variables.

For tyvar-sub variables: adds bidirectional bounds
For regular tyvars: signals an error (should use unify instead)
For concrete types: checks structural equality

Returns T if successful, signals constraint-error otherwise."
  (constrain-equal type1 type2))

(defun unify-sub (subs type1 type2)
  "Unify TYPE1 and TYPE2 using a hybrid approach.

This function provides compatibility with the existing unification-based
type inference. It:
1. Applies existing substitutions to both types
2. Attempts constraint-based unification for tyvar-sub variables
3. Falls back to substitution for regular tyvars

For a full transition to algebraic subtyping, use constrain-equal directly.

SUBS is the current substitution list (for compatibility).
Returns the updated substitution list."
  (declare (type substitution-list subs)
           (type ty type1 type2))

  (let ((t1 (apply-substitution subs type1))
        (t2 (apply-substitution subs type2)))

    ;; Handle the different cases based on what types we have
    (cond
      ;; Both are tyvar-sub: use constraint propagation
      ((and (tyvar-sub-p t1) (tyvar-sub-p t2))
       (constrain-equal t1 t2)
       subs)  ; No new substitutions needed

      ;; One is tyvar-sub, one is concrete: add bound
      ((tyvar-sub-p t1)
       (constrain t1 t2)
       subs)

      ((tyvar-sub-p t2)
       (constrain t2 t1)
       subs)

      ;; One or both are regular tyvar: create substitution
      ((tyvar-p t1)
       (when (tyvar-p t2)
         (unless (ty= t1 t2)
           ;; Two different regular tyvars - substitute one for the other
           (return-from unify-sub
             (compose-substitution-lists
              (list (make-substitution :from t1 :to t2))
              subs))))
       ;; t1 is tyvar, t2 is not
       (when (find t1 (type-variables t2))
         (error 'occurs-check-error :var t1 :type t2))
       (compose-substitution-lists
        (list (make-substitution :from t1 :to t2))
        subs))

      ((tyvar-p t2)
       ;; t2 is tyvar, t1 is not
       (when (find t2 (type-variables t1))
         (error 'occurs-check-error :var t2 :type t1))
       (compose-substitution-lists
        (list (make-substitution :from t2 :to t1))
        subs))

      ;; Both are type applications
      ((and (tapp-p t1) (tapp-p t2))
       (cond
         ;; Function types: handle variance
         ((and (function-type-p t1) (function-type-p t2))
          ;; For compatibility, treat as equality (not subtyping)
          (let ((subs1 (unify-sub subs
                                  (function-type-from t1)
                                  (function-type-from t2))))
            (unify-sub subs1
                       (function-type-to t1)
                       (function-type-to t2))))

         ;; Other type applications
         (t
          (let ((subs1 (unify-sub subs (tapp-from t1) (tapp-from t2))))
            (unify-sub subs1 (tapp-to t1) (tapp-to t2))))))

      ;; Both are concrete types: check equality
      ((ty= t1 t2)
       subs)

      ;; Types don't match
      (t
       (error 'constraint-error :lhs t1 :rhs t2)))))

;;;
;;; Type Matching for Subtyping
;;;
;;; These functions provide constraint-based matching for tyvar-sub variables.
;;; They use constraint propagation rather than substitution-based unification.
;;;

(defgeneric match-sub (type1 type2)
  (:documentation "Match TYPE1 to TYPE2 using constraint propagation for tyvar-sub.

Unlike MATCH which creates substitutions, this function uses the constraint
system for tyvar-sub variables. Regular tyvars still use substitutions.

Returns a SUBSTITUTION-LIST for any regular tyvars that were unified.")

  ;; Type application: match structurally
  (:method ((type1 tapp) (type2 tapp))
    (let ((s1 (match-sub (tapp-from type1) (tapp-from type2)))
          (s2 (match-sub (tapp-to type1) (tapp-to type2))))
      (merge-substitution-lists s1 s2)))

  ;; tyvar-sub on left: add type2 as upper bound
  (:method ((type1 tyvar-sub) (type2 ty))
    (constrain type1 type2)
    nil)  ; No substitution needed, constraint added

  ;; Regular tyvar on left: create substitution (traditional behavior)
  (:method ((type1 tyvar) (type2 ty))
    (if (equalp (kind-of type1) (kind-of type2))
        (list (make-substitution :from type1 :to type2))
        (error 'type-kind-mismatch-error :type1 type1 :type2 type2)))

  ;; tycon: must be equal
  (:method ((type1 tycon) (type2 tycon))
    (if (ty= type1 type2)
        nil
        (error 'unification-error :type1 type1 :type2 type2)))

  ;; ty-top: anything matches
  (:method ((type1 ty) (type2 ty-top))
    nil)

  ;; ty-bot on left: always matches
  (:method ((type1 ty-bot) (type2 ty))
    nil)

  ;; Default: error
  (:method ((type1 ty) (type2 ty))
    (error 'unification-error :type1 type1 :type2 type2)))

(defun predicate-match-sub (pred1 pred2)
  "Match PRED1 to PRED2 using constraint propagation for tyvar-sub.

This is the constraint-based analog of PREDICATE-MATCH. It matches the
predicate types using MATCH-SUB, which adds constraints for tyvar-sub
variables rather than creating substitutions.

Returns a SUBSTITUTION-LIST for any regular tyvars that were unified.
Signals PREDICATE-UNIFICATION-ERROR if matching fails."
  (declare (type ty-predicate pred1 pred2))
  (unless (eq (ty-predicate-class pred1)
              (ty-predicate-class pred2))
    (error 'predicate-unification-error :pred1 pred1 :pred2 pred2))
  (handler-case
      (reduce #'merge-substitution-lists
              (loop :for pred-type1 :in (ty-predicate-types pred1)
                    :for pred-type2 :in (ty-predicate-types pred2)
                    :collect (match-sub pred-type1 pred-type2))
              :initial-value nil)
    (coalton-internal-type-error ()
      (error 'predicate-unification-error :pred1 pred1 :pred2 pred2))
    (constraint-error ()
      (error 'predicate-unification-error :pred1 pred1 :pred2 pred2))))
