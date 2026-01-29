(defpackage #:coalton-impl/typechecker/tc-env
  (:use
   #:cl
   #:coalton-impl/typechecker/parse-type)
  (:local-nicknames
   (#:util #:coalton-impl/util)
   (#:parser #:coalton-impl/parser)
   (#:source #:coalton-impl/source)
   (#:tc #:coalton-impl/typechecker/stage-1)
   (#:macro #:coalton-impl/parser/macro))
  (:export
   #:make-tc-env                        ; CONSTRUCTOR
   #:tc-env                             ; STRUCT
   #:tc-env-env                         ; ACCESSOR
   #:tc-env-ty-table                    ; ACCESSOR
   #:tc-env-level                       ; ACCESSOR (for subtyping)
   #:tc-env-add-variable                ; FUNCTION
   #:tc-env-add-variable-sub            ; FUNCTION (for subtyping)
   #:tc-env-lookup-value                ; FUNCTION
   #:tc-env-lookup-value-sub            ; FUNCTION (for subtyping)
   #:tc-env-add-definition              ; FUNCTION
   #:tc-env-bound-variables             ; FUNCTION
   #:tc-env-bindings-variables          ; FUNCTION
   #:tc-env-replace-type                ; FUNCTION
   ;; Level management for subtyping
   #:tc-env-enter-level                 ; FUNCTION
   #:tc-env-exit-level                  ; FUNCTION
   #:with-tc-env-level                  ; MACRO
   ;; Expansion constraint application
   #:apply-expansion-constraints        ; FUNCTION
   ))

(in-package #:coalton-impl/typechecker/tc-env)

;;;
;;; Typechecking Environment
;;;

(defstruct (tc-env
            (:predicate nil))

  ;; The main compiler env
  (env      (util:required 'env)          :type tc:environment :read-only t)

  ;; Hash table mapping variables bound in the current translation unit to types
  (ty-table (make-hash-table :test #'eq)  :type hash-table     :read-only t)

  ;; Current level for let-polymorphism in algebraic subtyping
  ;; Level 0 is the outermost scope; each let-binding increases the level.
  ;; This field is mutable to allow entering/exiting scopes.
  (level    0                             :type fixnum         :read-only nil))

(defun tc-env-add-variable (env name)
  "Add a variable named NAME to ENV and return the scheme."
  (declare (type tc-env env)
           (type symbol name)
           (values tc:tyvar))

  (when (gethash name (tc-env-ty-table env))
    (util:coalton-bug "Attempt to add already defined variable with name ~S." name))

  (tc:qualified-ty-type (tc:fresh-inst (setf (gethash name (tc-env-ty-table env)) (tc:to-scheme (tc:make-variable))))))

(defun tc-env-suggest-value (env name)
  "If value lookup failed, generate suggestions for what to do, if anything."
  (declare (type tc-env env)
           (type symbol name)
           (values util:string-list &optional))
  (let ((suggestions nil))
    ;; If the symbol names a type, user may have intended to use a type constructor
    (let ((type (tc:lookup-type (tc-env-env env) name :no-error t)))
      (when type
        (push (format nil "Did you mean a constructor of type ~A?" (tc:type-entry-name type))
              suggestions)))
    (nreverse suggestions)))

(defun tc-env-lookup-value (env var)
  "Lookup the type of a variable named VAR in ENV."
  (declare (type tc-env env)
           (type parser:node-variable var)
           (values tc:ty tc:ty-predicate-list))

  (let* ((var-name (parser:node-variable-name var))
         (scheme (or (gethash var-name (tc-env-ty-table env))
                     (tc:lookup-value-type (tc-env-env env) var-name :no-error t))))
    (unless scheme
      ;; Variable is unbound: create an error
      (apply #'tc:tc-error (format nil "Unknown variable ~a" var-name)
             (cons (source:note (source:location var)
                                (format nil "unknown variable ~a" var-name))
                   (loop :for suggestion :in (tc-env-suggest-value env var-name)
                         :collect (source:help (source:location var) #'identity suggestion)))))
    (let ((qualified-type (tc:fresh-inst scheme)))
      (values (tc:qualified-ty-type qualified-type)
              (loop :for pred :in (tc:qualified-ty-predicates qualified-type)
                    :collect (tc:make-ty-predicate :class (tc:ty-predicate-class pred)
                                                   :types (tc:ty-predicate-types pred)
                                                   :location (source:location var)))))))

(defun tc-env-add-definition (env name scheme)
  "Add a type named NAME to ENV."
  (declare (type tc-env env)
           (type symbol name)
           (type tc:ty-scheme scheme)
           (values null))
  (when (gethash name (tc-env-ty-table env))
    (util:coalton-bug "Attempt to add already defined type with name ~S." name))
  (setf (gethash name (tc-env-ty-table env)) scheme)
  nil)

(defun tc-env-bound-variables (env)
  (declare (type tc-env env)
           (values util:symbol-list &optional))
  (alexandria:hash-table-keys (tc-env-ty-table env)))

(defun tc-env-bindings-variables (env names)
  (declare (type tc-env env)
           (type util:symbol-list names)
           (values tc:tyvar-list))

  (remove-duplicates
   (loop :with table := (tc-env-ty-table env)
         :for name :in names
         :for ty := (gethash name table)
         :unless ty
           :do (util:coalton-bug "Unknown binding ~A" name)
         :append (tc:type-variables ty))
   :test #'eq))

(defun tc-env-replace-type (env name scheme)
  (declare (type tc-env env)
           (type symbol name)
           (type tc:ty-scheme scheme)
           (values null))

  (unless (gethash name (tc-env-ty-table env))
    (util:coalton-bug "Attempt to replace unknown type ~S" name))

  (setf (gethash name (tc-env-ty-table env)) scheme)

  nil)

(defmethod tc:apply-substitution (subs (env tc-env))
  "Applies SUBS to the types currently being checked in ENV. Does not update the types in the inner main environment because there should not be substitutions for them."
  (maphash
   (lambda (key value)
     (setf (gethash key (tc-env-ty-table env)) (tc:apply-substitution subs value)))
   (tc-env-ty-table env)))

(defmethod tc:type-variables ((env tc-env))
  "Returns all of the type variables of the types being checked in ENV. Does not return type variables from the inner main environment because it should not contain any free type variables."
  (loop :for ty :being :the :hash-values :of (tc-env-ty-table env)
        :append (tc:type-variables ty)))

;;;
;;; Level Management for Algebraic Subtyping
;;;

(defun tc-env-enter-level (env)
  "Enter a new level scope for let-polymorphism.
Returns the previous level for restoration."
  (declare (type tc-env env)
           (values fixnum))
  (let ((prev-level (tc-env-level env)))
    (incf (tc-env-level env))
    prev-level))

(defun tc-env-exit-level (env prev-level)
  "Exit to a previous level scope.
PREV-LEVEL should be the value returned by tc-env-enter-level."
  (declare (type tc-env env)
           (type fixnum prev-level)
           (values null))
  (setf (tc-env-level env) prev-level)
  nil)

(defmacro with-tc-env-level ((env) &body body)
  "Execute BODY at an increased level for let-polymorphism.

Type variables created within this scope will have a higher level,
enabling them to be generalized when exiting."
  (let ((prev-level (gensym "PREV-LEVEL"))
        (env-var (gensym "ENV")))
    `(let* ((,env-var ,env)
            (,prev-level (tc-env-enter-level ,env-var)))
       (unwind-protect
            (progn ,@body)
         (tc-env-exit-level ,env-var ,prev-level)))))

;;;
;;; Subtyping-aware variable creation
;;;

(defun tc-env-add-variable-sub (env name)
  "Add a variable named NAME to ENV using algebraic subtyping.
Creates a tyvar-sub at the current level instead of a regular tyvar."
  (declare (type tc-env env)
           (type symbol name)
           (values tc:tyvar-sub))

  (when (gethash name (tc-env-ty-table env))
    (util:coalton-bug "Attempt to add already defined variable with name ~S." name))

  ;; Create a tyvar-sub at the current level
  (let ((var (tc:make-variable-at-level tc:+kstar+ (tc-env-level env))))
    (setf (gethash name (tc-env-ty-table env))
          (tc:to-scheme var))
    var))

(defun tc-env-lookup-value-sub (env var)
  "Lookup the type of a variable named VAR in ENV.
Uses algebraic subtyping instantiation (creates tyvar-sub at current level)."
  (declare (type tc-env env)
           (type parser:node-variable var)
           (values tc:ty tc:ty-predicate-list))

  (let* ((var-name (parser:node-variable-name var))
         (scheme (or (gethash var-name (tc-env-ty-table env))
                     (tc:lookup-value-type (tc-env-env env) var-name :no-error t))))
    (unless scheme
      ;; Variable is unbound: create an error
      (apply #'tc:tc-error (format nil "Unknown variable ~a" var-name)
             (cons (source:note (source:location var)
                                (format nil "unknown variable ~a" var-name))
                   (loop :for suggestion :in (tc-env-suggest-value env var-name)
                         :collect (source:help (source:location var) #'identity suggestion)))))
    ;; Use fresh-inst-sub for subtyping instantiation
    (let ((qualified-type (tc:fresh-inst-sub scheme (tc-env-level env))))
      (values (tc:qualified-ty-type qualified-type)
              (loop :for pred :in (tc:qualified-ty-predicates qualified-type)
                    :collect (tc:make-ty-predicate :class (tc:ty-predicate-class pred)
                                                   :types (tc:ty-predicate-types pred)
                                                   :location (source:location var)))))))

;;;
;;; Expansion Constraint Application
;;;
;;; After macro expansion, any type constraints accumulated in the expansion
;;; context need to be applied to the typechecker. This bridges the hygiene
;;; system with the type system.
;;;

(defun apply-expansion-constraints (constraints env)
  "Apply accumulated type constraints from macro expansion to the typechecker.

CONSTRAINTS is a list of type-constraint structures from an expansion context.
ENV is the tc-env to apply constraints in.

Each constraint specifies:
- :SUBTYPE  - The syntax's type must be a subtype of the constraint type
- :SUPERTYPE - The constraint type must be a subtype of the syntax's type
- :EQUAL    - The syntax's type must equal the constraint type

Returns NIL. Type errors are signaled via the normal typechecker mechanism."
  (declare (type list constraints)
           (type tc-env env)
           (values null))
  (dolist (constraint constraints)
    (let* ((stx (macro:type-constraint-syntax constraint))
           (kind (macro:type-constraint-kind constraint))
           (constraint-type (macro:type-constraint-type constraint))
           ;; Get the type attached to the syntax object, if any
           (type-info (parser:syntax-object-type-info stx)))
      (when type-info
        (let ((stx-type (parser:type-attachment-type type-info)))
          (ecase kind
            (:subtype
             ;; stx-type <: constraint-type
             (tc:constrain stx-type constraint-type (tc-env-level env)))
            (:supertype
             ;; constraint-type <: stx-type
             (tc:constrain constraint-type stx-type (tc-env-level env)))
            (:equal
             ;; stx-type = constraint-type (constrain both directions)
             (tc:constrain stx-type constraint-type (tc-env-level env))
             (tc:constrain constraint-type stx-type (tc-env-level env))))))))
  nil)
