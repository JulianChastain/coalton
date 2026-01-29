(defpackage #:coalton-impl/typechecker/types-sub
  (:use
   #:cl
   #:coalton-impl/typechecker/base
   #:coalton-impl/typechecker/kinds
   #:coalton-impl/typechecker/types)
  (:local-nicknames
   (#:util #:coalton-impl/util)
   (#:settings #:coalton-impl/settings)
   (#:scope #:coalton-impl/parser/scope))
  (:export
   ;; Type variable with bounds (for subtyping inference)
   #:tyvar-sub                          ; STRUCT
   #:make-tyvar-sub                     ; CONSTRUCTOR
   #:tyvar-sub-id                       ; ACCESSOR
   #:tyvar-sub-kind                     ; ACCESSOR
   #:tyvar-sub-level                    ; ACCESSOR
   #:tyvar-sub-lower-bounds             ; ACCESSOR
   #:tyvar-sub-upper-bounds             ; ACCESSOR
   #:tyvar-sub-scope-set                ; ACCESSOR (for hygienic type variables)
   #:tyvar-sub-p                        ; FUNCTION
   #:tyvar-sub-list                     ; TYPE
   ;; Union types
   #:ty-union                           ; STRUCT
   #:make-ty-union                      ; CONSTRUCTOR
   #:ty-union-members                   ; ACCESSOR
   #:ty-union-p                         ; FUNCTION
   ;; Intersection types
   #:ty-intersection                    ; STRUCT
   #:make-ty-intersection               ; CONSTRUCTOR
   #:ty-intersection-members            ; ACCESSOR
   #:ty-intersection-p                  ; FUNCTION
   ;; Top type (supertype of all types)
   #:ty-top                             ; STRUCT
   #:make-ty-top                        ; CONSTRUCTOR
   #:ty-top-kind                        ; ACCESSOR
   #:ty-top-p                           ; FUNCTION
   #:+ty-top+                           ; CONSTANT
   ;; Bottom type (subtype of all types)
   #:ty-bot                             ; STRUCT
   #:make-ty-bot                        ; CONSTRUCTOR
   #:ty-bot-kind                        ; ACCESSOR
   #:ty-bot-p                           ; FUNCTION
   #:+ty-bot+                           ; CONSTANT
   ))

(in-package #:coalton-impl/typechecker/types-sub)

;;;;
;;;; Algebraic Subtyping Type Extensions
;;;;
;;;; This module extends the core type system with structures needed for
;;;; algebraic subtyping (Simple-sub algorithm). The key additions are:
;;;;
;;;; - tyvar-sub: Type variables with explicit upper and lower bounds,
;;;;   plus a level for let-polymorphism. During inference, constraints
;;;;   are accumulated in bounds rather than applied as substitutions.
;;;;
;;;; - ty-union: Represents a union (join) of types. Emerges in positive
;;;;   (covariant) positions. A value of type (Union A B) can be either
;;;;   an A or a B.
;;;;
;;;; - ty-intersection: Represents an intersection (meet) of types.
;;;;   Emerges in negative (contravariant) positions. A value of type
;;;;   (Intersection A B) must satisfy both A and B.
;;;;
;;;; - ty-top: The top of the subtype lattice (⊤). Every type is a
;;;;   subtype of top.
;;;;
;;;; - ty-bot: The bottom of the subtype lattice (⊥). Bot is a subtype
;;;;   of every type.
;;;;

;;;
;;; Type variable with bounds
;;;

(defstruct (tyvar-sub (:include ty))
  "A type variable with explicit subtyping bounds.

During type inference with algebraic subtyping, constraints of the form
S <= α and α <= U are accumulated rather than immediately solved. The
LOWER-BOUNDS list contains all types S such that S <= α, and UPPER-BOUNDS
contains all types U such that α <= U.

The LEVEL field is used for let-polymorphism: variables at outer levels
can be generalized, while variables at inner levels must be constrained
or extruded to outer levels.

The SCOPE-SET field is used for hygienic type variable binding in macros.
Type variables with different scope sets are distinct, even if they have
the same symbolic name. This prevents accidental type variable capture.

ID is a unique identifier for the variable.
KIND is the kind of the type variable (usually * for regular types)."
  (id           (util:required 'id)    :type fixnum    :read-only t)
  (kind         (util:required 'kind)  :type kind      :read-only t)
  (level        (util:required 'level) :type fixnum    :read-only t)
  ;; Bounds are mutable - they accumulate during constraint propagation
  (lower-bounds nil                    :type ty-list   :read-only nil)
  (upper-bounds nil                    :type ty-list   :read-only nil)
  ;; Scope set for hygienic type variable binding (immutable)
  (scope-set    (scope:empty-scope-set) :type scope:scope-set :read-only t))

(defun tyvar-sub-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'tyvar-sub-p x)))

(deftype tyvar-sub-list ()
  '(satisfies tyvar-sub-list-p))

;;;
;;; Union types
;;;

(defstruct (ty-union (:include ty))
  "A union (join) type representing the least upper bound of its members.

A value of type (Union A B) is either a value of type A or a value of type B.
Union types arise from:
1. Combining lower bounds of a type variable
2. Conditional expressions with different branch types
3. Merging flows at join points

The MEMBERS list should contain at least two types. Single-member unions
are simplified to the member itself. Empty unions are equivalent to ty-bot."
  (members (util:required 'members) :type ty-list :read-only t))

;;;
;;; Intersection types
;;;

(defstruct (ty-intersection (:include ty))
  "An intersection (meet) type representing the greatest lower bound of its members.

A value of type (Intersection A B) must satisfy both type A and type B.
Intersection types arise from:
1. Combining upper bounds of a type variable
2. Function types in contravariant positions
3. Overloaded or refined types

The MEMBERS list should contain at least two types. Single-member intersections
are simplified to the member itself. Empty intersections are equivalent to ty-top."
  (members (util:required 'members) :type ty-list :read-only t))

;;;
;;; Top type
;;;

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct (ty-top (:include ty))
    "The top type (⊤) - the supertype of all types.

Every type T satisfies T <= ⊤. Top is the identity for intersection:
(Intersection T ⊤) = T, and the annihilator for union: (Union T ⊤) = ⊤.

Top represents \"any type\" or \"unknown type\" and arises when:
1. A variable has no upper bounds
2. An intersection type has no members
3. A type is never actually used (purely negative)

KIND specifies what kind of types this is the top of (usually +kstar+)."
    (kind +kstar+ :type kind :read-only t)))

(alexandria:define-constant +ty-top+
    (make-ty-top :kind +kstar+)
  :test #'equalp
  :documentation "The canonical top type for kind *.")

;;;
;;; Bottom type
;;;

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct (ty-bot (:include ty))
    "The bottom type (⊥) - the subtype of all types.

For every type T, we have ⊥ <= T. Bot is the identity for union:
(Union T ⊥) = T, and the annihilator for intersection: (Intersection T ⊥) = ⊥.

Bottom represents an impossible or uninhabited type and arises when:
1. A variable has no lower bounds
2. A union type has no members
3. A function never returns (diverges)

KIND specifies what kind of types this is the bottom of (usually +kstar+)."
    (kind +kstar+ :type kind :read-only t)))

(alexandria:define-constant +ty-bot+
    (make-ty-bot :kind +kstar+)
  :test #'equalp
  :documentation "The canonical bottom type for kind *.")

;;;
;;; Methods for new type structures
;;;

(defmethod kind-of ((type tyvar-sub))
  (tyvar-sub-kind type))

(defmethod kind-of ((type ty-union))
  ;; Union of types must all have the same kind
  (if (ty-union-members type)
      (kind-of (first (ty-union-members type)))
      +kstar+))

(defmethod kind-of ((type ty-intersection))
  ;; Intersection of types must all have the same kind
  (if (ty-intersection-members type)
      (kind-of (first (ty-intersection-members type)))
      +kstar+))

(defmethod kind-of ((type ty-top))
  (ty-top-kind type))

(defmethod kind-of ((type ty-bot))
  (ty-bot-kind type))

;;;
;;; Type equality for new types
;;;

(defmethod ty= ((type1 tyvar-sub) (type2 tyvar-sub))
  "Two tyvar-sub are equal if they have the same ID and the same scope set.
The scope set check enables hygienic type variable binding in macros."
  (and (= (tyvar-sub-id type1) (tyvar-sub-id type2))
       (scope:scope-set-equal (tyvar-sub-scope-set type1)
                              (tyvar-sub-scope-set type2))))

(defmethod ty= ((type1 ty-top) (type2 ty-top))
  (equalp (ty-top-kind type1) (ty-top-kind type2)))

(defmethod ty= ((type1 ty-bot) (type2 ty-bot))
  (equalp (ty-bot-kind type1) (ty-bot-kind type2)))

(defmethod ty= ((type1 ty-union) (type2 ty-union))
  ;; Union equality: same members (order-independent)
  (let ((m1 (ty-union-members type1))
        (m2 (ty-union-members type2)))
    (and (= (length m1) (length m2))
         (every (lambda (t1)
                  (some (lambda (t2) (ty= t1 t2)) m2))
                m1))))

(defmethod ty= ((type1 ty-intersection) (type2 ty-intersection))
  ;; Intersection equality: same members (order-independent)
  (let ((m1 (ty-intersection-members type1))
        (m2 (ty-intersection-members type2)))
    (and (= (length m1) (length m2))
         (every (lambda (t1)
                  (some (lambda (t2) (ty= t1 t2)) m2))
                m1))))

;;;
;;; Type variables extraction
;;;

(defmethod type-variables ((type tyvar-sub))
  ;; tyvar-sub is itself a type variable, but also contains bounds
  ;; that may have type variables
  (remove-duplicates
   (cons type
         (append (mapcan #'type-variables (tyvar-sub-lower-bounds type))
                 (mapcan #'type-variables (tyvar-sub-upper-bounds type))))
   :test #'equalp
   :from-end t))

(defmethod type-variables ((type ty-union))
  (remove-duplicates
   (mapcan #'type-variables (ty-union-members type))
   :test #'equalp
   :from-end t))

(defmethod type-variables ((type ty-intersection))
  (remove-duplicates
   (mapcan #'type-variables (ty-intersection-members type))
   :test #'equalp
   :from-end t))

(defmethod type-variables ((type ty-top))
  nil)

(defmethod type-variables ((type ty-bot))
  nil)

;;;
;;; Kind substitution application
;;;

(defmethod apply-ksubstitution (subs (type tyvar-sub))
  (make-tyvar-sub
   :alias (mapcar (lambda (alias) (apply-ksubstitution subs alias)) (ty-alias type))
   :id (tyvar-sub-id type)
   :kind (apply-ksubstitution subs (tyvar-sub-kind type))
   :level (tyvar-sub-level type)
   :lower-bounds (mapcar (lambda (b) (apply-ksubstitution subs b))
                         (tyvar-sub-lower-bounds type))
   :upper-bounds (mapcar (lambda (b) (apply-ksubstitution subs b))
                         (tyvar-sub-upper-bounds type))
   :scope-set (tyvar-sub-scope-set type)))

(defmethod apply-ksubstitution (subs (type ty-union))
  (make-ty-union
   :alias (mapcar (lambda (alias) (apply-ksubstitution subs alias)) (ty-alias type))
   :members (mapcar (lambda (m) (apply-ksubstitution subs m))
                    (ty-union-members type))))

(defmethod apply-ksubstitution (subs (type ty-intersection))
  (make-ty-intersection
   :alias (mapcar (lambda (alias) (apply-ksubstitution subs alias)) (ty-alias type))
   :members (mapcar (lambda (m) (apply-ksubstitution subs m))
                    (ty-intersection-members type))))

(defmethod apply-ksubstitution (subs (type ty-top))
  (make-ty-top
   :alias (mapcar (lambda (alias) (apply-ksubstitution subs alias)) (ty-alias type))
   :kind (apply-ksubstitution subs (ty-top-kind type))))

(defmethod apply-ksubstitution (subs (type ty-bot))
  (make-ty-bot
   :alias (mapcar (lambda (alias) (apply-ksubstitution subs alias)) (ty-alias type))
   :kind (apply-ksubstitution subs (ty-bot-kind type))))

;;;
;;; Kind variables extraction
;;;

(defmethod kind-variables-generic% ((type tyvar-sub))
  (append
   (kind-variables-generic% (tyvar-sub-kind type))
   (mapcan #'kind-variables-generic% (tyvar-sub-lower-bounds type))
   (mapcan #'kind-variables-generic% (tyvar-sub-upper-bounds type))))

(defmethod kind-variables-generic% ((type ty-union))
  (mapcan #'kind-variables-generic% (ty-union-members type)))

(defmethod kind-variables-generic% ((type ty-intersection))
  (mapcan #'kind-variables-generic% (ty-intersection-members type)))

(defmethod kind-variables-generic% ((type ty-top))
  (kind-variables-generic% (ty-top-kind type)))

(defmethod kind-variables-generic% ((type ty-bot))
  (kind-variables-generic% (ty-bot-kind type)))

;;;
;;; Type instantiation
;;;

(defmethod instantiate (types (type tyvar-sub))
  ;; tyvar-sub should not normally be instantiated, but handle it gracefully
  type)

(defmethod instantiate (types (type ty-union))
  (make-ty-union
   :alias (mapcar (lambda (alias) (instantiate types alias)) (ty-alias type))
   :members (mapcar (lambda (m) (instantiate types m)) (ty-union-members type))))

(defmethod instantiate (types (type ty-intersection))
  (make-ty-intersection
   :alias (mapcar (lambda (alias) (instantiate types alias)) (ty-alias type))
   :members (mapcar (lambda (m) (instantiate types m)) (ty-intersection-members type))))

(defmethod instantiate (types (type ty-top))
  type)

(defmethod instantiate (types (type ty-bot))
  type)

;;;
;;; Pretty printing
;;;

(defun pprint-tyvar-sub (stream type)
  (declare (type stream stream)
           (type tyvar-sub type))
  (if *coalton-pretty-print-tyvars*
      ;; Print the tvar using the current printing context
      (pprint-ty stream (pprint-tvar-sub type))
      (progn
        (write-string "#S" stream)
        (write (tyvar-sub-id type) :stream stream)
        (write-char #\@ stream)
        (write (tyvar-sub-level type) :stream stream))))

(defun pprint-tvar-sub (tvar)
  "Pretty print a tyvar-sub, reusing the tyvar dict mechanism."
  (unless (boundp '*pprint-tyvar-dict*)
    (util:coalton-bug "Unable to pretty print tyvar-sub outside pprint variable context"))
  (let ((value (gethash (tyvar-sub-id tvar) *pprint-tyvar-dict*)))
    (or value
        (setf (gethash (tyvar-sub-id tvar) *pprint-tyvar-dict*)
              (next-pprint-variable-as-tvar)))))

(defun pprint-ty-union (stream type)
  (declare (type stream stream)
           (type ty-union type))
  (write-string "(Union" stream)
  (dolist (member (ty-union-members type))
    (write-char #\space stream)
    (pprint-ty stream member))
  (write-char #\) stream))

(defun pprint-ty-intersection (stream type)
  (declare (type stream stream)
           (type ty-intersection type))
  (write-string "(Intersection" stream)
  (dolist (member (ty-intersection-members type))
    (write-char #\space stream)
    (pprint-ty stream member))
  (write-char #\) stream))

(defun pprint-ty-top (stream type)
  (declare (type stream stream)
           (type ty-top type)
           (ignore type))
  (write-string (if settings:*coalton-print-unicode* "⊤" "Top") stream))

(defun pprint-ty-bot (stream type)
  (declare (type stream stream)
           (type ty-bot type)
           (ignore type))
  (write-string (if settings:*coalton-print-unicode* "⊥" "Bot") stream))

(defmethod print-object ((type tyvar-sub) stream)
  (if *print-readably*
      (call-next-method)
      (pprint-tyvar-sub stream type)))

(defmethod print-object ((type ty-union) stream)
  (if *print-readably*
      (call-next-method)
      (pprint-ty-union stream type)))

(defmethod print-object ((type ty-intersection) stream)
  (if *print-readably*
      (call-next-method)
      (pprint-ty-intersection stream type)))

(defmethod print-object ((type ty-top) stream)
  (if *print-readably*
      (call-next-method)
      (pprint-ty-top stream type)))

(defmethod print-object ((type ty-bot) stream)
  (if *print-readably*
      (call-next-method)
      (pprint-ty-bot stream type)))

;;;
;;; Integration with pprint-ty
;;;
;;; These methods allow the new subtyping types to be printed by
;;; the core pprint-ty function through pprint-ty-extended.
;;;

(defmethod pprint-ty-extended (stream (type tyvar-sub))
  (pprint-tyvar-sub stream type))

(defmethod pprint-ty-extended (stream (type ty-union))
  (pprint-ty-union stream type))

(defmethod pprint-ty-extended (stream (type ty-intersection))
  (pprint-ty-intersection stream type))

(defmethod pprint-ty-extended (stream (type ty-top))
  (pprint-ty-top stream type))

(defmethod pprint-ty-extended (stream (type ty-bot))
  (pprint-ty-bot stream type))
