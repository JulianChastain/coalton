;;;; Syntax objects for hygienic macro expansion
;;;;
;;;; A syntax object wraps a datum (symbol, list, or atom) with:
;;;; - A scope set for hygiene tracking
;;;; - Source location information (from CST)
;;;; - Optional properties for metadata
;;;;
;;;; This is the core data structure for implementing Racket-style
;;;; hygienic macros using the "sets of scopes" algorithm.

(defpackage #:coalton-impl/parser/syntax-object
  (:use #:cl)
  (:local-nicknames
   (#:cst #:concrete-syntax-tree)
   (#:source #:coalton-impl/source)
   (#:util #:coalton-impl/util)
   (#:scope #:coalton-impl/parser/scope))
  (:export
   ;; Syntax object type
   #:syntax-object                        ; STRUCT
   #:make-syntax-object                   ; CONSTRUCTOR
   #:syntax-object-p                      ; PREDICATE
   #:syntax-object-datum                  ; ACCESSOR
   #:syntax-object-scopes                 ; ACCESSOR
   #:syntax-object-source                 ; ACCESSOR
   #:syntax-object-properties             ; ACCESSOR

   ;; Core operations
   #:syntax-e                             ; FUNCTION - extract datum
   #:syntax->datum                        ; FUNCTION - recursively strip wrappers
   #:datum->syntax                        ; FUNCTION - copy scopes from context

   ;; Scope manipulation
   #:stx-add-scope                        ; FUNCTION
   #:stx-remove-scope                     ; FUNCTION
   #:stx-flip-scope                       ; FUNCTION

   ;; Property access
   #:stx-property                         ; FUNCTION
   #:stx-with-property                    ; FUNCTION

   ;; Constructors
   #:make-identifier-syntax               ; FUNCTION
   #:make-atom-syntax                     ; FUNCTION
   #:make-list-syntax                     ; FUNCTION

   ;; Identifier predicates
   #:identifier?                          ; FUNCTION

   ;; Identifier comparison (Phase 1 of Racket parity)
   #:free-identifier=?                    ; FUNCTION
   #:bound-identifier=?                   ; FUNCTION
   #:identifier-symbol                    ; FUNCTION

   ;; Rename transformers (Phase 6)
   #:rename-transformer                   ; STRUCT
   #:rename-transformer-p                 ; PREDICATE
   #:make-rename-transformer              ; FUNCTION
   #:rename-transformer-target            ; ACCESSOR
   #:apply-rename-transformer             ; FUNCTION
   ))

(in-package #:coalton-impl/parser/syntax-object)

;;;
;;; Syntax Object Structure
;;;

(defstruct (syntax-object
            (:copier nil)
            (:constructor %make-syntax-object (datum scopes source properties)))
  "A syntax object wrapping a datum with hygiene and source information.

DATUM is the underlying value: a symbol, number, string, or list of syntax objects.
SCOPES is the scope-set tracking lexical context for hygiene.
SOURCE is the source location (span) from the CST, or NIL.
PROPERTIES is an alist of metadata key-value pairs."
  (datum      (util:required 'datum)      :type t :read-only t)
  (scopes     (util:required 'scopes)     :type scope:scope-set :read-only t)
  (source     nil                         :type (or null cons) :read-only t)
  (properties nil                         :type list :read-only t))

(defmethod make-load-form ((self syntax-object) &optional env)
  (make-load-form-saving-slots self :environment env))

(defun make-syntax-object (datum &key
                                   (scopes (scope:empty-scope-set))
                                   source
                                   properties)
  "Create a syntax object wrapping DATUM.

SCOPES defaults to the empty scope set.
SOURCE is the source location span (cons of start/end offsets), or NIL.
PROPERTIES is an alist of metadata."
  (declare (type scope:scope-set scopes)
           (type (or null cons) source)
           (type list properties)
           (values syntax-object))
  (%make-syntax-object datum scopes source properties))

(defmethod print-object ((obj syntax-object) stream)
  (print-unreadable-object (obj stream :type t)
    (let ((datum (syntax-object-datum obj)))
      (if (and (listp datum) (> (length datum) 3))
          (format stream "(~{~S ~}...)" (subseq datum 0 3))
          (format stream "~S" datum)))))

;;;
;;; Core Operations
;;;

(defun syntax-e (stx)
  "Extract the datum from a syntax object.

This is the shallow extraction - if the datum is a list, the elements
are still syntax objects. Use SYNTAX->DATUM for recursive extraction."
  (declare (type syntax-object stx)
           (values t))
  (syntax-object-datum stx))

(defun syntax->datum (stx)
  "Recursively strip syntax object wrappers, returning the underlying datum.

For a syntax object containing a list, this recursively extracts all
nested syntax objects. Non-syntax-object values are returned as-is."
  (declare (values t))
  (typecase stx
    (syntax-object
     (let ((datum (syntax-object-datum stx)))
       (if (listp datum)
           (mapcar #'syntax->datum datum)
           datum)))
    (t stx)))

(defun datum->syntax (context datum &key source)
  "Create a syntax object from DATUM, copying scopes from CONTEXT.

This is the hygiene-breaking operation: it allows a macro to
intentionally capture or inject identifiers by giving a raw datum
the scopes of an existing syntax object.

CONTEXT is a syntax object whose scopes will be copied.
DATUM is the raw value to wrap.
SOURCE is an optional source location for the new syntax object."
  (declare (type syntax-object context)
           (values syntax-object))
  (let ((scopes (syntax-object-scopes context))
        (src (or source (syntax-object-source context))))
    (labels ((convert (d)
               (typecase d
                 (syntax-object d)  ; Already a syntax object, leave it
                 (cons
                  (%make-syntax-object
                   (mapcar #'convert d)
                   scopes
                   src
                   nil))
                 (t
                  (%make-syntax-object d scopes src nil)))))
      (convert datum))))

;;;
;;; Scope Manipulation
;;;
;;; These operations recursively traverse syntax objects, adding or
;;; flipping scopes throughout the structure. This is essential for
;;; the hygiene algorithm.
;;;

(defun stx-add-scope (stx token)
  "Return a new syntax object with TOKEN added to its scope set.

This recursively adds the scope to all nested syntax objects."
  (declare (type syntax-object stx)
           (type scope:scope-token token)
           (values syntax-object))
  (let ((datum (syntax-object-datum stx)))
    (%make-syntax-object
     (if (listp datum)
         (mapcar (lambda (elem) (stx-add-scope elem token)) datum)
         datum)
     (scope:scope-set-add (syntax-object-scopes stx) token)
     (syntax-object-source stx)
     (syntax-object-properties stx))))

(defun stx-remove-scope (stx token)
  "Return a new syntax object with TOKEN removed from its scope set.

This recursively removes the scope from all nested syntax objects."
  (declare (type syntax-object stx)
           (type scope:scope-token token)
           (values syntax-object))
  (let ((datum (syntax-object-datum stx)))
    (%make-syntax-object
     (if (listp datum)
         (mapcar (lambda (elem) (stx-remove-scope elem token)) datum)
         datum)
     (scope:scope-set-remove (syntax-object-scopes stx) token)
     (syntax-object-source stx)
     (syntax-object-properties stx))))

(defun stx-flip-scope (stx token)
  "Return a new syntax object with TOKEN flipped in its scope set.

Flipping adds the scope if absent, removes it if present.
This recursively flips the scope in all nested syntax objects.

This is the key operation for macro hygiene:
- Input syntax has a use-site scope added before expansion
- Output syntax has an intro scope flipped after expansion
- The result: input syntax returns to its original scopes (use-site added then removed)
  while introduced syntax gains the intro scope."
  (declare (type syntax-object stx)
           (type scope:scope-token token)
           (values syntax-object))
  (let ((datum (syntax-object-datum stx)))
    (%make-syntax-object
     (if (listp datum)
         (mapcar (lambda (elem) (stx-flip-scope elem token)) datum)
         datum)
     (scope:scope-set-flip (syntax-object-scopes stx) token)
     (syntax-object-source stx)
     (syntax-object-properties stx))))

;;;
;;; Property Access
;;;

(defun stx-property (stx key &optional default)
  "Get the value of property KEY from STX, or DEFAULT if not found."
  (declare (type syntax-object stx)
           (type symbol key)
           (values t))
  (let ((pair (assoc key (syntax-object-properties stx))))
    (if pair
        (cdr pair)
        default)))

(defun stx-with-property (stx key value)
  "Return a new syntax object with property KEY set to VALUE."
  (declare (type syntax-object stx)
           (type symbol key)
           (values syntax-object))
  (let ((props (syntax-object-properties stx)))
    (%make-syntax-object
     (syntax-object-datum stx)
     (syntax-object-scopes stx)
     (syntax-object-source stx)
     (acons key value (remove key props :key #'car)))))

;;;
;;; Convenient Constructors
;;;

(defun make-identifier-syntax (symbol &key (scopes (scope:empty-scope-set)) source)
  "Create a syntax object wrapping a symbol (identifier)."
  (declare (type symbol symbol)
           (type scope:scope-set scopes)
           (values syntax-object))
  (%make-syntax-object symbol scopes source nil))

(defun make-atom-syntax (value &key (scopes (scope:empty-scope-set)) source)
  "Create a syntax object wrapping an atomic value (number, string, etc)."
  (declare (type scope:scope-set scopes)
           (values syntax-object))
  (%make-syntax-object value scopes source nil))

(defun make-list-syntax (elements &key (scopes (scope:empty-scope-set)) source)
  "Create a syntax object wrapping a list of syntax objects."
  (declare (type list elements)
           (type scope:scope-set scopes)
           (values syntax-object))
  (%make-syntax-object elements scopes source nil))

;;;
;;; Identifier Predicates and Comparison
;;;
;;; These operations are fundamental for macros that need to inspect
;;; or compare identifiers. They form the foundation for pattern matching
;;; and binding resolution in the hygiene system.
;;;

(defun identifier? (stx)
  "Return T if STX is an identifier (syntax object wrapping a symbol).

Excludes keywords and booleans (t, nil) - only regular symbols are identifiers."
  (declare (type syntax-object stx)
           (values boolean))
  (let ((datum (syntax-object-datum stx)))
    (and (symbolp datum)
         (not (keywordp datum))
         (not (eq datum t))
         (not (eq datum nil)))))

(defun identifier-symbol (stx)
  "Extract the symbol from an identifier syntax object.

Signals an error if STX is not an identifier."
  (declare (type syntax-object stx)
           (values symbol))
  (unless (identifier? stx)
    (error "identifier-symbol: expected identifier, got ~S" stx))
  (syntax-object-datum stx))

(defun free-identifier=? (id1 id2)
  "Return T if ID1 and ID2 refer to the same free binding.

Two identifiers are free-identifier=? if they have the same symbol name
AND the same scope sets. This means they would resolve to the same binding
in any context where both are in scope.

This is the primary comparison for checking if two identifiers refer to
the same variable, for example when a macro wants to check if an identifier
matches a keyword like 'else' or 'unquote'.

Example:
  ;; These are free-identifier=? if they have the same scopes
  (free-identifier=? (make-identifier-syntax 'x :scopes s1)
                     (make-identifier-syntax 'x :scopes s1))
  => T

  ;; Different scopes means different bindings
  (free-identifier=? (make-identifier-syntax 'x :scopes s1)
                     (make-identifier-syntax 'x :scopes s2))
  => NIL"
  (declare (type syntax-object id1 id2)
           (values boolean))
  (and (identifier? id1)
       (identifier? id2)
       (eq (syntax-object-datum id1) (syntax-object-datum id2))
       (scope:scope-set-equal (syntax-object-scopes id1)
                              (syntax-object-scopes id2))))

(defun bound-identifier=? (id1 id2)
  "Return T if ID1 and ID2 would create the same binding.

Two identifiers are bound-identifier=? if binding one would shadow
the other. In the sets-of-scopes model, this occurs when they have
the same symbol name AND the same scope sets.

This is primarily used for checking if a macro-introduced binding
would conflict with an existing one, or for implementing binding
constructs that need to detect duplicate bindings.

In the current implementation, bound-identifier=? is equivalent to
free-identifier=? because Coalton uses a single namespace. In Racket,
these can differ due to module imports and rename transformers.

Example:
  (let ((x 1))
    (let ((x 2))  ; This x is NOT bound-identifier=? to outer x
      ...))

  (my-macro x)
  ;; If macro introduces a binding for 'x', it should be
  ;; bound-identifier=? to any 'x' it wants to shadow."
  (declare (type syntax-object id1 id2)
           (values boolean))
  ;; In the sets-of-scopes model, bound-identifier=? and free-identifier=?
  ;; are equivalent: same symbol + same scopes = same binding identity
  (free-identifier=? id1 id2))

;;;
;;; Rename Transformers (Phase 6)
;;;
;;; Rename transformers create aliases that redirect identifier uses
;;; to a target identifier, preserving hygiene information.
;;;

(defstruct (rename-transformer
            (:copier nil)
            (:constructor %make-rename-transformer (target)))
  "A transformer that redirects identifier uses to a target identifier.

TARGET is the identifier syntax object that uses will be redirected to."
  (target (error "target required") :type syntax-object :read-only t))

(defun make-rename-transformer (target-id)
  "Create a transformer that redirects uses of an identifier to TARGET-ID.

TARGET-ID must be an identifier syntax object. The returned transformer
can be used as a macro transformer that replaces uses of the aliased
identifier with the target identifier.

This is useful for:
- Creating identifier aliases
- Implementing re-exports with different names
- Certain forms of identifier macros

The transformer preserves the source location of the use site but
adopts the scopes from TARGET-ID for proper hygiene.

Example:
  ;; Create an alias 'my-fn' that redirects to 'original-fn'
  (let ((transformer (make-rename-transformer
                       (make-identifier-syntax 'original-fn))))
    ;; When (my-fn arg1 arg2) is encountered, it becomes (original-fn arg1 arg2)
    (funcall transformer (datum->syntax ctx '(my-fn arg1 arg2))))
  => #<SYNTAX-OBJECT (ORIGINAL-FN ARG1 ARG2)>"
  (declare (type syntax-object target-id)
           (values rename-transformer))
  (unless (identifier? target-id)
    (error "make-rename-transformer: TARGET-ID must be an identifier, got ~S" target-id))
  (%make-rename-transformer target-id))

;; rename-transformer-target is auto-generated by defstruct

(defun apply-rename-transformer (transformer stx)
  "Apply a rename transformer to a syntax object.

If STX is a list form (like a function call), replaces the first element
(the identifier being called) with the target identifier. The arguments
are preserved.

If STX is just an identifier, returns the target identifier with
the source location from STX.

TRANSFORMER is a rename-transformer created with make-rename-transformer.
STX is the syntax object representing the use of the aliased identifier.

Example:
  ;; If transformer targets 'real-name':
  (apply-rename-transformer transformer (datum->syntax ctx '(alias arg1 arg2)))
  => #<SYNTAX-OBJECT (REAL-NAME ARG1 ARG2)>"
  (declare (type rename-transformer transformer)
           (type syntax-object stx)
           (values syntax-object))
  (let ((target (rename-transformer-target transformer))
        (datum (syntax-e stx)))
    (cond
      ;; Single identifier: return target with use-site source
      ((identifier? stx)
       (%make-syntax-object
        (syntax-object-datum target)
        (syntax-object-scopes target)
        (or (syntax-object-source stx) (syntax-object-source target))
        (syntax-object-properties stx)))

      ;; List form: replace head with target
      ((and (listp datum) datum)
       (let ((args (rest datum)))
         (%make-syntax-object
          (cons target args)
          (syntax-object-scopes stx)
          (syntax-object-source stx)
          (syntax-object-properties stx))))

      ;; Unexpected: return as-is
      (t stx))))
