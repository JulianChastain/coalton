(defpackage #:coalton-impl/typechecker/simplify
  (:use
   #:cl
   #:coalton-impl/typechecker/base
   #:coalton-impl/typechecker/kinds
   #:coalton-impl/typechecker/types
   #:coalton-impl/typechecker/types-sub)
  (:local-nicknames
   (#:util #:coalton-impl/util)
   (#:cl-types #:coalton-impl/typechecker/cl-types))
  (:export
   #:simplify-type                      ; FUNCTION
   #:simplify-union                     ; FUNCTION
   #:simplify-intersection              ; FUNCTION
   #:compact-type                       ; FUNCTION
   #:remove-polar-variables             ; FUNCTION
   #:sandwiched-type-p                  ; FUNCTION
   #:polar-variable-p                   ; FUNCTION
   #:substitute-tyvar-sub               ; FUNCTION
   #:collect-type-occurrences           ; FUNCTION
   #:co-occurring-variables             ; FUNCTION
   #:merge-co-occurring-variables       ; FUNCTION
   ))

(in-package #:coalton-impl/typechecker/simplify)

;;;;
;;;; Type Simplification for Algebraic Subtyping
;;;;
;;;; After type inference, the constraint graph may contain type variables
;;;; with bounds that can be simplified to produce more readable types.
;;;; This module implements simplification transformations from the
;;;; Simple-sub paper.
;;;;
;;;; Key simplifications:
;;;;
;;;; 1. Sandwich removal: If a variable has exactly one lower bound L and
;;;;    one upper bound U, and L = U, then the variable can be replaced by L.
;;;;
;;;; 2. Polar variable removal: If a variable only appears in positive
;;;;    positions (covariant), it can be replaced by the union of its
;;;;    lower bounds. Dually for negative positions.
;;;;
;;;; 3. Union/Intersection flattening: Nested unions become flat unions,
;;;;    nested intersections become flat intersections.
;;;;
;;;; 4. Identity removal: (Union T ⊥) = T, (Intersection T ⊤) = T
;;;;
;;;; 5. Absorption: (Union T ⊤) = ⊤, (Intersection T ⊥) = ⊥
;;;;

;;;
;;; Union simplification
;;;

(defun flatten-union-members (members)
  "Flatten nested unions in MEMBERS into a single list."
  (declare (type ty-list members))
  (loop :for m :in members
        :if (ty-union-p m)
          :append (flatten-union-members (ty-union-members m))
        :else
          :collect m))

(defun remove-duplicate-types (types)
  "Remove duplicate types from TYPES list."
  (remove-duplicates types :test #'ty= :from-end t))

(defun simplify-union (members)
  "Simplify a union type with the given MEMBERS.

Simplifications applied:
- Flatten nested unions
- Remove duplicate types
- Remove ⊥ (bottom is identity for union)
- If ⊤ is present, result is ⊤
- Single member becomes that member
- Empty union becomes ⊥"
  (declare (type ty-list members))

  ;; Flatten nested unions
  (let* ((flat (flatten-union-members members))
         ;; Remove duplicates
         (unique (remove-duplicate-types flat))
         ;; Check for top (absorbing element)
         (has-top (some #'ty-top-p unique)))

    (when has-top
      ;; Union with Top is Top
      (return-from simplify-union +ty-top+))

    ;; Remove bottom (identity element)
    (let ((without-bot (remove-if #'ty-bot-p unique)))
      (cond
        ;; Empty union is bottom
        ((null without-bot) +ty-bot+)
        ;; Single member is that member
        ((null (rest without-bot)) (first without-bot))
        ;; Otherwise, create a union
        (t (make-ty-union :members without-bot))))))

;;;
;;; Intersection simplification
;;;

(defun flatten-intersection-members (members)
  "Flatten nested intersections in MEMBERS into a single list."
  (declare (type ty-list members))
  (loop :for m :in members
        :if (ty-intersection-p m)
          :append (flatten-intersection-members (ty-intersection-members m))
        :else
          :collect m))

(defun simplify-intersection (members)
  "Simplify an intersection type with the given MEMBERS.

Simplifications applied:
- Flatten nested intersections
- Remove duplicate types
- Remove ⊤ (top is identity for intersection)
- If ⊥ is present, result is ⊥
- Single member becomes that member
- Empty intersection becomes ⊤"
  (declare (type ty-list members))

  ;; Flatten nested intersections
  (let* ((flat (flatten-intersection-members members))
         ;; Remove duplicates
         (unique (remove-duplicate-types flat))
         ;; Check for bottom (absorbing element)
         (has-bot (some #'ty-bot-p unique)))

    (when has-bot
      ;; Intersection with Bottom is Bottom
      (return-from simplify-intersection +ty-bot+))

    ;; Remove top (identity element)
    (let ((without-top (remove-if #'ty-top-p unique)))
      (cond
        ;; Empty intersection is top
        ((null without-top) +ty-top+)
        ;; Single member is that member
        ((null (rest without-top)) (first without-top))
        ;; Otherwise, create an intersection
        (t (make-ty-intersection :members without-top))))))

;;;
;;; Sandwich removal
;;;

(defun sandwiched-type-p (var)
  "Check if VAR is 'sandwiched' between equal lower and upper bounds.
Returns the sandwiching type if true, NIL otherwise.

A variable is sandwiched if it has exactly one lower bound and one
upper bound, and they are equal. In this case, the variable can be
replaced by that type."
  (declare (type tyvar-sub var))
  (let ((lbs (tyvar-sub-lower-bounds var))
        (ubs (tyvar-sub-upper-bounds var)))
    (when (and (= 1 (length lbs))
               (= 1 (length ubs))
               (ty= (first lbs) (first ubs)))
      (first lbs))))

;;;
;;; Type simplification
;;;

(defgeneric simplify-type (type)
  (:documentation "Simplify TYPE by applying all applicable simplification rules.

This is the main entry point for type simplification after inference.
It recursively simplifies all parts of the type and applies:
- Sandwich removal for bounded variables
- Union/intersection simplification
- Structural recursion for type applications")

  (:method ((type tyvar-sub))
    ;; Check for sandwich (lower bound = upper bound)
    (let ((sandwich (sandwiched-type-p type)))
      (if sandwich
          (simplify-type sandwich)
          ;; Otherwise, simplify bounds and decide based on polarity
          (let ((lbs (tyvar-sub-lower-bounds type))
                (ubs (tyvar-sub-upper-bounds type)))
            (cond
              ;; Only lower bounds: the variable represents their union
              ((and lbs (null ubs))
               (simplify-union (mapcar #'simplify-type lbs)))
              ;; Only upper bounds: the variable represents their intersection
              ((and ubs (null lbs))
               (simplify-intersection (mapcar #'simplify-type ubs)))
              ;; Both bounds or neither: keep the variable
              ;; (could potentially do more sophisticated analysis)
              (t type))))))

  (:method ((type tyvar))
    ;; Regular type variable, return as-is
    type)

  (:method ((type tycon))
    type)

  (:method ((type tapp))
    (let ((from-simp (simplify-type (tapp-from type)))
          (to-simp (simplify-type (tapp-to type))))
      (if (and (eq from-simp (tapp-from type))
               (eq to-simp (tapp-to type)))
          type
          (make-tapp :from from-simp :to to-simp))))

  (:method ((type ty-union))
    (simplify-union (mapcar #'simplify-type (ty-union-members type))))

  (:method ((type ty-intersection))
    (simplify-intersection (mapcar #'simplify-type (ty-intersection-members type))))

  (:method ((type ty-top))
    type)

  (:method ((type ty-bot))
    type)

  (:method ((type tgen))
    type)

  ;; ty-cl-type: return as-is (opaque wrapper)
  (:method ((type cl-types:ty-cl-type))
    type))

;;;
;;; Polar variable removal
;;;

(defun collect-type-occurrences (type var positive)
  "Count occurrences of VAR in TYPE, tracking polarity.
Returns (VALUES POSITIVE-COUNT NEGATIVE-COUNT).

POSITIVE indicates the current polarity:
- T means we're in a positive (covariant) position
- NIL means we're in a negative (contravariant) position

Function argument types flip polarity, return types keep it.
Union and intersection are transparent to polarity."
  (declare (type ty type)
           (type tyvar-sub var))
  (labels ((count-in (ty pos)
             (etypecase ty
               (tyvar-sub
                (if (= (tyvar-sub-id ty) (tyvar-sub-id var))
                    (if pos '(1 . 0) '(0 . 1))
                    '(0 . 0)))
               (tyvar '(0 . 0))
               (tycon '(0 . 0))
               (tapp
                (if (function-type-p ty)
                    ;; Function: argument is negative, result is positive
                    (let ((arg-counts (count-in (function-type-from ty) (not pos)))
                          (ret-counts (count-in (function-type-to ty) pos)))
                      (cons (+ (car arg-counts) (car ret-counts))
                            (+ (cdr arg-counts) (cdr ret-counts))))
                    ;; Other type application: assume invariant for now
                    (let ((from-counts (count-in (tapp-from ty) pos))
                          (to-counts (count-in (tapp-to ty) pos)))
                      (cons (+ (car from-counts) (car to-counts))
                            (+ (cdr from-counts) (cdr to-counts))))))
               (ty-union
                (reduce (lambda (acc m)
                          (let ((c (count-in m pos)))
                            (cons (+ (car acc) (car c))
                                  (+ (cdr acc) (cdr c)))))
                        (ty-union-members ty)
                        :initial-value '(0 . 0)))
               (ty-intersection
                (reduce (lambda (acc m)
                          (let ((c (count-in m pos)))
                            (cons (+ (car acc) (car c))
                                  (+ (cdr acc) (cdr c)))))
                        (ty-intersection-members ty)
                        :initial-value '(0 . 0)))
               (ty-top '(0 . 0))
               (ty-bot '(0 . 0))
               (tgen '(0 . 0))
               (cl-types:ty-cl-type '(0 . 0)))))
    (let ((counts (count-in type positive)))
      (values (car counts) (cdr counts)))))

(defun polar-variable-p (type var)
  "Determine if VAR is a polar variable in TYPE.
Returns :POSITIVE if VAR only appears in positive positions,
:NEGATIVE if only in negative positions, or NIL if in both."
  (multiple-value-bind (pos-count neg-count)
      (collect-type-occurrences type var t)
    (cond
      ((and (> pos-count 0) (= neg-count 0)) :positive)
      ((and (= pos-count 0) (> neg-count 0)) :negative)
      (t nil))))

(defun remove-polar-variables (type)
  "Remove polar variables from TYPE by substituting their bound.

Positive-only variables are replaced by the union of their lower bounds.
Negative-only variables are replaced by the intersection of their upper bounds.

This produces more readable types without changing the semantics."
  (declare (type ty type))

  ;; Collect all tyvar-sub in the type
  (let ((vars (remove-if-not #'tyvar-sub-p (type-variables type))))
    (if (null vars)
        ;; No bounded variables to remove
        (simplify-type type)
        ;; Try to remove polar variables
        (let ((substitutions nil))
          (dolist (var vars)
            (let ((polarity (polar-variable-p type var)))
              (when polarity
                (let ((replacement
                        (case polarity
                          (:positive
                           ;; Replace with union of lower bounds
                           (let ((lbs (tyvar-sub-lower-bounds var)))
                             (if lbs
                                 (simplify-union lbs)
                                 +ty-bot+)))  ; No lower bounds = bottom
                          (:negative
                           ;; Replace with intersection of upper bounds
                           (let ((ubs (tyvar-sub-upper-bounds var)))
                             (if ubs
                                 (simplify-intersection ubs)
                                 +ty-top+))))))  ; No upper bounds = top
                  (push (cons var replacement) substitutions)))))

          (if substitutions
              ;; Apply substitutions and simplify again
              (remove-polar-variables
               (substitute-tyvar-sub type substitutions))
              ;; No more polar variables to remove
              (simplify-type type))))))

(defun substitute-tyvar-sub (type substitutions)
  "Substitute type variables according to SUBSTITUTIONS alist.
SUBSTITUTIONS is an alist of (tyvar-sub . replacement-type) pairs."
  (labels ((subst-in (ty)
             (etypecase ty
               (tyvar-sub
                ;; Compare by ID: extract ID from ty and from alist keys
                (let ((found (assoc (tyvar-sub-id ty) substitutions
                                    :key (lambda (x) (tyvar-sub-id x))
                                    :test #'=)))
                  (if found (cdr found) ty)))
               (tyvar ty)
               (tycon ty)
               (tapp
                (make-tapp :from (subst-in (tapp-from ty))
                           :to (subst-in (tapp-to ty))))
               (ty-union
                (make-ty-union :members (mapcar #'subst-in (ty-union-members ty))))
               (ty-intersection
                (make-ty-intersection :members (mapcar #'subst-in (ty-intersection-members ty))))
               (ty-top ty)
               (ty-bot ty)
               (tgen ty)
               (cl-types:ty-cl-type ty))))
    (subst-in type)))

;;;
;;; Compact simplification (full pipeline)
;;;

(defun compact-type (type)
  "Apply full simplification pipeline to TYPE.

This applies:
1. Basic simplification (sandwich removal, flatten, etc.)
2. Polar variable removal
3. Co-occurrence merging
4. Final simplification pass

The result is a type that is semantically equivalent but more readable."
  (let* ((step1 (simplify-type type))
         (step2 (remove-polar-variables step1))
         (step3 (merge-co-occurring-variables step2)))
    (simplify-type step3)))

;;;
;;; Co-occurrence Analysis
;;;
;;; Two type variables co-occur if they always appear together in all
;;; occurrences within a type. In such cases, they can be merged into
;;; a single variable, simplifying the type.
;;;
;;; For example, in the type (A -> B) -> (A -> B), if A and B always
;;; appear together as part of the same function type structure, they
;;; can potentially be represented more simply.
;;;

(defun collect-variable-contexts (type)
  "Collect contexts (paths) where each tyvar-sub appears in TYPE.
Returns a hash table mapping tyvar-sub IDs to lists of context paths."
  (let ((contexts (make-hash-table :test #'eql)))
    (labels ((collect (ty path)
               (etypecase ty
                 (tyvar-sub
                  (push (reverse path) (gethash (tyvar-sub-id ty) contexts nil)))
                 (tyvar nil)
                 (tycon nil)
                 (tapp
                  (collect (tapp-from ty) (cons :from path))
                  (collect (tapp-to ty) (cons :to path)))
                 (ty-union
                  (loop :for m :in (ty-union-members ty)
                        :for i :from 0
                        :do (collect m (cons (cons :union i) path))))
                 (ty-intersection
                  (loop :for m :in (ty-intersection-members ty)
                        :for i :from 0
                        :do (collect m (cons (cons :intersection i) path))))
                 (ty-top nil)
                 (ty-bot nil)
                 (tgen nil)
                 (cl-types:ty-cl-type nil))))
      (collect type nil)
      contexts)))

(defun co-occurring-variables (type)
  "Find groups of co-occurring variables in TYPE.

Two variables co-occur if:
1. They appear the same number of times
2. Their contexts differ only in which variable occupies the position

Returns a list of (representative . members) where members are variable IDs
that can be unified with the representative."
  (declare (type ty type))
  (let* ((contexts (collect-variable-contexts type))
         (vars (remove-if-not #'tyvar-sub-p (type-variables type)))
         (var-ids (mapcar #'tyvar-sub-id vars))
         (groups nil))

    ;; Simple heuristic: group variables that appear exactly once
    ;; and in identical structural positions (modulo variable identity)
    (dolist (var vars)
      (let* ((id (tyvar-sub-id var))
             (var-contexts (gethash id contexts)))
        (when (= 1 (length var-contexts))
          ;; Variable appears exactly once - candidate for merging
          (let ((ctx (first var-contexts)))
            ;; Find or create a group for this context pattern
            (let ((existing-group (find-if (lambda (g)
                                             (equal (second g) ctx))
                                           groups)))
              (if existing-group
                  (push id (cddr existing-group))
                  (push (list id ctx id) groups)))))))

    ;; Return groups with more than one member
    (mapcar (lambda (g)
              (cons (first g) (cddr g)))
            (remove-if (lambda (g) (null (cddr g))) groups))))

(defun merge-co-occurring-variables (type)
  "Merge co-occurring variables in TYPE to simplify it.

When multiple variables always appear in the same structural context,
they can be merged into a single representative variable."
  (declare (type ty type))
  (let ((groups (co-occurring-variables type)))
    (if (null groups)
        type  ; Nothing to merge
        ;; Build substitutions: map all members to representative
        (let ((substitutions nil))
          (dolist (group groups)
            (let* ((representative-id (car group))
                   (member-ids (cdr group))
                   (representative (find representative-id
                                         (remove-if-not #'tyvar-sub-p (type-variables type))
                                         :key #'tyvar-sub-id)))
              (dolist (member-id member-ids)
                (let ((member (find member-id
                                    (remove-if-not #'tyvar-sub-p (type-variables type))
                                    :key #'tyvar-sub-id)))
                  (when (and member representative (not (eql member-id representative-id)))
                    (push (cons member representative) substitutions))))))
          (if substitutions
              (substitute-tyvar-sub type substitutions)
              type)))))

;;;
;;; Advanced Union/Intersection Simplification
;;;
;;; Additional simplifications for set-theoretic types:
;;; 1. Remove function types that are more specific (in unions)
;;; 2. Remove function types that are more general (in intersections)
;;;

(defun function-subtype-p (f1 f2)
  "Check if function type F1 is a subtype of F2.

A function type (A -> B) is a subtype of (C -> D) if:
- C is a subtype of A (contravariant)
- B is a subtype of D (covariant)

For concrete types, subtyping is equality.
Returns T if F1 <= F2, NIL otherwise."
  (when (and (function-type-p f1) (function-type-p f2))
    (let ((a (function-type-from f1))
          (b (function-type-to f1))
          (c (function-type-from f2))
          (d (function-type-to f2)))
      ;; For concrete types, check equality
      ;; For variables, we can't determine subtyping statically
      (and (or (tyvar-p c) (tyvar-sub-p c) (ty= a c) (ty= c a))
           (or (tyvar-p b) (tyvar-sub-p b) (ty= b d) (ty= d b))))))

(defun simplify-union-subtypes (members)
  "Remove redundant subtypes from a union.

In a union, if type A is a subtype of type B, then A is redundant
because any value of type A is also of type B, and the union already
includes B."
  (declare (type ty-list members))
  ;; For now, just handle the case of identical function types
  ;; More sophisticated subtype analysis could be added later
  (remove-duplicate-types members))

(defun simplify-intersection-supertypes (members)
  "Remove redundant supertypes from an intersection.

In an intersection, if type A is a supertype of type B, then A is
redundant because any value that satisfies B also satisfies A."
  (declare (type ty-list members))
  ;; For now, just handle duplicates
  ;; More sophisticated supertype analysis could be added later
  (remove-duplicate-types members))

;;;
;;; CL Type Simplification
;;;
;;; Additional simplification rules for unions and intersections
;;; that contain ty-cl-type members.
;;;

(defun simplify-union-with-cl-types (members)
  "Simplify a union that may contain ty-cl-type members.

Combines multiple ty-cl-type members into a single (OR ...) type
and removes redundant types based on subtypep relationships."
  (declare (type ty-list members))
  (let ((cl-types nil)
        (other-types nil))
    ;; Separate CL types from other types
    (dolist (m members)
      (if (cl-types:ty-cl-type-p m)
          (push (cl-types:ty-cl-type-specifier m) cl-types)
          (push m other-types)))

    (cond
      ;; No CL types - return original members
      ((null cl-types)
       members)
      ;; Only CL types
      ((null other-types)
       (if (= 1 (length cl-types))
           (list (cl-types:make-ty-cl-type :specifier (first cl-types)))
           ;; Combine into single (OR ...) CL type
           (list (cl-types:make-ty-cl-type :specifier `(or ,@(nreverse cl-types))))))
      ;; Mix of CL types and other types
      (t
       (let ((combined-cl (if (= 1 (length cl-types))
                              (cl-types:make-ty-cl-type :specifier (first cl-types))
                              (cl-types:make-ty-cl-type :specifier `(or ,@(nreverse cl-types))))))
         (cons combined-cl (nreverse other-types)))))))

(defun simplify-intersection-with-cl-types (members)
  "Simplify an intersection that may contain ty-cl-type members.

Combines multiple ty-cl-type members into a single (AND ...) type
and detects empty intersections using subtypep."
  (declare (type ty-list members))
  (let ((cl-types nil)
        (other-types nil))
    ;; Separate CL types from other types
    (dolist (m members)
      (if (cl-types:ty-cl-type-p m)
          (push (cl-types:ty-cl-type-specifier m) cl-types)
          (push m other-types)))

    (cond
      ;; No CL types - return original members
      ((null cl-types)
       members)
      ;; Only CL types
      ((null other-types)
       ;; Check if intersection is empty
       (let ((combined-spec (if (= 1 (length cl-types))
                                (first cl-types)
                                `(and ,@(nreverse cl-types)))))
         (multiple-value-bind (is-nil valid-p)
             (cl:subtypep combined-spec nil)
           (if (and valid-p is-nil)
               ;; Empty intersection - return bottom type
               (list +ty-bot+)
               (list (cl-types:make-ty-cl-type :specifier combined-spec))))))
      ;; Mix of CL types and other types
      (t
       (let* ((combined-spec (if (= 1 (length cl-types))
                                 (first cl-types)
                                 `(and ,@(nreverse cl-types))))
              ;; Check if the CL part is empty
              (combined-cl (multiple-value-bind (is-nil valid-p)
                               (cl:subtypep combined-spec nil)
                             (if (and valid-p is-nil)
                                 +ty-bot+
                                 (cl-types:make-ty-cl-type :specifier combined-spec)))))
         (cons combined-cl (nreverse other-types)))))))

(defun remove-cl-type-redundancies (members direction)
  "Remove redundant types from MEMBERS using CL subtypep.

DIRECTION is either :UNION or :INTERSECTION.
- For unions: remove types that are subtypes of other members
- For intersections: remove types that are supertypes of other members"
  (declare (type ty-list members)
           (type (member :union :intersection) direction))
  (let ((result nil))
    (dolist (m members)
      (unless (some (lambda (other)
                      (and (not (eq m other))
                           (cond
                             ;; Both are CL types: use subtypep
                             ((and (cl-types:ty-cl-type-p m)
                                   (cl-types:ty-cl-type-p other))
                              (multiple-value-bind (subtype-p valid-p)
                                  (ecase direction
                                    (:union
                                     ;; In union: m is redundant if m <= other
                                     (cl:subtypep (cl-types:ty-cl-type-specifier m)
                                                  (cl-types:ty-cl-type-specifier other)))
                                    (:intersection
                                     ;; In intersection: m is redundant if other <= m
                                     (cl:subtypep (cl-types:ty-cl-type-specifier other)
                                                  (cl-types:ty-cl-type-specifier m))))
                                (and valid-p subtype-p)))
                             ;; Otherwise, can't determine statically
                             (t nil))))
                    members)
        (push m result)))
    (nreverse result)))
