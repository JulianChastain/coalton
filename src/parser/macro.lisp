(defpackage #:coalton-impl/parser/macro
  (:use
   #:cl
   #:coalton-impl/parser/base
   #:coalton-impl/parser/types
   #:coalton-impl/parser/pattern)
  (:shadowing-import-from
   #:coalton-impl/parser/base
   #:parse-error)
  (:local-nicknames
   (#:cst #:concrete-syntax-tree)
   (#:scope #:coalton-impl/parser/scope)
   (#:stx #:coalton-impl/parser/syntax-object)
   (#:stx-cst #:coalton-impl/parser/syntax-cst))
  (:export
   #:expand-macro
   #:expand-macro-hygienic
   #:expand-macro-hygienic-wrapper
   #:make-cl-macro-transformer
   #:syntax->cst
   #:*use-hygienic-macros*

   ;; Expansion context (Phase 2: Intentional Capture)
   #:expansion-context                    ; STRUCT
   #:expansion-context-p                  ; PREDICATE
   #:expansion-context-intro-scope        ; ACCESSOR
   #:expansion-context-use-scope          ; ACCESSOR
   #:expansion-context-level              ; ACCESSOR
   #:expansion-context-type-bindings      ; ACCESSOR
   #:expansion-context-type-constraints   ; ACCESSOR
   #:*current-expansion-context*          ; VARIABLE
   #:syntax-local-introduce               ; FUNCTION
   #:make-syntax-introducer               ; FUNCTION
   #:expand-macro-hygienic/ctx            ; FUNCTION

   ;; Type constraint tracking
   #:type-constraint                      ; STRUCT
   #:make-type-constraint                 ; CONSTRUCTOR
   #:type-constraint-syntax               ; ACCESSOR
   #:type-constraint-kind                 ; ACCESSOR
   #:type-constraint-type                 ; ACCESSOR
   #:add-expansion-constraint             ; FUNCTION
   #:apply-expansion-constraints          ; FUNCTION

   ;; Local Expansion Control (Phase 3)
   #:local-expand                         ; FUNCTION
   #:syntax-local-value                   ; FUNCTION
   #:define-compile-time-value            ; FUNCTION
   #:*compile-time-bindings*              ; VARIABLE
   #:+local-expand-max-depth+             ; CONSTANT

   ;; Advanced Features (Phase 6)
   #:syntax-track-origin                  ; FUNCTION
   #:syntax-debug-info                    ; FUNCTION

   ;; Type-aware macro operations
   #:syntax-local-type                    ; FUNCTION
   #:syntax-local-constrain               ; FUNCTION
   ))

(in-package #:coalton-impl/parser/macro)

;;;
;;; Global State for Local Expansion Control (Phase 3)
;;;

(defvar *compile-time-bindings* (make-hash-table :test 'eq)
  "Compile-time binding table mapping symbols to their transformer values.
These are custom bindings that can be retrieved with syntax-local-value.")

(defvar *local-expand-depth* 0
  "Current depth of local-expand recursion.")

(defconstant +local-expand-max-depth+ 1000
  "Maximum recursion depth for local-expand.")

(defun expand-macro (form source)
  "Expand the macro in FORM using MACROEXPAND-1, trying our best to preserve source information."
  (declare (type stx:syntax-object form)
           (values stx:syntax-object &optional))
  (let (;; Fallback to the macro source if unable to find something more specific.
        (fallback-source (stx-cst:stx-source form))
        ;; Table mapping forms within FORM to their sources. We will
        ;; check pointer equality of forms in the output of the macro
        ;; to these to retrieve source information.
        (source-table (make-hash-table :test #'eq)))
    (fill-source-table form source-table (make-hash-table :test #'eq))
    (handler-case
        (rebuild-syntax (macroexpand-1 (stx:syntax->datum form))
                        source-table
                        fallback-source
                        (make-hash-table :test #'eq))
      (error (condition)
        (parse-error "Error during macro expansion"
                     (note source form (princ-to-string condition)))))))

(defun fill-source-table (stx source-table seen-forms)
  "Fill SOURCE-TABLE with source information in STX and its children."
  (declare (type stx:syntax-object stx)
           (type hash-table source-table))
  (cond
    ;; If we have already seen this form then skip it.
    ((gethash stx seen-forms)
     nil)
    (t
     (setf (gethash stx seen-forms) t)
     ;; When forms appear multiple times the later ones don't have any
     ;; source information. We can safely ignore these.
     (let ((datum (stx:syntax-e stx)))
       (unless (or (null datum)
                   (nth-value 1 (gethash datum source-table)))
         (setf (gethash datum source-table) (stx-cst:stx-source stx)))
       (when (and (listp datum) datum)
         (dolist (child datum)
           (when (stx:syntax-object-p child)
             (fill-source-table child source-table seen-forms))))))))

(defun rebuild-syntax (form source-table fallback-source seen-forms)
  "Rebuild a syntax object from the expanded FORM.

SOURCE-TABLE contains a pointer mapping from macro input forms to source information.
FALLBACK-SOURCE is the source information of the macro to use as a fallback.
SEEN-FORMS is a hash table of known forms to prevent hang on cyclical list forms."
  (declare (type (or atom list) form)
           (type hash-table source-table seen-forms)
           (type cons fallback-source)
           (values stx:syntax-object &optional))
  (let ((source (gethash form source-table fallback-source)))
    (cond ((nth-value 1 (gethash form seen-forms))
           (values (gethash form seen-forms)))
          ((atom form)
           (let ((result (stx:make-syntax-object form :source source)))
             (setf (gethash form seen-forms) result)
             result))
          (t
           (let ((result (stx:make-syntax-object
                          (mapcar (lambda (elem)
                                    (rebuild-syntax elem source-table fallback-source seen-forms))
                                  form)
                          :source source)))
             (setf (gethash form seen-forms) result)
             result)))))

;;;
;;; Hygienic Macro Expansion
;;;
;;; This implements the "sets of scopes" hygiene algorithm from Flatt (POPL 2016).
;;; The key insight is that hygiene can be achieved by tracking scope sets on
;;; syntax objects and using the "flip" operation during expansion.
;;;

(defvar *use-hygienic-macros* t
  "When T, use hygienic macro expansion. When NIL, use traditional expansion.
This is a feature flag for gradual rollout.")

;;;
;;; Expansion Context
;;;
;;; The expansion context tracks the scopes created during a single macro
;;; expansion. This enables intentional capture via syntax-local-introduce.
;;;

(defstruct (expansion-context
            (:copier nil)
            (:constructor %make-expansion-context (use-scope intro-scope level type-bindings)))
  "Context for a single macro expansion, tracking scopes and types for hygiene.

USE-SCOPE is the scope added to input syntax before the transformer runs.
INTRO-SCOPE is the scope flipped on output syntax after the transformer runs.
LEVEL is the let-polymorphism level for type variable creation.
TYPE-BINDINGS is a type-binding-table for hygienic type variable resolution.
TYPE-CONSTRAINTS is a list of type constraints accumulated during expansion."
  (use-scope         nil :type scope:scope-token :read-only t)
  (intro-scope       nil :type scope:scope-token :read-only t)
  (level             0   :type fixnum :read-only t)
  (type-bindings     nil :type t :read-only t)  ; type-binding-table from binding-table
  ;; Mutable: constraints accumulate during expansion
  (type-constraints  nil :type list))

;;;
;;; Type Constraint Structure
;;;
;;; Type constraints are accumulated during macro expansion and applied
;;; after expansion completes. This enables type-directed macro expansion.
;;;

(defstruct (type-constraint
            (:copier nil)
            (:constructor %make-type-constraint (syntax kind type)))
  "A type constraint recorded during macro expansion.

SYNTAX is the syntax object that is constrained.
KIND is :SUBTYPE, :SUPERTYPE, or :EQUAL indicating the constraint direction.
TYPE is the type to constrain against."
  (syntax (error "syntax required") :type stx:syntax-object :read-only t)
  (kind   (error "kind required")   :type keyword :read-only t)
  (type   (error "type required")   :type t :read-only t))

(defun make-type-constraint (syntax kind type)
  "Create a type constraint for SYNTAX.

KIND is :SUBTYPE (syntax <: type), :SUPERTYPE (type <: syntax), or :EQUAL."
  (declare (type stx:syntax-object syntax)
           (type keyword kind)
           (values type-constraint))
  (%make-type-constraint syntax kind type))

(defmethod print-object ((obj type-constraint) stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "~S ~A ~S"
            (stx:syntax-e (type-constraint-syntax obj))
            (type-constraint-kind obj)
            (type-constraint-type obj))))

(defvar *current-expansion-context* nil
  "The expansion context for the currently executing macro transformer.
Bound during calls to the transformer in expand-macro-hygienic/ctx.
NIL when not inside a macro expansion.")

(defun add-expansion-constraint (syntax kind type)
  "Add a type constraint to the current expansion context.

SYNTAX is the syntax object being constrained.
KIND is :SUBTYPE, :SUPERTYPE, or :EQUAL.
TYPE is the type to constrain against.

Signals an error if called outside of macro expansion."
  (declare (type stx:syntax-object syntax)
           (type keyword kind)
           (values type-constraint))
  (unless *current-expansion-context*
    (error "add-expansion-constraint: not in a macro expansion context"))
  (let ((constraint (%make-type-constraint syntax kind type)))
    (push constraint (expansion-context-type-constraints *current-expansion-context*))
    constraint))

(defun syntax-local-introduce (stx)
  "Flip the current expansion's intro scope on STX.

This is the key operation for intentional hygiene breaking. When called
during macro expansion:

- For syntax introduced by the macro (which will get intro-scope flipped on
  after the transformer returns), calling syntax-local-introduce pre-flips
  the scope so the post-flip removes it, making the syntax visible to user code.

- For user-supplied syntax (which won't have intro-scope), calling
  syntax-local-introduce adds the intro scope, making it invisible to the
  macro's own bindings.

Example use case - anaphoric 'aif' macro:
  The macro introduces 'it' bound to the test result. By calling
  (syntax-local-introduce (make-identifier-syntax 'it)), the 'it' identifier
  won't get the intro scope after expansion, so user code can reference it.

Signals an error if called outside of a macro expansion context."
  (declare (type stx:syntax-object stx)
           (values stx:syntax-object))
  (unless *current-expansion-context*
    (error "syntax-local-introduce: not in a macro expansion context"))
  (stx:stx-flip-scope stx (expansion-context-intro-scope *current-expansion-context*)))

(defun make-syntax-introducer (&optional scope)
  "Create an introducer function for the given SCOPE.

If SCOPE is NIL, creates a fresh scope token.

Returns a function that takes a syntax object and an optional MODE:
  :flip (default) - Flip the scope (add if absent, remove if present)
  :add            - Add the scope unconditionally
  :remove         - Remove the scope unconditionally

This is useful for creating custom scope manipulations, for example
to implement definition contexts or module boundaries."
  (declare (type (or null scope:scope-token) scope)
           (values function))
  (let ((scope (or scope (scope:make-scope-token))))
    (lambda (stx &optional (mode :flip))
      (declare (type stx:syntax-object stx)
               (type (member :flip :add :remove) mode))
      (ecase mode
        (:flip   (stx:stx-flip-scope stx scope))
        (:add    (stx:stx-add-scope stx scope))
        (:remove (stx:stx-remove-scope stx scope))))))

(defun expand-macro-hygienic/ctx (stx transformer &key (level 0) type-bindings)
  "Expand STX using TRANSFORMER with hygienic scope tracking and context.

Like expand-macro-hygienic, but binds *current-expansion-context* during
the transformer call, enabling the use of syntax-local-introduce.

LEVEL is the let-polymorphism level for type variable creation.
TYPE-BINDINGS is an optional type-binding-table for hygienic type resolution.

The transformer receives a single argument (the scoped input syntax).
It can call syntax-local-introduce to break hygiene intentionally.

Returns two values:
1. The expanded syntax object
2. A list of type constraints accumulated during expansion"
  (declare (type stx:syntax-object stx)
           (type function transformer)
           (type fixnum level)
           (values stx:syntax-object list))
  (let* ((use-scope (scope:make-scope-token))
         (intro-scope (scope:make-scope-token))
         (ctx (%make-expansion-context use-scope intro-scope level type-bindings))
         ;; Step 1: Add use-site scope to entire input
         (input (stx:stx-add-scope stx use-scope))
         ;; Step 2: Call transformer with context bound
         (output (let ((*current-expansion-context* ctx))
                   (funcall transformer input)))
         ;; Step 3: Flip intro scope on output
         (result (stx:stx-flip-scope output intro-scope))
         ;; Collect accumulated constraints
         (constraints (expansion-context-type-constraints ctx)))
    ;; Also flip the use-site scope to remove it from passed-through syntax
    (values (stx:stx-flip-scope result use-scope)
            constraints)))

(defun expand-macro-hygienic (stx transformer)
  "Expand STX using TRANSFORMER with hygienic scope tracking.

This implements the core hygiene algorithm:
1. Create a fresh use-site scope and add it to the entire input
2. Call the transformer with the scoped input
3. Create a fresh intro scope and flip it on the entire output

The flip operation ensures:
- Syntax from the input has the use-site scope added then flipped away,
  returning to its original scopes
- Syntax introduced by the macro has the intro scope flipped on,
  distinguishing it from user code

STX must be a syntax-object. TRANSFORMER is a function that takes a
syntax-object and returns a syntax-object."
  (declare (type stx:syntax-object stx)
           (type function transformer)
           (values stx:syntax-object))
  (let* ((use-scope (scope:make-scope-token))
         (intro-scope (scope:make-scope-token))
         ;; Step 1: Add use-site scope to entire input
         (input (stx:stx-add-scope stx use-scope))
         ;; Step 2: Call transformer
         (output (funcall transformer input))
         ;; Step 3: Flip intro scope on output
         (result (stx:stx-flip-scope output intro-scope)))
    ;; Also flip the use-site scope to remove it from passed-through syntax
    (stx:stx-flip-scope result use-scope)))

(defun syntax->cst (stx fallback-source)
  "Convert a syntax object back to a CST for compatibility with existing parser.

This strips the syntax wrapper and rebuilds CST nodes, preserving source
information from the syntax objects where available."
  (declare (type stx:syntax-object stx)
           (values cst:cst))
  (let ((datum (stx:syntax-e stx))
        (source (or (stx:syntax-object-source stx) fallback-source)))
    (cond
      ((null datum)
       (make-instance 'cst:atom-cst :raw nil :source source))
      ((atom datum)
       (make-instance 'cst:atom-cst :raw datum :source source))
      (t
       ;; List: recursively convert elements
       (labels ((convert-list (elements)
                  (if (null elements)
                      (make-instance 'cst:atom-cst :raw nil :source source)
                      (let* ((first-elem (car elements))
                             (first-source (or (and (stx:syntax-object-p first-elem)
                                                    (stx:syntax-object-source first-elem))
                                               source)))
                        (make-instance 'cst:cons-cst
                                       :raw (mapcar (lambda (e)
                                                      (if (stx:syntax-object-p e)
                                                          (stx:syntax->datum e)
                                                          e))
                                                    elements)
                                       :source source
                                       :first (if (stx:syntax-object-p first-elem)
                                                  (syntax->cst first-elem fallback-source)
                                                  (make-instance 'cst:atom-cst
                                                                 :raw first-elem
                                                                 :source first-source))
                                       :rest (convert-list (cdr elements)))))))
         (convert-list datum))))))

;;;
;;; CL Macro Integration
;;;
;;; These functions bridge Common Lisp macros with the hygienic expansion system.
;;; They allow existing CL macros (including Coalton's) to be expanded hygienically.
;;;

(defun make-cl-macro-transformer (macro-form)
  "Create a transformer that calls CL macroexpand-1 on the macro form.

MACRO-FORM is the raw macro invocation form (a list starting with a macro name).
Returns a function that takes a syntax object and returns a syntax object."
  (declare (type (or symbol cons) macro-form)
           (ignore macro-form)
           (values function))
  (lambda (stx)
    (let* ((datum (stx:syntax->datum stx))
           (expanded (macroexpand-1 datum)))
      (stx:datum->syntax stx expanded))))

(defun expand-macro-hygienic-wrapper (form source)
  "Expand FORM hygienically using the sets-of-scopes algorithm.

FORM is a syntax object representing the macro invocation.
SOURCE is the source information context.

This is the main entry point for hygienic macro expansion in the parser.
It:
1. Creates a transformer that calls CL's macroexpand-1
2. Expands hygienically using the flip algorithm
3. Returns the expanded syntax object directly"
  (declare (type stx:syntax-object form)
           (values stx:syntax-object))
  (handler-case
      (let* ((transformer (make-cl-macro-transformer (stx:syntax->datum form)))
             (expanded-stx (expand-macro-hygienic form transformer)))
        expanded-stx)
    (parse-error (c) (error c))
    (error (condition)
      (parse-error "Error during macro expansion"
                   (note source form (princ-to-string condition))))))

;;;
;;; Local Expansion Control (Phase 3)
;;;
;;; These functions enable controlled macro expansion for macro-aware code walkers
;;; and type-directed macros.
;;;

(defun local-expand (stx &optional (stop-list nil) (context-stx nil))
  "Expand macros in STX until reaching forms in STOP-LIST.

STX is the syntax object to expand.
STOP-LIST is a list of symbols naming forms that should not be expanded.
CONTEXT-STX is optional syntax to inherit source context from.

Returns the partially expanded syntax object. Macros whose names appear
in STOP-LIST will not be expanded, but their subforms may be.

Example:
  (local-expand (datum->syntax ctx '(outer (inner x))) '(inner))
  ;; Expands 'outer' but stops at 'inner'"
  (declare (type stx:syntax-object stx)
           (type list stop-list)
           (ignore context-stx))
  ;; Check recursion depth
  (when (>= *local-expand-depth* +local-expand-max-depth+)
    (error "local-expand: maximum expansion depth exceeded"))
  (let ((datum (stx:syntax-e stx)))
    (cond
      ;; Atom: return as-is
      ((not (listp datum))
       stx)

      ;; Empty list: return as-is
      ((null datum)
       stx)

      ;; List form: check for macro
      (t
       (let* ((head-stx (first datum))
              ;; Handle both wrapped and unwrapped head elements
              (head (if (stx:syntax-object-p head-stx)
                        (stx:syntax-e head-stx)
                        head-stx)))
         (flet ((expand-child (sub)
                  (let ((*local-expand-depth* (1+ *local-expand-depth*)))
                    (if (stx:syntax-object-p sub)
                        (local-expand sub stop-list)
                        ;; Wrap raw datum in syntax object before expanding
                        (local-expand (stx:make-syntax-object sub
                                        :scopes (stx:syntax-object-scopes stx)
                                        :source (stx:syntax-object-source stx))
                                      stop-list)))))
           (cond
             ;; Head is symbol in stop-list: expand children but not this form
             ((and (symbolp head) (member head stop-list :test #'eq))
              (stx:make-syntax-object
               (cons head-stx
                     (mapcar #'expand-child (rest datum)))
               :scopes (stx:syntax-object-scopes stx)
               :source (stx:syntax-object-source stx)
               :properties (stx:syntax-object-properties stx)))

             ;; Head is macro: expand and recurse
             ((and (symbolp head) (macro-function head))
              (let* ((transformer (make-cl-macro-transformer datum))
                     (expanded (expand-macro-hygienic/ctx stx transformer))
                     (*local-expand-depth* (1+ *local-expand-depth*)))
                (local-expand expanded stop-list)))

             ;; Not a macro: recurse on children
             (t
              (stx:make-syntax-object
               (mapcar #'expand-child datum)
               :scopes (stx:syntax-object-scopes stx)
               :source (stx:syntax-object-source stx)
               :properties (stx:syntax-object-properties stx))))))))))

(defun syntax-local-value (id &optional failure-thunk)
  "Get the compile-time value bound to identifier ID.

ID must be an identifier syntax object.
FAILURE-THUNK, if provided, is called with no arguments when ID has
no compile-time binding. If not provided, an error is signaled.

Returns the compile-time value (typically a macro transformer function).

This checks both the custom compile-time bindings table and CL's
macro-function for the identifier's symbol."
  (declare (type stx:syntax-object id))
  (unless (stx:identifier? id)
    (error "syntax-local-value: expected identifier, got ~S" id))
  (let* ((sym (stx:identifier-symbol id))
         (value (or (gethash sym *compile-time-bindings*)
                    (macro-function sym))))
    (cond
      (value value)
      (failure-thunk (funcall failure-thunk))
      (t (error "syntax-local-value: no binding for ~S" sym)))))

(defun define-compile-time-value (sym value)
  "Bind SYM to VALUE in the compile-time binding table.

This allows associating compile-time values with symbols that are not
CL macros. These values can be retrieved with syntax-local-value."
  (declare (type symbol sym))
  (setf (gethash sym *compile-time-bindings*) value))

;;;
;;; Advanced Features (Phase 6)
;;;
;;; These functions provide production-quality debugging and aliasing support.
;;;

(defun syntax-track-origin (result-stx origin-stx)
  "Attach ORIGIN-STX as the origin of RESULT-STX.

This is used to track where macro-expanded code came from, enabling better
error messages that point to the macro use site rather than the expanded code.

RESULT-STX is the syntax object to annotate (typically macro output).
ORIGIN-STX is the syntax object representing the original source
(typically the macro invocation).

Returns a new syntax object with the :origin property set. The origin can be
retrieved later using (stx-property result :origin).

Example:
  (syntax-track-origin expanded-code macro-call)
  ;; Later, when reporting an error in expanded-code:
  ;; (stx-property expanded-code :origin) => macro-call"
  (declare (type stx:syntax-object result-stx origin-stx)
           (values stx:syntax-object))
  (stx:stx-with-property result-stx :origin origin-stx))

(defun syntax-debug-info (stx &optional (stream nil))
  "Return a string describing STX's hygiene information for debugging.

This is useful for understanding macro expansion issues and hygiene problems.
The output includes:
- The datum (the underlying value)
- All scopes and their IDs
- Source location if available
- Properties

If STREAM is provided, writes directly to it. Otherwise returns a string.

Example output:
  Syntax Object Debug Info:
    Datum: FOO
    Scopes: {1 3 7}
    Source: (10 . 25)
    Properties: ((ORIGIN . #<SYNTAX-OBJECT ...>))"
  (declare (type stx:syntax-object stx)
           (values (or string null)))
  (let ((datum (stx:syntax-e stx))
        (scopes (stx:syntax-object-scopes stx))
        (source (stx:syntax-object-source stx))
        (properties (stx:syntax-object-properties stx)))
    (flet ((format-it (s)
             (format s "Syntax Object Debug Info:~%")
             (format s "  Datum: ~S~%" datum)
             (format s "  Scopes: {~{~A~^ ~}}~%"
                     (mapcar #'scope:scope-token-id (scope:scope-set->list scopes)))
             (format s "  Source: ~S~%" source)
             (format s "  Properties: ~S~%" properties)
             (when (stx:identifier? stx)
               (format s "  Is Identifier: T~%")
               (format s "  Symbol: ~S~%" (stx:identifier-symbol stx)))))
      (if stream
          (progn (format-it stream) nil)
          (with-output-to-string (s)
            (format-it s))))))

;;;
;;; Type-Aware Macro Operations
;;;
;;; These functions enable macros to interact with the type system,
;;; querying types and adding constraints during expansion.
;;;

(defun syntax-local-type (stx)
  "Get the type of STX if available.

Returns the type attachment from STX, or NIL if no type information
is attached. Type information is typically attached during or after
type inference.

This function is useful for macros that need to generate code
based on the type of an expression. For example, a 'print' macro
might dispatch to different printing functions based on the type.

Example:
  (let ((type-info (syntax-local-type expr-stx)))
    (when type-info
      (let ((ty (stx:type-attachment-type type-info)))
        ;; Use ty to inform code generation
        ...)))

Note: This returns the cached type attachment. It does not trigger
type inference. Use in contexts where type information has already
been computed."
  (declare (type stx:syntax-object stx)
           (values (or null stx:type-attachment)))
  (stx:syntax-object-type-info stx))

(defun syntax-local-constrain (stx type &optional (kind :subtype))
  "Record a type constraint on STX for later processing.

STX is the syntax object to constrain.
TYPE is the type to constrain against.
KIND is one of :SUBTYPE (STX <: TYPE), :SUPERTYPE (TYPE <: STX), or :EQUAL.

This function records the constraint in the current expansion context's
constraint list. The constraints are applied after macro expansion completes.

Returns STX with a :type-constraint property added for constraint tracking.

Example usage in a macro:
  ;; Ensure the argument is a subtype of Integer
  (syntax-local-constrain arg-stx integer-type :subtype)

Note: This function requires an active expansion context. Signals an
error if called outside of macro expansion."
  (declare (type stx:syntax-object stx)
           (type (member :subtype :supertype :equal) kind)
           (values stx:syntax-object))
  (unless *current-expansion-context*
    (error "syntax-local-constrain: not in a macro expansion context"))
  ;; Record the constraint as a property on the syntax object
  ;; The constraint will be processed when the expansion context is applied
  (stx:stx-with-property
   stx :type-constraint
   (list :type type :kind kind)))
