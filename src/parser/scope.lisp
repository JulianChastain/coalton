;;;; Scope tokens and scope sets for hygienic macro expansion
;;;;
;;;; This implements the "sets of scopes" model from Flatt (POPL 2016).
;;;; Each scope is represented by a unique integer token, and identifiers
;;;; carry sets of these tokens to track their lexical context.

(defpackage #:coalton-impl/parser/scope
  (:use #:cl)
  (:local-nicknames
   (#:util #:coalton-impl/util))
  (:export
   ;; Scope tokens
   #:scope-token                          ; TYPE
   #:make-scope-token                     ; FUNCTION
   #:scope-token-id                       ; ACCESSOR

   ;; Scope sets
   #:scope-set                            ; TYPE
   #:empty-scope-set                      ; FUNCTION
   #:scope-set-add                        ; FUNCTION
   #:scope-set-remove                     ; FUNCTION
   #:scope-set-flip                       ; FUNCTION
   #:scope-set-subset-p                   ; FUNCTION
   #:scope-set-empty-p                    ; FUNCTION
   #:scope-set-size                       ; FUNCTION
   #:scope-set-equal                      ; FUNCTION
   #:scope-set-union                      ; FUNCTION
   #:scope-set-intersection               ; FUNCTION
   #:scope-set-member-p                   ; FUNCTION
   #:scope-set->list                      ; FUNCTION
   ))

(in-package #:coalton-impl/parser/scope)

;;;
;;; Scope Tokens
;;;
;;; A scope token is a unique identifier for a lexical scope.
;;; New tokens are created at binding sites (let, fn, define) and
;;; during macro expansion (use-site and intro scopes).
;;;

(defvar *next-scope-id* 0
  "Counter for generating unique scope IDs.")

(defstruct (scope-token
            (:copier nil)
            (:constructor %make-scope-token (id)))
  "A unique identifier for a lexical scope."
  (id (util:required 'id) :type (integer 0) :read-only t))

(defmethod make-load-form ((self scope-token) &optional env)
  (declare (ignore env))
  `(%make-scope-token ,(scope-token-id self)))

(defun make-scope-token ()
  "Create a fresh scope token with a unique ID."
  (declare (values scope-token))
  (%make-scope-token (prog1 *next-scope-id*
                       (incf *next-scope-id*))))

(defmethod print-object ((obj scope-token) stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "~D" (scope-token-id obj))))

;;;
;;; Scope Sets
;;;
;;; A scope set is an immutable set of scope tokens, implemented using FSet.
;;; The key operations are:
;;;   - add: Include a scope in the set
;;;   - remove: Exclude a scope from the set
;;;   - flip: Symmetric difference (add if absent, remove if present)
;;;
;;; The flip operation is crucial for hygiene: it ensures that syntax
;;; introduced by a macro gets a fresh scope, while syntax passed through
;;; from the macro input returns to its original scope set.
;;;

(defstruct (scope-set
            (:copier nil)
            (:constructor %make-scope-set (data)))
  "An immutable set of scope tokens."
  (data (fset:empty-set) :type fset:set :read-only t))

(defmethod make-load-form ((self scope-set) &optional env)
  (declare (ignore env))
  `(%make-scope-set (fset:convert 'fset:set ',(fset:convert 'list (scope-set-data self)))))

(defun empty-scope-set ()
  "Return an empty scope set."
  (declare (values scope-set))
  (%make-scope-set (fset:empty-set)))

(defmethod print-object ((obj scope-set) stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "~{~A~^ ~}"
            (mapcar #'scope-token-id
                    (fset:convert 'list (scope-set-data obj))))))

(defun scope-set-add (set token)
  "Return a new scope set with TOKEN added."
  (declare (type scope-set set)
           (type scope-token token)
           (values scope-set))
  (%make-scope-set (fset:with (scope-set-data set) token)))

(defun scope-set-remove (set token)
  "Return a new scope set with TOKEN removed."
  (declare (type scope-set set)
           (type scope-token token)
           (values scope-set))
  (%make-scope-set (fset:less (scope-set-data set) token)))

(defun scope-set-flip (set token)
  "Return a new scope set with TOKEN flipped (added if absent, removed if present).

This is the symmetric difference operation, crucial for hygiene:
- When applied to macro output, syntax from the input (which had the scope added
  earlier) will have it removed, returning to its original state.
- Syntax introduced by the macro (which didn't have the scope) will have it added,
  distinguishing it from user code."
  (declare (type scope-set set)
           (type scope-token token)
           (values scope-set))
  (let ((data (scope-set-data set)))
    (if (fset:contains? data token)
        (%make-scope-set (fset:less data token))
        (%make-scope-set (fset:with data token)))))

(defun scope-set-subset-p (set1 set2)
  "Return T if SET1 is a subset of SET2.

This is used in binding resolution: a binding's scopes must be a subset
of the reference's scopes for the binding to be visible."
  (declare (type scope-set set1 set2)
           (values boolean))
  (fset:subset? (scope-set-data set1) (scope-set-data set2)))

(defun scope-set-empty-p (set)
  "Return T if SET is empty."
  (declare (type scope-set set)
           (values boolean))
  (fset:empty? (scope-set-data set)))

(defun scope-set-size (set)
  "Return the number of scopes in SET."
  (declare (type scope-set set)
           (values (integer 0)))
  (fset:size (scope-set-data set)))

(defun scope-set-equal (set1 set2)
  "Return T if SET1 and SET2 contain the same scopes."
  (declare (type scope-set set1 set2)
           (values boolean))
  (fset:equal? (scope-set-data set1) (scope-set-data set2)))

(defun scope-set-union (set1 set2)
  "Return the union of SET1 and SET2."
  (declare (type scope-set set1 set2)
           (values scope-set))
  (%make-scope-set (fset:union (scope-set-data set1) (scope-set-data set2))))

(defun scope-set-intersection (set1 set2)
  "Return the intersection of SET1 and SET2."
  (declare (type scope-set set1 set2)
           (values scope-set))
  (%make-scope-set (fset:intersection (scope-set-data set1) (scope-set-data set2))))

(defun scope-set-member-p (set token)
  "Return T if TOKEN is a member of SET."
  (declare (type scope-set set)
           (type scope-token token)
           (values boolean))
  (if (fset:contains? (scope-set-data set) token) t nil))

(defun scope-set->list (set)
  "Return the scopes in SET as a list."
  (declare (type scope-set set)
           (values list))
  (fset:convert 'list (scope-set-data set)))
