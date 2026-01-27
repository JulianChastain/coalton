;;;; Definition contexts for hygienic macro expansion
;;;;
;;;; Definition contexts implement inside/outside edge scopes to prevent
;;;; hygiene violations in interleaved definitions within coalton-toplevel blocks.
;;;;
;;;; The problem: Without definition contexts, later definitions can incorrectly
;;;; shadow macro references:
;;;;
;;;;   (coalton-toplevel
;;;;     (define helper (fn (x) (+ x 1)))        ; binding 1
;;;;     (define-macro use-helper (stx)
;;;;       `(helper ,(stx-second stx)))          ; references binding 1
;;;;     (define helper (fn (x) (* x 2)))        ; binding 2 - shadows!
;;;;     (define result (use-helper 5)))         ; Should be 6, not 10
;;;;
;;;; Definition contexts apply scope edges so that later definitions cannot
;;;; capture references made by earlier macros.

(defpackage #:coalton-impl/parser/definition-context
  (:use #:cl)
  (:local-nicknames
   (#:scope #:coalton-impl/parser/scope)
   (#:stx #:coalton-impl/parser/syntax-object)
   (#:bt #:coalton-impl/parser/binding-table))
  (:export
   ;; Definition context type
   #:definition-context
   #:make-definition-context
   #:definition-context-p
   #:definition-context-inside-scope
   #:definition-context-outside-scope
   #:definition-context-parent
   #:definition-context-bindings

   ;; Operations
   #:syntax-local-make-definition-context
   #:definition-context-bind
   #:definition-context-lookup
   #:definition-context-introduce-binding
   #:definition-context-introduce-reference

   ;; Dynamic state
   #:*current-definition-context*))

(in-package #:coalton-impl/parser/definition-context)

;;;
;;; Global State
;;;

(defvar *current-definition-context* nil
  "The current definition context during toplevel processing.
Bound during coalton-toplevel expansion.")

;;;
;;; Definition Context Structure
;;;

(defstruct (definition-context
            (:copier nil)
            (:constructor %make-definition-context
                (inside-scope outside-scope parent bindings)))
  "Context for a block of interleaved definitions.

INSIDE-SCOPE: Scope added to bindings visible inside this block.
OUTSIDE-SCOPE: Scope added to prevent captures from outside.
PARENT: Enclosing definition context, or NIL.
BINDINGS: Binding table for this context's definitions (mutable slot, immutable table)."
  (inside-scope  (scope:make-scope-token) :type scope:scope-token :read-only t)
  (outside-scope (scope:make-scope-token) :type scope:scope-token :read-only t)
  (parent        nil :type (or null definition-context) :read-only t)
  (bindings      (bt:make-binding-table) :type bt:binding-table))  ; Not read-only

;; Provide a public constructor alias for tests
(defun make-definition-context (&key inside-scope outside-scope parent bindings)
  "Create a definition context with explicit parameters.
Primarily for testing; prefer SYNTAX-LOCAL-MAKE-DEFINITION-CONTEXT for normal use."
  (%make-definition-context
   (or inside-scope (scope:make-scope-token))
   (or outside-scope (scope:make-scope-token))
   parent
   (or bindings (bt:make-binding-table))))

(defmethod print-object ((obj definition-context) stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "inside=~A outside=~A~@[ parent=~A~]"
            (scope:scope-token-id (definition-context-inside-scope obj))
            (scope:scope-token-id (definition-context-outside-scope obj))
            (when (definition-context-parent obj)
              (scope:scope-token-id
               (definition-context-inside-scope (definition-context-parent obj)))))))

;;;
;;; Core Operations
;;;

(defun syntax-local-make-definition-context (&optional parent)
  "Create a new definition context, optionally nested in PARENT.

Creates fresh inside-scope and outside-scope tokens. If PARENT is provided,
bindings from PARENT are visible in the new context."
  (declare (values definition-context))
  (%make-definition-context
   (scope:make-scope-token)
   (scope:make-scope-token)
   (or parent *current-definition-context*)
   (bt:make-binding-table)))

(defun definition-context-bind (ctx name value &key source)
  "Add a binding for NAME to CTX with the inside-scope applied.

Returns the syntax object for the bound identifier (with inside-scope).
Note: The bindings slot is mutable; we replace it with a new immutable table."
  (declare (type definition-context ctx)
           (type symbol name)
           (values stx:syntax-object))
  (let* ((inside-scope (definition-context-inside-scope ctx))
         (scopes (scope:scope-set-add (scope:empty-scope-set) inside-scope))
         (binding (bt:make-scope-binding name scopes value :source source)))
    ;; Replace the binding table with a new one containing this binding
    (setf (definition-context-bindings ctx)
          (bt:binding-table-add-binding (definition-context-bindings ctx) binding))
    ;; Return identifier syntax with inside-scope
    (stx:make-identifier-syntax name :scopes scopes :source source)))

(defun definition-context-lookup (ctx id)
  "Look up identifier ID in CTX and its parents.

Returns a resolution-result from the binding table.
ID can be either a syntax object or a symbol."
  (declare (type definition-context ctx)
           (values bt:resolution-result))
  (let ((sym (if (stx:syntax-object-p id)
                 (stx:identifier-symbol id)
                 id))
        (scopes (if (stx:syntax-object-p id)
                    (stx:syntax-object-scopes id)
                    (scope:empty-scope-set))))
    (labels ((lookup-in (context)
               (when context
                 (let ((result (bt:binding-table-resolve
                                (definition-context-bindings context)
                                sym scopes)))
                   ;; Return if we found a binding or detected ambiguity
                   ;; Only continue to parent if truly unbound in this context
                   (if (bt:resolution-unbound-p result)
                       (lookup-in (definition-context-parent context))
                       result)))))
      (or (lookup-in ctx)
          (bt:make-resolution-unbound sym scopes)))))

(defun definition-context-introduce-binding (ctx stx)
  "Add inside-scope to STX for use as a binding site.

The inside-scope marks this identifier as defined within the context."
  (declare (type definition-context ctx)
           (type stx:syntax-object stx)
           (values stx:syntax-object))
  (stx:stx-add-scope stx (definition-context-inside-scope ctx)))

(defun definition-context-introduce-reference (ctx stx)
  "Add outside-scope to STX for a reference that should not be captured.

References with outside-scope cannot be captured by later definitions
that only have inside-scope."
  (declare (type definition-context ctx)
           (type stx:syntax-object stx)
           (values stx:syntax-object))
  (stx:stx-add-scope stx (definition-context-outside-scope ctx)))
