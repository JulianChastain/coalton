;;;; Binding table and resolution for hygienic macros
;;;;
;;;; The binding table maps (symbol, scope-set) pairs to bindings.
;;;; Resolution uses the "maximal subset" rule: find the binding whose
;;;; scope set is the largest subset of the reference's scopes.
;;;;
;;;; This implements the binding resolution algorithm from Flatt (POPL 2016).

(defpackage #:coalton-impl/parser/binding-table
  (:use #:cl)
  (:local-nicknames
   (#:util #:coalton-impl/util)
   (#:scope #:coalton-impl/parser/scope)
   (#:stx #:coalton-impl/parser/syntax-object))
  (:export
   ;; Scope binding type (named to avoid conflict with parser/binding)
   #:scope-binding                        ; STRUCT
   #:make-scope-binding                   ; CONSTRUCTOR
   #:scope-binding-name                   ; ACCESSOR
   #:scope-binding-scopes                 ; ACCESSOR
   #:scope-binding-value                  ; ACCESSOR
   #:scope-binding-source                 ; ACCESSOR

   ;; Binding table type
   #:binding-table                        ; STRUCT
   #:make-binding-table                   ; CONSTRUCTOR
   #:binding-table-add                    ; FUNCTION
   #:binding-table-add-binding            ; FUNCTION
   #:binding-table-resolve                ; FUNCTION
   #:binding-table-resolve-syntax         ; FUNCTION

   ;; Resolution results
   #:resolution-result                    ; TYPE
   #:resolution-unbound                   ; STRUCT
   #:resolution-unbound-p                 ; PREDICATE
   #:resolution-bound                     ; STRUCT
   #:resolution-bound-p                   ; PREDICATE
   #:resolution-ambiguous                 ; STRUCT
   #:resolution-ambiguous-p               ; PREDICATE
   #:resolution-result-binding            ; ACCESSOR
   #:resolution-result-candidates         ; ACCESSOR

   ;; Conditions
   #:unbound-identifier                   ; CONDITION
   #:ambiguous-identifier                 ; CONDITION
   ))

(in-package #:coalton-impl/parser/binding-table)

;;;
;;; Scope Binding Structure
;;;
;;; Named scope-binding to avoid conflict with coalton-impl/parser/binding
;;; which defines generic functions binding-name and binding-value.
;;;

(defstruct (scope-binding
            (:copier nil)
            (:constructor %make-scope-binding (name scopes value source)))
  "A binding associates an identifier with a value in a specific scope context.

NAME is the symbol being bound.
SCOPES is the scope-set at the binding site.
VALUE is the bound value (arbitrary data - could be a variable, type, etc).
SOURCE is the optional source location of the binding site."
  (name   (util:required 'name)   :type symbol :read-only t)
  (scopes (util:required 'scopes) :type scope:scope-set :read-only t)
  (value  (util:required 'value)  :type t :read-only t)
  (source nil                     :type (or null cons) :read-only t))

(defun make-scope-binding (name scopes value &key source)
  "Create a scope binding for NAME with SCOPES mapping to VALUE."
  (declare (type symbol name)
           (type scope:scope-set scopes)
           (values scope-binding))
  (%make-scope-binding name scopes value source))

(defmethod print-object ((obj scope-binding) stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "~S ~A" (scope-binding-name obj) (scope-binding-scopes obj))))

;;;
;;; Resolution Results
;;;
;;; Resolution can succeed with a unique binding, fail with no binding,
;;; or fail with multiple ambiguous bindings.
;;;

(defstruct (resolution-unbound
            (:copier nil)
            (:constructor make-resolution-unbound (name scopes)))
  "Resolution failed: no binding found for this identifier."
  (name   (util:required 'name)   :type symbol :read-only t)
  (scopes (util:required 'scopes) :type scope:scope-set :read-only t))

(defstruct (resolution-bound
            (:copier nil)
            (:constructor make-resolution-bound (binding)))
  "Resolution succeeded with a unique binding."
  (binding (util:required 'binding) :type scope-binding :read-only t))

(defun resolution-result-binding (result)
  "Extract the binding from a successful resolution result."
  (declare (type resolution-bound result)
           (values scope-binding))
  (resolution-bound-binding result))

(defstruct (resolution-ambiguous
            (:copier nil)
            (:constructor make-resolution-ambiguous (name scopes candidates)))
  "Resolution failed: multiple bindings are equally valid."
  (name       (util:required 'name)       :type symbol :read-only t)
  (scopes     (util:required 'scopes)     :type scope:scope-set :read-only t)
  (candidates (util:required 'candidates) :type list :read-only t))

(defun resolution-result-candidates (result)
  "Extract the candidate bindings from an ambiguous resolution result."
  (declare (type resolution-ambiguous result)
           (values list))
  (resolution-ambiguous-candidates result))

(deftype resolution-result ()
  "The result of binding resolution."
  '(or resolution-unbound resolution-bound resolution-ambiguous))

;;;
;;; Conditions
;;;

(define-condition unbound-identifier (error)
  ((name :initarg :name :reader unbound-identifier-name)
   (scopes :initarg :scopes :reader unbound-identifier-scopes))
  (:report (lambda (c s)
             (format s "Unbound identifier: ~S" (unbound-identifier-name c)))))

(define-condition ambiguous-identifier (error)
  ((name :initarg :name :reader ambiguous-identifier-name)
   (scopes :initarg :scopes :reader ambiguous-identifier-scopes)
   (candidates :initarg :candidates :reader ambiguous-identifier-candidates))
  (:report (lambda (c s)
             (format s "Ambiguous identifier: ~S has ~D possible bindings"
                     (ambiguous-identifier-name c)
                     (length (ambiguous-identifier-candidates c))))))

;;;
;;; Binding Table
;;;
;;; The table maps symbols to lists of scope-bindings. When resolving, we search
;;; through all bindings for that symbol to find matching scope sets.
;;;
;;; Implementation uses FSet maps for immutability.
;;;

(defstruct (binding-table
            (:copier nil)
            (:constructor %make-binding-table (data)))
  "An immutable table mapping identifiers to scope-bindings.

Internally, this maps each symbol to a list of scope-bindings, since the same
symbol can be bound in different scope contexts."
  (data (fset:empty-map) :type fset:map :read-only t))

(defun make-binding-table ()
  "Create an empty binding table."
  (declare (values binding-table))
  (%make-binding-table (fset:empty-map)))

(defun binding-table-add (table name scopes value &key source)
  "Add a binding to the table, returning a new table.

NAME is the symbol being bound.
SCOPES is the scope-set at the binding site.
VALUE is the bound value."
  (declare (type binding-table table)
           (type symbol name)
           (type scope:scope-set scopes)
           (values binding-table))
  (let* ((binding (%make-scope-binding name scopes value source))
         (data (binding-table-data table))
         (existing (fset:lookup data name))
         (new-list (cons binding (or existing nil))))
    (%make-binding-table (fset:with data name new-list))))

(defun binding-table-add-binding (table binding)
  "Add an existing scope-binding to the table, returning a new table."
  (declare (type binding-table table)
           (type scope-binding binding)
           (values binding-table))
  (let* ((name (scope-binding-name binding))
         (data (binding-table-data table))
         (existing (fset:lookup data name))
         (new-list (cons binding (or existing nil))))
    (%make-binding-table (fset:with data name new-list))))

;;;
;;; Binding Resolution
;;;
;;; The maximal subset rule:
;;; 1. Find all bindings for the symbol where binding-scopes ⊆ reference-scopes
;;; 2. If none: unbound
;;; 3. If one: return it
;;; 4. If multiple: select the one with the largest scope set
;;; 5. If multiple are maximal (none is a superset of all others): ambiguity
;;;

(defun find-candidates (table name scopes)
  "Find all bindings for NAME whose scopes are subsets of SCOPES."
  (declare (type binding-table table)
           (type symbol name)
           (type scope:scope-set scopes)
           (values list))
  (let ((bindings (fset:lookup (binding-table-data table) name)))
    (remove-if-not
     (lambda (binding)
       (scope:scope-set-subset-p (scope-binding-scopes binding) scopes))
     bindings)))

(defun find-maximal (candidates)
  "From CANDIDATES, find bindings with maximal scope sets.

A binding is maximal if no other candidate has a strictly larger scope set
that is still a subset. Returns the list of maximal bindings."
  (declare (type list candidates)
           (values list))
  (if (null candidates)
      nil
      (let ((maximal nil))
        (dolist (candidate candidates)
          (let ((dominated nil))
            ;; Check if this candidate is dominated by any current maximal
            (dolist (m maximal)
              (when (and (scope:scope-set-subset-p (scope-binding-scopes candidate)
                                                   (scope-binding-scopes m))
                         (not (scope:scope-set-equal (scope-binding-scopes candidate)
                                                     (scope-binding-scopes m))))
                (setf dominated t)
                (return)))
            (unless dominated
              ;; Remove any maximals that this candidate dominates
              (setf maximal
                    (remove-if
                     (lambda (m)
                       (and (scope:scope-set-subset-p (scope-binding-scopes m)
                                                      (scope-binding-scopes candidate))
                            (not (scope:scope-set-equal (scope-binding-scopes m)
                                                        (scope-binding-scopes candidate)))))
                     maximal))
              (push candidate maximal))))
        maximal)))

(defun binding-table-resolve (table name scopes)
  "Resolve NAME with SCOPES in TABLE, returning a resolution result.

Returns:
- RESOLUTION-UNBOUND if no binding is found
- RESOLUTION-BOUND if exactly one maximal binding is found
- RESOLUTION-AMBIGUOUS if multiple maximal bindings are found"
  (declare (type binding-table table)
           (type symbol name)
           (type scope:scope-set scopes)
           (values resolution-result))
  (let* ((candidates (find-candidates table name scopes))
         (maximal (find-maximal candidates)))
    (cond
      ((null maximal)
       (make-resolution-unbound name scopes))
      ((null (cdr maximal))
       (make-resolution-bound (car maximal)))
      (t
       (make-resolution-ambiguous name scopes maximal)))))

(defun binding-table-resolve-syntax (table stx)
  "Resolve a syntax object STX in TABLE.

STX must be an identifier (symbol datum). Returns a resolution result."
  (declare (type binding-table table)
           (type stx:syntax-object stx)
           (values resolution-result))
  (let ((datum (stx:syntax-e stx)))
    (unless (symbolp datum)
      (error "Cannot resolve non-identifier syntax: ~S" datum))
    (binding-table-resolve table datum (stx:syntax-object-scopes stx))))
