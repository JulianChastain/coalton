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
   ;; Effecting function type (for algebraic effects)
   #:ty-effecting-fn                    ; STRUCT
   #:make-ty-effecting-fn               ; CONSTRUCTOR
   #:ty-effecting-fn-domain             ; ACCESSOR
   #:ty-effecting-fn-codomain           ; ACCESSOR
   #:ty-effecting-fn-effects            ; ACCESSOR
   #:ty-effecting-fn-p                  ; FUNCTION
   ;; Effect operation type
   #:ty-effect-op                       ; STRUCT
   #:make-ty-effect-op                  ; CONSTRUCTOR
   #:ty-effect-op-name                  ; ACCESSOR
   #:ty-effect-op-request-type          ; ACCESSOR
   #:ty-effect-op-response-type         ; ACCESSOR
   #:ty-effect-op-p                     ; FUNCTION
   ;; Effect utilities
   #:make-exception-effect              ; FUNCTION
   #:pure-effect-p                      ; FUNCTION
   #:effect-row-p                       ; FUNCTION
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
;;; Effecting function type (for algebraic effects)
;;;

(defstruct (ty-effecting-fn (:include ty))
  "A function type with effect tracking.

An effecting function type (A -> B ! E) represents a function that:
- Takes a value of type A (the DOMAIN)
- Returns a value of type B (the CODOMAIN)
- May perform effects described by E (the EFFECTS)

The EFFECTS field is an effect row, which is either:
- ty-bot (Pure): No effects, equivalent to regular function
- ty-effect-op: A single effect operation
- ty-union of effect operations: Multiple possible effects
- tyvar-sub: Polymorphic effect variable

Effect rows follow these subtyping rules:
- E1 <= (E1 | E2)  (subset relationship)
- Pure <= E for all E (pure functions are subtypes of effectful ones)
- (-> A B ! E1) <= (-> A B ! E2) when E1 <= E2 (covariant effects)

This structure enables tracking effects through the type system while
maintaining backwards compatibility with existing pure function types."
  (domain   (util:required 'domain)   :type ty :read-only t)
  (codomain (util:required 'codomain) :type ty :read-only t)
  (effects  (util:required 'effects)  :type ty :read-only t))

;;;
;;; Effect operation type
;;;

(defstruct (ty-effect-op (:include ty))
  "An effect operation type.

Effect operations are the primitive building blocks of algebraic effects.
Each operation represents a request that can be handled by an effect handler.

NAME: A symbol identifying the effect (e.g., 'STATE.GET, 'CONSOLE.READ-LINE)
REQUEST-TYPE: The type of data sent with the request
RESPONSE-TYPE: The type of data returned when the handler resumes

For example, a State effect might have operations:
- (ty-effect-op 'STATE.GET Unit :s)       ; get : () -> :s ! State
- (ty-effect-op 'STATE.PUT :s Unit)       ; put : :s -> Unit ! State

Exceptions are a special case where RESPONSE-TYPE is ty-bot (⊥) because
throwing an exception never returns normally:
- (ty-effect-op 'PARSE-ERROR String ⊥)    ; never resumes

Effect operations participate in effect rows via ty-union, enabling
functions to declare multiple possible effects."
  (name          (util:required 'name)          :type symbol :read-only t)
  (request-type  (util:required 'request-type)  :type ty     :read-only t)
  (response-type (util:required 'response-type) :type ty     :read-only t))

(defun make-exception-effect (name payload-type)
  "Create an exception effect (non-resumable).

Exceptions are effect operations where the response type is ⊥ (bottom),
indicating that throwing the exception never returns normally.

NAME: Symbol identifying the exception type
PAYLOAD-TYPE: Type of data carried by the exception

This maps to Common Lisp's ERROR function at runtime."
  (make-ty-effect-op :name name
                     :request-type payload-type
                     :response-type +ty-bot+))

(defun pure-effect-p (effects)
  "Check if EFFECTS represents a pure (effect-free) computation.

Pure effects are represented by ty-bot (⊥), the identity for effect union.
A function with pure effects is equivalent to a regular function type."
  (ty-bot-p effects))

(defun effect-row-p (type)
  "Check if TYPE is a valid effect row.

Valid effect rows are:
- ty-bot (Pure): No effects
- ty-effect-op: Single effect
- ty-union of effect ops/rows: Multiple effects
- tyvar-sub: Effect variable (polymorphic)"
  (or (ty-bot-p type)
      (ty-effect-op-p type)
      (and (ty-union-p type)
           (every #'effect-row-p (ty-union-members type)))
      (tyvar-sub-p type)))

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

(defmethod kind-of ((type ty-effecting-fn))
  ;; Effecting function type has kind * (it's a concrete type)
  +kstar+)

(defmethod kind-of ((type ty-effect-op))
  ;; Effect operations have kind * (they're types in effect rows)
  +kstar+)

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

(defmethod ty= ((type1 ty-effecting-fn) (type2 ty-effecting-fn))
  "Two effecting function types are equal if domain, codomain, and effects are equal."
  (and (ty= (ty-effecting-fn-domain type1) (ty-effecting-fn-domain type2))
       (ty= (ty-effecting-fn-codomain type1) (ty-effecting-fn-codomain type2))
       (ty= (ty-effecting-fn-effects type1) (ty-effecting-fn-effects type2))))

(defmethod ty= ((type1 ty-effect-op) (type2 ty-effect-op))
  "Two effect operations are equal if they have the same name and types."
  (and (eq (ty-effect-op-name type1) (ty-effect-op-name type2))
       (ty= (ty-effect-op-request-type type1) (ty-effect-op-request-type type2))
       (ty= (ty-effect-op-response-type type1) (ty-effect-op-response-type type2))))

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

(defmethod type-variables ((type ty-effecting-fn))
  (remove-duplicates
   (append (type-variables (ty-effecting-fn-domain type))
           (type-variables (ty-effecting-fn-codomain type))
           (type-variables (ty-effecting-fn-effects type)))
   :test #'equalp
   :from-end t))

(defmethod type-variables ((type ty-effect-op))
  (remove-duplicates
   (append (type-variables (ty-effect-op-request-type type))
           (type-variables (ty-effect-op-response-type type)))
   :test #'equalp
   :from-end t))

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

(defmethod apply-ksubstitution (subs (type ty-effecting-fn))
  (make-ty-effecting-fn
   :alias (mapcar (lambda (alias) (apply-ksubstitution subs alias)) (ty-alias type))
   :domain (apply-ksubstitution subs (ty-effecting-fn-domain type))
   :codomain (apply-ksubstitution subs (ty-effecting-fn-codomain type))
   :effects (apply-ksubstitution subs (ty-effecting-fn-effects type))))

(defmethod apply-ksubstitution (subs (type ty-effect-op))
  (make-ty-effect-op
   :alias (mapcar (lambda (alias) (apply-ksubstitution subs alias)) (ty-alias type))
   :name (ty-effect-op-name type)
   :request-type (apply-ksubstitution subs (ty-effect-op-request-type type))
   :response-type (apply-ksubstitution subs (ty-effect-op-response-type type))))

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

(defmethod kind-variables-generic% ((type ty-effecting-fn))
  (append
   (kind-variables-generic% (ty-effecting-fn-domain type))
   (kind-variables-generic% (ty-effecting-fn-codomain type))
   (kind-variables-generic% (ty-effecting-fn-effects type))))

(defmethod kind-variables-generic% ((type ty-effect-op))
  (append
   (kind-variables-generic% (ty-effect-op-request-type type))
   (kind-variables-generic% (ty-effect-op-response-type type))))

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

(defmethod instantiate (types (type ty-effecting-fn))
  (make-ty-effecting-fn
   :alias (mapcar (lambda (alias) (instantiate types alias)) (ty-alias type))
   :domain (instantiate types (ty-effecting-fn-domain type))
   :codomain (instantiate types (ty-effecting-fn-codomain type))
   :effects (instantiate types (ty-effecting-fn-effects type))))

(defmethod instantiate (types (type ty-effect-op))
  (make-ty-effect-op
   :alias (mapcar (lambda (alias) (instantiate types alias)) (ty-alias type))
   :name (ty-effect-op-name type)
   :request-type (instantiate types (ty-effect-op-request-type type))
   :response-type (instantiate types (ty-effect-op-response-type type))))

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

(defun pprint-ty-effecting-fn (stream type)
  "Pretty print an effecting function type.

Uses Koka-style syntax: (A -> B ! E)
When effects are pure (ty-bot), hides the effect annotation for cleaner output."
  (declare (type stream stream)
           (type ty-effecting-fn type))
  (write-string "(" stream)
  (pprint-ty stream (ty-effecting-fn-domain type))
  (write-string (if settings:*coalton-print-unicode*
                    " → "
                    " -> ")
                stream)
  (pprint-ty stream (ty-effecting-fn-codomain type))
  ;; Only show effects if not pure
  (let ((effects (ty-effecting-fn-effects type)))
    (unless (pure-effect-p effects)
      (write-string " ! " stream)
      (pprint-effect-row stream effects)))
  (write-string ")" stream))

(defun pprint-effect-row (stream effects)
  "Pretty print an effect row.

Effect rows are displayed as:
- Pure effects (ty-bot): 'Pure' or hidden
- Single effect: effect name
- Union of effects: (E1 | E2 | ...)"
  (declare (type stream stream)
           (type ty effects))
  (cond
    ((ty-bot-p effects)
     (write-string "Pure" stream))
    ((ty-effect-op-p effects)
     (write (ty-effect-op-name effects) :stream stream))
    ((ty-union-p effects)
     ;; Print as (E1 | E2 | ...)
     (write-string "(" stream)
     (loop :for (member . rest) :on (ty-union-members effects)
           :do (pprint-effect-row stream member)
           :when rest :do (write-string " | " stream))
     (write-string ")" stream))
    ((tyvar-sub-p effects)
     ;; Effect variable - print like type variable
     (pprint-tyvar-sub stream effects))
    (t
     ;; Fallback - use generic printing
     (pprint-ty stream effects))))

(defun pprint-ty-effect-op (stream type)
  "Pretty print an effect operation type."
  (declare (type stream stream)
           (type ty-effect-op type))
  (format stream "(Effect ~S ~A ~A)"
          (ty-effect-op-name type)
          (ty-effect-op-request-type type)
          (ty-effect-op-response-type type)))

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

(defmethod print-object ((type ty-effecting-fn) stream)
  (if *print-readably*
      (call-next-method)
      (pprint-ty-effecting-fn stream type)))

(defmethod print-object ((type ty-effect-op) stream)
  (if *print-readably*
      (call-next-method)
      (pprint-ty-effect-op stream type)))

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

(defmethod pprint-ty-extended (stream (type ty-effecting-fn))
  (pprint-ty-effecting-fn stream type))

(defmethod pprint-ty-extended (stream (type ty-effect-op))
  (pprint-ty-effect-op stream type))
