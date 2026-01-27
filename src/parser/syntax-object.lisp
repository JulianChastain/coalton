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
