(defpackage #:coalton-impl/typechecker/scheme
  (:use
   #:cl
   #:coalton-impl/typechecker/base
   #:coalton-impl/typechecker/kinds
   #:coalton-impl/typechecker/types
   #:coalton-impl/typechecker/substitutions
   #:coalton-impl/typechecker/predicate)
  (:local-nicknames
   (#:util #:coalton-impl/util)
   (#:settings #:coalton-impl/settings)
   (#:types-sub #:coalton-impl/typechecker/types-sub)
   (#:levels #:coalton-impl/typechecker/levels)
   (#:simplify #:coalton-impl/typechecker/simplify))
  (:export
   #:ty-scheme                          ; STRUCT
   #:make-ty-scheme                     ; CONSTRUCTOR
   #:ty-scheme-kinds                    ; ACCESSOR
   #:ty-scheme-type                     ; ACCESSOR
   #:ty-scheme=                         ; FUNCTION
   #:ty-scheme-p                        ; FUNCTION
   #:scheme-list                        ; TYPE
   #:scheme-binding-list                ; TYPE
   #:quantify                           ; FUNCTION
   #:to-scheme                          ; FUNCTION
   #:fresh-inst                         ; FUNCTION
   #:scheme-predicates                  ; FUNCTION
   #:fresh-pred                         ; FUNCTION
   #:fresh-preds                        ; FUNCTION
   #:quantify-using-tvar-order          ; FUNCTION
   ;; Algebraic subtyping extensions
   #:fresh-inst-sub                     ; FUNCTION
   #:quantify-at-level                  ; FUNCTION
   #:to-scheme-sub                      ; FUNCTION
   ))

(in-package #:coalton-impl/typechecker/scheme)

;;;
;;; Type schemes
;;;

(defstruct ty-scheme 
  (kinds (util:required 'kinds) :type list         :read-only t)
  (type  (util:required 'type)  :type qualified-ty :read-only t))

(defun ty-scheme= (ty-scheme1 ty-scheme2)
  (and (equalp (ty-scheme-kinds ty-scheme1)
               (ty-scheme-kinds ty-scheme2))
       (qualified-ty= (ty-scheme-type ty-scheme1)
                      (ty-scheme-type ty-scheme2))))

(defmethod make-load-form ((self ty-scheme) &optional env)
  (make-load-form-saving-slots self :environment env))

(defun scheme-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'ty-scheme-p x)))

(deftype scheme-list ()
  '(satisfies scheme-list-p))

(defun scheme-binding-list-p (x)
  (and (alexandria:proper-list-p x)
       (every (lambda (b) (typep b '(cons symbol ty-scheme))) x)))

(deftype scheme-binding-list ()
  `(satisfies scheme-binding-list-p))

;;;
;;; Operations on Schemes
;;;

(defun quantify (tyvars type)
  (declare (type tyvar-list tyvars)
           (type qualified-ty type)
           (values ty-scheme))
  (let* ((vars (remove-if
                (lambda (x) (not (find x tyvars :test #'equalp)))
                (type-variables type)))
         (kinds (mapcar #'kind-of vars))
         (subst (loop :for var :in vars
                      :for id :from 0
                      :collect (make-substitution :from var :to (make-tgen :id id)))))
    (make-ty-scheme
     :kinds kinds
     :type (apply-substitution subst type))))

(defgeneric to-scheme (ty)
  (:method ((ty qualified-ty))
    (make-ty-scheme
     :kinds nil
     :type ty))

  (:method ((ty ty))
    (to-scheme (qualify nil ty))))

(defun fresh-inst (ty-scheme)
  (declare (type ty-scheme ty-scheme)
           (values qualified-ty &optional))
  (let ((types (mapcar (lambda (k) (make-variable k))
                       (ty-scheme-kinds ty-scheme))))
    (instantiate types (ty-scheme-type ty-scheme))))

(defun scheme-predicates (ty-scheme)
  "Get freshly instantiated predicates of scheme TY-SCHEME"
  (qualified-ty-predicates (fresh-inst ty-scheme)))

(defun fresh-pred (pred)
  "Returns PRED with fresh type variables"
  (declare (type ty-predicate pred)
           (values ty-predicate))
  (let* ((var (make-variable))
         (qual-ty (make-qualified-ty :predicates (list pred) :type var))
         (scheme (quantify (type-variables (list pred var)) qual-ty)))
    (car (qualified-ty-predicates (fresh-inst scheme)))))

(defun fresh-preds (preds)
  "Returns PRED with fresh type variables"
  (declare (type ty-predicate-list preds)
           (values ty-predicate-list))
  (let* ((var (make-variable))
         (qual-ty (make-qualified-ty :predicates preds :type var))
         (scheme (quantify (type-variables (cons var preds)) qual-ty)))
    (qualified-ty-predicates (fresh-inst scheme))))

(defun quantify-using-tvar-order (tyvars type)
  (let* ((vars (remove-if
                (lambda (x) (not (find x (type-variables type) :test #'equalp)))
                tyvars))
         (kinds (mapcar #'kind-of vars))
         (subst (loop :for var :in vars
                      :for id :from 0
                      :collect (make-substitution :from var :to (make-tgen :id id)))))
    (make-ty-scheme
     :kinds kinds
     :type (apply-substitution subst type))))

;;;
;;; Methods
;;;

(defmethod apply-substitution (subst-list (type ty-scheme))
  (make-ty-scheme
   :kinds (ty-scheme-kinds type)
   :type (apply-substitution subst-list (ty-scheme-type type))))

(defmethod type-variables ((type ty-scheme))
  (type-variables (ty-scheme-type type)))

(defmethod kind-of ((type ty-scheme))
  (kind-of (fresh-inst type)))

(defmethod function-type-p ((type ty-scheme))
  (function-type-p (fresh-inst type)))

(defmethod function-return-type ((type ty-scheme))
  (to-scheme (function-return-type (fresh-inst type))))

(defmethod function-type-arguments ((type ty-scheme))
  (function-type-arguments (fresh-inst type)))

(defmethod remove-source-info ((scheme ty-scheme))
  (make-ty-scheme
   :kinds (ty-scheme-kinds scheme)
   :type (remove-source-info (ty-scheme-type scheme))))

;;;
;;; Pretty printing
;;;

(defun pprint-scheme (stream scheme)
  (declare (type stream stream)
           (type ty-scheme scheme))
  (cond
    ((null (ty-scheme-kinds scheme))
     (write (ty-scheme-type scheme) :stream stream))
    (t
     (with-pprint-variable-scope ()
       (let* ((types (mapcar (lambda (k) (next-pprint-variable-as-tvar k))
                             (ty-scheme-kinds scheme)))
              (new-type (instantiate types (ty-scheme-type scheme))))
         (write-string (if settings:*coalton-print-unicode*
                           "∀"
                           "FORALL")
                       stream)
         (loop :for ty :in types
               :do (write-char #\space stream)
                   (write ty :stream stream))
         (write-string ". " stream)
         (write new-type :stream stream)))
     ))

  nil)

(defmethod print-object ((scheme ty-scheme) stream)
  (if *print-readably*
      (call-next-method)
      (pprint-scheme stream scheme)))

;;;
;;; Algebraic Subtyping Extensions
;;;
;;; These functions support level-based let-polymorphism using tyvar-sub
;;; instead of tyvar. They can be used alongside or instead of the
;;; traditional HM-style operations.
;;;

(defun substitute-vars-for-tgen (type var-tgen-alist)
  "Substitute type variables (tyvar or tyvar-sub) with tgen according to alist.
VAR-TGEN-ALIST is an alist of (variable . tgen) pairs."
  (labels ((subst-in (ty)
             (etypecase ty
               (types-sub:tyvar-sub
                (let ((found (assoc (types-sub:tyvar-sub-id ty) var-tgen-alist
                                    :key (lambda (v)
                                           (if (types-sub:tyvar-sub-p v)
                                               (types-sub:tyvar-sub-id v)
                                               (tyvar-id v)))
                                    :test #'=)))
                  (if found (cdr found) ty)))
               (tyvar
                (let ((found (assoc (tyvar-id ty) var-tgen-alist
                                    :key (lambda (v)
                                           (if (tyvar-p v)
                                               (tyvar-id v)
                                               (types-sub:tyvar-sub-id v)))
                                    :test #'=)))
                  (if found (cdr found) ty)))
               (tycon ty)
               (tapp
                (make-tapp :from (subst-in (tapp-from ty))
                           :to (subst-in (tapp-to ty))))
               (types-sub:ty-union
                (types-sub:make-ty-union
                 :members (mapcar #'subst-in (types-sub:ty-union-members ty))))
               (types-sub:ty-intersection
                (types-sub:make-ty-intersection
                 :members (mapcar #'subst-in (types-sub:ty-intersection-members ty))))
               (types-sub:ty-top ty)
               (types-sub:ty-bot ty)
               (tgen ty))))
    (etypecase type
      (qualified-ty
       (make-qualified-ty
        :predicates (mapcar (lambda (pred)
                              (make-ty-predicate
                               :class (ty-predicate-class pred)
                               :types (mapcar #'subst-in (ty-predicate-types pred))
                               :location (ty-predicate-location pred)))
                            (qualified-ty-predicates type))
        :type (subst-in (qualified-ty-type type))))
      (ty (subst-in type)))))

(defun fresh-inst-sub (ty-scheme level)
  "Instantiate TY-SCHEME with fresh tyvar-sub variables at LEVEL.

This is the subtyping analog of fresh-inst. Instead of creating regular
type variables, it creates tyvar-sub variables that track bounds and
are associated with a specific let-polymorphism level."
  (declare (type ty-scheme ty-scheme)
           (type fixnum level)
           (values qualified-ty &optional))
  (let ((types (mapcar (lambda (k) (levels:make-variable-at-level k level))
                       (ty-scheme-kinds ty-scheme))))
    (instantiate types (ty-scheme-type ty-scheme))))

(defun quantify-at-level (type target-level)
  "Quantify TYPE based on tyvar-sub levels.

Type variables at levels greater than TARGET-LEVEL are generalized.
The type is simplified before quantification to produce cleaner schemes.

Returns a ty-scheme with the generalizable variables abstracted."
  (declare (type qualified-ty type)
           (type fixnum target-level)
           (values ty-scheme))

  ;; First, simplify the type (but don't remove polar variables yet,
  ;; since those at higher levels will be quantified, not simplified away)
  (let* ((simplified-type (simplify:simplify-type (qualified-ty-type type)))
         (simplified-qual (make-qualified-ty
                           :predicates (qualified-ty-predicates type)
                           :type simplified-type))

         ;; Find all tyvar-sub at levels > target-level
         (all-vars (type-variables simplified-qual))
         (generalizable-vars
           (remove-if-not
            (lambda (var)
              (and (types-sub:tyvar-sub-p var)
                   (> (types-sub:tyvar-sub-level var) target-level)))
            all-vars))

         ;; For compatibility, also include regular tyvars
         (regular-tyvars
           (remove-if-not #'tyvar-p all-vars))

         ;; All variables to quantify
         (vars-to-quantify (append generalizable-vars regular-tyvars)))

    (if (null vars-to-quantify)
        ;; No variables to quantify
        (make-ty-scheme :kinds nil :type simplified-qual)
        ;; Quantify the variables
        (let* ((kinds (mapcar #'kind-of vars-to-quantify))
               (var-tgen-alist (loop :for var :in vars-to-quantify
                                     :for id :from 0
                                     :collect (cons var (make-tgen :id id)))))
          (make-ty-scheme
           :kinds kinds
           :type (substitute-vars-for-tgen simplified-qual var-tgen-alist))))))

(defgeneric to-scheme-sub (ty level)
  (:documentation "Convert a type to a scheme using subtyping-based quantification.

Unlike to-scheme, this function:
1. Simplifies the type to resolve constraint bounds
2. Quantifies variables based on their level relative to LEVEL")

  (:method ((ty qualified-ty) level)
    (quantify-at-level ty level))

  (:method ((ty ty) level)
    (to-scheme-sub (qualify nil ty) level)))
