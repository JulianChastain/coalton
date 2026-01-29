(defpackage #:coalton-impl/typechecker/levels
  (:use
   #:cl
   #:coalton-impl/typechecker/base
   #:coalton-impl/typechecker/kinds
   #:coalton-impl/typechecker/types
   #:coalton-impl/typechecker/types-sub)
  (:local-nicknames
   (#:util #:coalton-impl/util))
  (:export
   #:*current-level*                    ; PARAMETER
   #:with-new-level                     ; MACRO
   #:make-variable-at-level             ; FUNCTION
   #:make-variable-at-current-level     ; FUNCTION
   #:extrude                            ; FUNCTION
   #:generalize-at-level                ; FUNCTION
   #:can-generalize-p                   ; FUNCTION
   #:reset-levels                       ; FUNCTION
   ))

(in-package #:coalton-impl/typechecker/levels)

;;;;
;;;; Level-Based Let-Polymorphism
;;;;
;;;; This module implements level-based tracking for let-polymorphism in the
;;;; Simple-sub algorithm. Levels are used to determine which type variables
;;;; can be generalized (made polymorphic) when leaving a let-binding scope.
;;;;
;;;; The key insight is that a type variable can only be generalized if it
;;;; was created at a level that is about to be exited. Variables at outer
;;;; levels are still "in use" and cannot be generalized.
;;;;
;;;; Levels work as follows:
;;;; - Level 0 is the outermost (global) level
;;;; - Each let-binding increases the level by 1
;;;; - Type variables remember the level at which they were created
;;;; - When exiting a let-scope, variables at that level can be generalized
;;;; - Variables that escape to outer levels must be "extruded"
;;;;
;;;; Extrusion occurs when a type variable at level N appears in a type that
;;;; escapes to level N-1 or lower. The variable must be lowered to the
;;;; escaping level to maintain soundness.
;;;;

;;;
;;; Level tracking
;;;

(defparameter *current-level* 0
  "The current nesting level for let-polymorphism.
Level 0 is the outermost (global) level. Each let-binding scope increases
the level by 1.")

#+sbcl
(declaim (sb-ext:always-bound *current-level*))

(defparameter *next-sub-var-id* 0
  "Counter for generating unique tyvar-sub IDs.")

#+sbcl
(declaim (sb-ext:always-bound *next-sub-var-id*))

(defun reset-levels ()
  "Reset the level counter and variable ID counter.
Primarily useful for testing."
  (setf *current-level* 0)
  (setf *next-sub-var-id* 0))

;;;
;;; Level scope management
;;;

(defmacro with-new-level (() &body body)
  "Execute BODY at an increased level for let-polymorphism.

Type variables created within this scope will have a higher level than
those outside. When the scope exits, variables at this level can be
generalized if they don't escape.

Example:
  (with-new-level ()
    ;; Variables created here have level N+1
    (let ((x-type (make-variable-at-current-level)))
      ;; Type inference for let-bound expression
      ...))
  ;; Back at level N; x-type could be generalized"
  `(let ((*current-level* (1+ *current-level*)))
     ,@body))

;;;
;;; Variable creation at levels
;;;

(declaim (ftype (function (&optional kind fixnum) tyvar-sub) make-variable-at-level))
(defun make-variable-at-level (&optional (kind +kstar+) (level *current-level*))
  "Create a fresh type variable with bounds at the specified level.

KIND defaults to +kstar+ for concrete types.
LEVEL defaults to the current level (*current-level*).

The returned tyvar-sub has:
- A globally unique ID
- The specified kind
- The specified level
- Empty lower and upper bounds"
  (prog1 (make-tyvar-sub
          :id *next-sub-var-id*
          :kind kind
          :level level
          :lower-bounds nil
          :upper-bounds nil)
    (incf *next-sub-var-id*)))

(declaim (inline make-variable-at-current-level))
(defun make-variable-at-current-level (&optional (kind +kstar+))
  "Create a fresh type variable at the current level.
Shorthand for (make-variable-at-level kind *current-level*)."
  (make-variable-at-level kind *current-level*))

;;;
;;; Level checking
;;;

(defun can-generalize-p (var &optional (target-level (1- *current-level*)))
  "Check if VAR can be generalized when exiting to TARGET-LEVEL.

A type variable can be generalized if:
1. Its level is greater than the target level
2. It does not appear in any type that escapes to an outer level

This is a simple check based on level; full escape analysis may
require examining the bounds and usage context."
  (declare (type tyvar-sub var)
           (type fixnum target-level))
  (> (tyvar-sub-level var) target-level))

;;;
;;; Extrusion
;;;

(defgeneric extrude (type target-level)
  (:documentation "Extrude TYPE to TARGET-LEVEL.

When a type escapes from a let-binding scope to an outer level, any type
variables at the inner level must be 'extruded' - their level is lowered
to the target level so they can appear in the outer scope.

This is necessary because a variable at level N cannot be generalized if
it appears in a type that escapes to level N-1. The extrusion operation
ensures the type system remains sound.

Returns the extruded type (which may be the same object if no extrusion
was needed).")

  (:method ((type tyvar-sub) target-level)
    (if (<= (tyvar-sub-level type) target-level)
        ;; Already at or below target level
        type
        ;; Need to extrude: create a new variable at lower level
        ;; and propagate bounds
        (let ((extruded (make-variable-at-level (tyvar-sub-kind type) target-level)))
          ;; Copy bounds, extruding them as well
          (dolist (lb (tyvar-sub-lower-bounds type))
            (push (extrude lb target-level) (tyvar-sub-lower-bounds extruded)))
          (dolist (ub (tyvar-sub-upper-bounds type))
            (push (extrude ub target-level) (tyvar-sub-upper-bounds extruded)))
          extruded)))

  (:method ((type tyvar) target-level)
    (declare (ignore target-level))
    ;; Regular tyvars don't have levels
    type)

  (:method ((type tycon) target-level)
    (declare (ignore target-level))
    type)

  (:method ((type tapp) target-level)
    (let ((from-extruded (extrude (tapp-from type) target-level))
          (to-extruded (extrude (tapp-to type) target-level)))
      (if (and (eq from-extruded (tapp-from type))
               (eq to-extruded (tapp-to type)))
          type  ; No change needed
          (make-tapp :from from-extruded :to to-extruded))))

  (:method ((type ty-union) target-level)
    (let ((extruded-members (mapcar (lambda (m) (extrude m target-level))
                                    (ty-union-members type))))
      (if (every #'eq extruded-members (ty-union-members type))
          type
          (make-ty-union :members extruded-members))))

  (:method ((type ty-intersection) target-level)
    (let ((extruded-members (mapcar (lambda (m) (extrude m target-level))
                                    (ty-intersection-members type))))
      (if (every #'eq extruded-members (ty-intersection-members type))
          type
          (make-ty-intersection :members extruded-members))))

  (:method ((type ty-top) target-level)
    (declare (ignore target-level))
    type)

  (:method ((type ty-bot) target-level)
    (declare (ignore target-level))
    type)

  (:method ((type tgen) target-level)
    (declare (ignore target-level))
    type))

;;;
;;; Generalization
;;;

(defun collect-generalizable-vars (type &optional (target-level (1- *current-level*)))
  "Collect all type variables in TYPE that can be generalized when exiting to TARGET-LEVEL."
  (declare (type ty type)
           (type fixnum target-level))
  (remove-duplicates
   (remove-if-not
    (lambda (var)
      (and (tyvar-sub-p var)
           (can-generalize-p var target-level)))
    (type-variables type))
   :test #'eq))

(defun generalize-at-level (type &optional (target-level (1- *current-level*)))
  "Prepare TYPE for generalization when exiting to TARGET-LEVEL.

This function:
1. Identifies type variables that can be generalized
2. Returns a list of these variables along with the type

The actual conversion to a ty-scheme with tgen variables is handled
elsewhere (in scheme.lisp or equivalent), as it may need to interact
with predicate handling.

Returns (VALUES TYPE GENERALIZABLE-VARS) where GENERALIZABLE-VARS is
a list of tyvar-sub that can be universally quantified."
  (declare (type ty type)
           (type fixnum target-level))
  (let ((vars (collect-generalizable-vars type target-level)))
    (values type vars)))
