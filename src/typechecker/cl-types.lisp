(defpackage #:coalton-impl/typechecker/cl-types
  (:use
   #:cl
   #:coalton-impl/typechecker/base
   #:coalton-impl/typechecker/kinds
   #:coalton-impl/typechecker/types
   #:coalton-impl/typechecker/types-sub)
  (:local-nicknames
   (#:util #:coalton-impl/util)
   (#:settings #:coalton-impl/settings))
  (:export
   ;; CL type wrapper
   #:ty-cl-type                           ; STRUCT
   #:make-ty-cl-type                      ; CONSTRUCTOR
   #:ty-cl-type-p                         ; PREDICATE
   #:ty-cl-type-specifier                 ; ACCESSOR
   #:ty-cl-type-normalized-p              ; ACCESSOR
   ;; Conversion functions
   #:cl-type->ty                          ; FUNCTION
   #:ty->cl-type                          ; FUNCTION
   ;; Subtype checking
   #:cl-subtype-p                         ; FUNCTION
   #:cl-types-disjoint-p                  ; FUNCTION
   ;; Type registry
   #:register-cl-type                     ; FUNCTION
   #:lookup-cl-type                       ; FUNCTION
   #:lookup-coalton-type                  ; FUNCTION
   ))

(in-package #:coalton-impl/typechecker/cl-types)

;;;;
;;;; Common Lisp Type System Interface
;;;;
;;;; This module provides an interface between Common Lisp's native type
;;;; system and Coalton's algebraic subtyping infrastructure. It enables
;;;; CL compound types like (or integer string), (and number (satisfies evenp)),
;;;; and (array element-type dimensions) to participate in Coalton's
;;;; constraint-based type inference.
;;;;
;;;; Key design principle:
;;;; - CL types that have direct Coalton equivalents (t, nil, or, and) are
;;;;   converted to their algebraic counterparts (ty-top, ty-bot, ty-union,
;;;;   ty-intersection)
;;;; - Other CL types (satisfies, member, array, etc.) are wrapped as
;;;;   opaque ty-cl-type structures
;;;; - Subtype relationships are computed using cl:subtypep
;;;;

;;;
;;; Type Registry
;;;
;;; Bidirectional mapping between known Coalton types and CL type specifiers.
;;; This allows efficient conversion for common types without creating
;;; ty-cl-type wrappers.
;;;

(defvar *cl-to-coalton-types* (make-hash-table :test 'equal)
  "Map from CL type specifier to Coalton type.")

(defvar *coalton-to-cl-types* (make-hash-table :test 'equalp)
  "Map from Coalton type name to CL type specifier.")

(defun register-cl-type (cl-specifier coalton-type)
  "Register a bidirectional mapping between CL-SPECIFIER and COALTON-TYPE."
  (setf (gethash cl-specifier *cl-to-coalton-types*) coalton-type)
  (when (tycon-p coalton-type)
    (setf (gethash (tycon-name coalton-type) *coalton-to-cl-types*) cl-specifier)))

(defun lookup-cl-type (cl-specifier)
  "Look up a Coalton type for the given CL-SPECIFIER.
Returns NIL if no mapping exists."
  (gethash cl-specifier *cl-to-coalton-types*))

(defun lookup-coalton-type (coalton-type)
  "Look up a CL type specifier for the given COALTON-TYPE.
Returns NIL if no mapping exists."
  (when (tycon-p coalton-type)
    (gethash (tycon-name coalton-type) *coalton-to-cl-types*)))

;; Initialize common type mappings
(defun initialize-type-registry ()
  "Initialize the type registry with built-in type mappings."
  ;; Clear existing mappings
  (clrhash *cl-to-coalton-types*)
  (clrhash *coalton-to-cl-types*)

  ;; Register primitive types
  (register-cl-type 'cl:integer *integer-type*)
  (register-cl-type 'cl:string *string-type*)
  (register-cl-type 'cl:character *char-type*)
  (register-cl-type 'cl:single-float *single-float-type*)
  (register-cl-type 'cl:double-float *double-float-type*)
  (register-cl-type 'cl:fixnum *ifix-type*)

  ;; Register Boolean (maps to generalized boolean in CL)
  ;; Note: CL doesn't have a dedicated boolean type
  )

;; Initialize on load
(initialize-type-registry)

;;;
;;; CL Type Wrapper Structure
;;;

(defstruct (ty-cl-type (:include ty))
  "A Common Lisp type specifier wrapped as a Coalton algebraic type.

This structure allows CL compound types to participate in Coalton's
type inference. The SPECIFIER field holds the original CL type specifier,
which can be:
- A symbol (e.g., INTEGER, STRING)
- A compound type (e.g., (SATISFIES EVENP), (MEMBER :A :B))
- A parameterized type (e.g., (ARRAY INTEGER 2))

NORMALIZED-P indicates whether the specifier has been normalized
(e.g., expanded type aliases, simplified redundant constructs).

Subtype relationships are computed using cl:subtypep, which may return
indeterminate results for certain type combinations. Such cases are
handled conservatively."
  (specifier    (util:required 'specifier) :type t       :read-only t)
  (normalized-p nil                        :type boolean :read-only t))

;;;
;;; Methods for ty-cl-type
;;;

(defmethod kind-of ((type ty-cl-type))
  "CL types are always of kind * (they represent value types)."
  +kstar+)

(defmethod ty= ((type1 ty-cl-type) (type2 ty-cl-type))
  "Two ty-cl-type are equal if their specifiers are equivalent.
Uses cl:subtypep for semantic equality."
  (let ((spec1 (ty-cl-type-specifier type1))
        (spec2 (ty-cl-type-specifier type2)))
    ;; Types are equal if each is a subtype of the other
    (multiple-value-bind (sub1-p valid1-p)
        (cl:subtypep spec1 spec2)
      (multiple-value-bind (sub2-p valid2-p)
          (cl:subtypep spec2 spec1)
        (and valid1-p valid2-p sub1-p sub2-p)))))

(defmethod type-variables ((type ty-cl-type))
  "CL types contain no type variables."
  nil)

(defmethod apply-ksubstitution (subs (type ty-cl-type))
  "Kind substitutions have no effect on CL types."
  type)

(defmethod kind-variables-generic% ((type ty-cl-type))
  "CL types have no kind variables."
  nil)

(defmethod instantiate (types (type ty-cl-type))
  "CL types cannot be instantiated (no type parameters)."
  type)

;;;
;;; Pretty Printing
;;;

(defun pprint-ty-cl-type (stream type)
  "Pretty print a ty-cl-type."
  (declare (type stream stream)
           (type ty-cl-type type))
  (let ((spec (ty-cl-type-specifier type)))
    (write-string "(CL-Type " stream)
    (prin1 spec stream)
    (write-char #\) stream)))

(defmethod print-object ((type ty-cl-type) stream)
  (if *print-readably*
      (call-next-method)
      (pprint-ty-cl-type stream type)))

(defmethod pprint-ty-extended (stream (type ty-cl-type))
  (pprint-ty-cl-type stream type))

;;;
;;; CL Subtype Checking
;;;

(defun cl-subtype-p (type1 type2)
  "Check if CL TYPE1 is a subtype of TYPE2.
Returns two values like cl:subtypep:
- First value: T if TYPE1 is definitely a subtype of TYPE2
- Second value: T if the relationship could be determined

Examples:
  (cl-subtype-p 'integer 'number) => T, T
  (cl-subtype-p 'string 'number) => NIL, T
  (cl-subtype-p '(satisfies foo) 'integer) => NIL, NIL (indeterminate)"
  (cl:subtypep type1 type2))

(defun cl-types-disjoint-p (type1 type2)
  "Check if CL TYPE1 and TYPE2 are disjoint (have no common instances).
Returns two values:
- First value: T if the types are definitely disjoint
- Second value: T if the relationship could be determined

Two types are disjoint if their intersection is the empty type."
  (multiple-value-bind (subtype-p valid-p)
      (cl:subtypep `(and ,type1 ,type2) nil)
    (values subtype-p valid-p)))

;;;
;;; Conversion Functions
;;;

(defgeneric cl-type->ty (specifier)
  (:documentation "Convert a CL type SPECIFIER to a Coalton algebraic type.

Mapping rules:
- T => ty-top (+ty-top+)
- NIL => ty-bot (+ty-bot+)
- (OR A B ...) => ty-union
- (AND A B ...) => ty-intersection
- Known types (integer, string, etc.) => registered Coalton type
- Other => ty-cl-type wrapper

The ENV parameter is reserved for future use (e.g., type expansion)."))

(defmethod cl-type->ty ((specifier (eql t)))
  "T is the top type in CL, maps to ty-top."
  +ty-top+)

(defmethod cl-type->ty ((specifier (eql nil)))
  "NIL is the bottom type in CL (empty type), maps to ty-bot."
  +ty-bot+)

(defmethod cl-type->ty ((specifier symbol))
  "Convert a symbol type specifier."
  (or
   ;; Check for registered type mapping
   (lookup-cl-type specifier)
   ;; Otherwise wrap as ty-cl-type
   (make-ty-cl-type :specifier specifier)))

(defmethod cl-type->ty ((specifier cons))
  "Convert a compound type specifier."
  (case (car specifier)
    ;; OR becomes ty-union
    (or
     (let ((members (mapcar #'cl-type->ty (cdr specifier))))
       (simplify-union-from-list members)))

    ;; AND becomes ty-intersection
    (and
     (let ((members (mapcar #'cl-type->ty (cdr specifier))))
       (simplify-intersection-from-list members)))

    ;; NOT is tricky - wrap as opaque for now
    ;; Future work could add ty-complement
    (not
     (make-ty-cl-type :specifier specifier))

    ;; SATISFIES predicates are opaque
    (satisfies
     (make-ty-cl-type :specifier specifier))

    ;; MEMBER types are opaque
    (member
     (make-ty-cl-type :specifier specifier))

    ;; EQL types are opaque
    (eql
     (make-ty-cl-type :specifier specifier))

    ;; VALUES type (multiple values) - wrap as opaque
    (values
     (make-ty-cl-type :specifier specifier))

    ;; FUNCTION types - could potentially map to Coalton function types
    ;; but the mapping is complex, so wrap as opaque for now
    (function
     (make-ty-cl-type :specifier specifier))

    ;; ARRAY, SIMPLE-ARRAY, VECTOR - wrap as opaque
    ((array simple-array vector simple-vector)
     (make-ty-cl-type :specifier specifier))

    ;; Default: wrap as opaque ty-cl-type
    (otherwise
     (make-ty-cl-type :specifier specifier))))

;;;
;;; Helper functions for union/intersection simplification
;;;

(defun simplify-union-from-list (members)
  "Create a simplified union from a list of types."
  (let ((flat-members (flatten-union-members-internal members)))
    (cond
      ;; Check for top (absorbing element)
      ((some #'ty-top-p flat-members)
       +ty-top+)
      ;; Remove bottom and duplicates
      (t
       (let ((filtered (remove-duplicates
                        (remove-if #'ty-bot-p flat-members)
                        :test #'ty=
                        :from-end t)))
         (cond
           ((null filtered) +ty-bot+)
           ((null (rest filtered)) (first filtered))
           (t (make-ty-union :members filtered))))))))

(defun simplify-intersection-from-list (members)
  "Create a simplified intersection from a list of types."
  (let ((flat-members (flatten-intersection-members-internal members)))
    (cond
      ;; Check for bottom (absorbing element)
      ((some #'ty-bot-p flat-members)
       +ty-bot+)
      ;; Remove top and duplicates
      (t
       (let ((filtered (remove-duplicates
                        (remove-if #'ty-top-p flat-members)
                        :test #'ty=
                        :from-end t)))
         (cond
           ((null filtered) +ty-top+)
           ((null (rest filtered)) (first filtered))
           (t (make-ty-intersection :members filtered))))))))

(defun flatten-union-members-internal (members)
  "Flatten nested unions into a single list."
  (loop :for m :in members
        :if (ty-union-p m)
          :append (flatten-union-members-internal (ty-union-members m))
        :else
          :collect m))

(defun flatten-intersection-members-internal (members)
  "Flatten nested intersections into a single list."
  (loop :for m :in members
        :if (ty-intersection-p m)
          :append (flatten-intersection-members-internal (ty-intersection-members m))
        :else
          :collect m))

;;;
;;; Reverse Conversion: Coalton Type to CL Type Specifier
;;;

(defgeneric ty->cl-type (type)
  (:documentation "Convert a Coalton type to a CL type specifier.

This is the inverse of cl-type->ty. Returns a CL type specifier that
approximates the Coalton type.

Note: Some Coalton types (e.g., polymorphic types, type applications
with type variables) cannot be directly represented in CL's type system.
Such cases return T (the top type) as a conservative approximation."))

(defmethod ty->cl-type ((type ty-cl-type))
  "Unwrap a ty-cl-type to get the original specifier."
  (ty-cl-type-specifier type))

(defmethod ty->cl-type ((type ty-top))
  "Top type maps to CL:T."
  t)

(defmethod ty->cl-type ((type ty-bot))
  "Bottom type maps to CL:NIL."
  nil)

(defmethod ty->cl-type ((type ty-union))
  "Union type maps to CL (OR ...)."
  (let ((member-specs (mapcar #'ty->cl-type (ty-union-members type))))
    (if (= 1 (length member-specs))
        (first member-specs)
        `(or ,@member-specs))))

(defmethod ty->cl-type ((type ty-intersection))
  "Intersection type maps to CL (AND ...)."
  (let ((member-specs (mapcar #'ty->cl-type (ty-intersection-members type))))
    (if (= 1 (length member-specs))
        (first member-specs)
        `(and ,@member-specs))))

(defmethod ty->cl-type ((type tycon))
  "Convert a type constructor to CL type."
  (or (lookup-coalton-type type)
      ;; Try to use the tycon name directly
      (let ((name (tycon-name type)))
        (if (and (symbolp name)
                 (find-symbol (symbol-name name) :cl))
            ;; Use CL symbol if available
            (find-symbol (symbol-name name) :cl)
            ;; Otherwise return the name as-is
            name))))

(defmethod ty->cl-type ((type tapp))
  "Convert a type application to CL type.
For function types, returns FUNCTION. For other applications,
returns the base type (loses type parameters)."
  (if (function-type-p type)
      ;; Function type: (A -> B) => (FUNCTION (A) B)
      (let ((from-spec (ty->cl-type (function-type-from type)))
            (to-spec (ty->cl-type (function-type-to type))))
        `(function (,from-spec) ,to-spec))
      ;; Other type applications: return base type
      ;; This is a conservative approximation
      (ty->cl-type (tapp-from type))))

(defmethod ty->cl-type ((type tyvar))
  "Type variables cannot be represented in CL - return T."
  t)

(defmethod ty->cl-type ((type tyvar-sub))
  "Bounded type variables cannot be represented in CL - return T."
  t)

(defmethod ty->cl-type ((type tgen))
  "Generic type variables cannot be represented in CL - return T."
  t)
