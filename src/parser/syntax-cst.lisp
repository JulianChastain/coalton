;;;; Abstraction layer for working with syntax objects
;;;;
;;;; This provides a uniform interface for traversing and manipulating
;;;; syntax objects, analogous to CST operations but for syntax objects.
;;;; These functions handle the common patterns of working with syntax
;;;; that may contain nested lists.

(defpackage #:coalton-impl/parser/syntax-cst
  (:use #:cl)
  (:local-nicknames
   (#:cst #:concrete-syntax-tree)
   (#:source #:coalton-impl/source)
   (#:scope #:coalton-impl/parser/scope)
   (#:stx #:coalton-impl/parser/syntax-object))
  (:export
   ;; Predicates
   #:stx-null-p                           ; FUNCTION
   #:stx-consp                            ; FUNCTION
   #:stx-atom-p                           ; FUNCTION
   #:stx-identifier-p                     ; FUNCTION
   #:stx-list-p                           ; FUNCTION
   #:stx-symbol-p                         ; FUNCTION
   #:stx-keyword-p                        ; FUNCTION
   #:stx-literal-p                        ; FUNCTION

   ;; List operations
   #:stx-first                            ; FUNCTION
   #:stx-rest                             ; FUNCTION
   #:stx-second                           ; FUNCTION
   #:stx-third                            ; FUNCTION
   #:stx-nth                              ; FUNCTION
   #:stx-length                           ; FUNCTION
   #:stx-list                             ; FUNCTION
   #:stx-list*                            ; FUNCTION
   #:stx-append                           ; FUNCTION

   ;; Mapping and traversal
   #:stx-map                              ; FUNCTION
   #:stx-for-each                         ; FUNCTION
   #:stx-fold                             ; FUNCTION

   ;; Source information
   #:stx-source                           ; FUNCTION
   #:stx-scopes                           ; FUNCTION

   ;; Symbol operations
   #:stx-symbol                           ; FUNCTION
   #:stx-symbol-name                      ; FUNCTION
   #:stx-keyword                          ; FUNCTION

   ;; Additional list operations
   #:stx-nthrest                          ; FUNCTION
   #:stx-listify                          ; FUNCTION
   #:stx-proper-list-p                    ; FUNCTION
   #:stx-head-symbol                      ; FUNCTION
   #:stx-source-range                     ; FUNCTION

   ;; Conversion from CST
   #:cst->syntax                          ; FUNCTION
   #:cst->syntax-with-scopes              ; FUNCTION
   ))

(in-package #:coalton-impl/parser/syntax-cst)

;;;
;;; Predicates
;;;

(defun stx-null-p (stx)
  "Return T if STX represents an empty list."
  (declare (type stx:syntax-object stx)
           (values boolean))
  (null (stx:syntax-e stx)))

(defun stx-consp (stx)
  "Return T if STX is a syntax object wrapping a non-empty list."
  (declare (type stx:syntax-object stx)
           (values boolean))
  (let ((datum (stx:syntax-e stx)))
    (and (listp datum) (not (null datum)))))

(defun stx-atom-p (stx)
  "Return T if STX wraps an atomic value (not a cons)."
  (declare (type stx:syntax-object stx)
           (values boolean))
  (atom (stx:syntax-e stx)))

(defun stx-identifier-p (stx)
  "Return T if STX is an identifier (a symbol that is not a keyword or boolean)."
  (declare (type stx:syntax-object stx)
           (values boolean))
  (let ((datum (stx:syntax-e stx)))
    (and (symbolp datum)
         (not (keywordp datum))
         (not (member datum '(t nil))))))

(defun stx-symbol-p (stx)
  "Return T if STX wraps a symbol."
  (declare (type stx:syntax-object stx)
           (values boolean))
  (symbolp (stx:syntax-e stx)))

(defun stx-keyword-p (stx)
  "Return T if STX wraps a keyword."
  (declare (type stx:syntax-object stx)
           (values boolean))
  (keywordp (stx:syntax-e stx)))

(defun stx-literal-p (stx)
  "Return T if STX wraps a literal value (number, string, character)."
  (declare (type stx:syntax-object stx)
           (values boolean))
  (let ((datum (stx:syntax-e stx)))
    (or (numberp datum)
        (stringp datum)
        (characterp datum))))

(defun stx-list-p (stx)
  "Return T if STX wraps a proper list (possibly empty)."
  (declare (type stx:syntax-object stx)
           (values boolean))
  (listp (stx:syntax-e stx)))

;;;
;;; List Operations
;;;

(defun stx-first (stx)
  "Return the first element of a list syntax object."
  (declare (type stx:syntax-object stx)
           (values stx:syntax-object))
  (let ((datum (stx:syntax-e stx)))
    (unless (and (listp datum) datum)
      (error "STX-FIRST: not a non-empty list syntax: ~S" stx))
    (car datum)))

(defun stx-rest (stx)
  "Return the rest of a list syntax object as a new syntax object.

The resulting syntax object has the same scopes and source as STX."
  (declare (type stx:syntax-object stx)
           (values stx:syntax-object))
  (let ((datum (stx:syntax-e stx)))
    (unless (and (listp datum) datum)
      (error "STX-REST: not a non-empty list syntax: ~S" stx))
    (stx:make-syntax-object
     (cdr datum)
     :scopes (stx:syntax-object-scopes stx)
     :source (stx:syntax-object-source stx))))

(defun stx-second (stx)
  "Return the second element of a list syntax object."
  (declare (type stx:syntax-object stx)
           (values stx:syntax-object))
  (stx-first (stx-rest stx)))

(defun stx-third (stx)
  "Return the third element of a list syntax object."
  (declare (type stx:syntax-object stx)
           (values stx:syntax-object))
  (stx-first (stx-rest (stx-rest stx))))

(defun stx-nth (n stx)
  "Return the Nth element (0-indexed) of a list syntax object."
  (declare (type (integer 0) n)
           (type stx:syntax-object stx)
           (values stx:syntax-object))
  (let ((datum (stx:syntax-e stx)))
    (unless (listp datum)
      (error "STX-NTH: not a list syntax: ~S" stx))
    (let ((elem (nth n datum)))
      (unless elem
        (error "STX-NTH: index ~D out of bounds for ~S" n stx))
      elem)))

(defun stx-length (stx)
  "Return the length of a list syntax object."
  (declare (type stx:syntax-object stx)
           (values (integer 0)))
  (let ((datum (stx:syntax-e stx)))
    (unless (listp datum)
      (error "STX-LENGTH: not a list syntax: ~S" stx))
    (length datum)))

(defun stx-list (&rest elements)
  "Create a list syntax object from the given ELEMENTS.

All elements must be syntax objects. The resulting syntax object
has empty scopes and no source."
  (declare (values stx:syntax-object))
  (stx:make-syntax-object elements))

(defun stx-list* (&rest elements)
  "Create a list syntax object, with the last element as the tail.

Like CL's LIST*, but for syntax objects."
  (declare (values stx:syntax-object))
  (stx:make-syntax-object (apply #'list* elements)))

(defun stx-append (&rest lists)
  "Append list syntax objects together.

Each argument should be a syntax object wrapping a list.
Returns a new syntax object wrapping the concatenated list."
  (declare (values stx:syntax-object))
  (stx:make-syntax-object
   (apply #'append
          (mapcar (lambda (stx)
                    (let ((datum (stx:syntax-e stx)))
                      (unless (listp datum)
                        (error "STX-APPEND: not a list syntax: ~S" stx))
                      datum))
                  lists))))

(defun stx-nthrest (n stx)
  "Skip the first N elements of a list syntax object, returning the rest.

The resulting syntax object has the same scopes and source as STX."
  (declare (type (integer 0) n)
           (type stx:syntax-object stx)
           (values stx:syntax-object))
  (let ((datum (stx:syntax-e stx)))
    (unless (listp datum)
      (error "STX-NTHREST: not a list syntax: ~S" stx))
    (stx:make-syntax-object
     (nthcdr n datum)
     :scopes (stx:syntax-object-scopes stx)
     :source (stx:syntax-object-source stx))))

(defun stx-listify (stx)
  "Extract the CL list of child syntax objects from a list syntax object."
  (declare (type stx:syntax-object stx)
           (values list))
  (let ((datum (stx:syntax-e stx)))
    (unless (listp datum)
      (error "STX-LISTIFY: not a list syntax: ~S" stx))
    datum))

(defun stx-proper-list-p (stx)
  "Return T if STX wraps a proper list.
Dotted lists are rejected during CST->syntax conversion, so this
always returns T for list datums."
  (declare (type stx:syntax-object stx)
           (values boolean))
  (listp (stx:syntax-e stx)))

(defun stx-head-symbol (stx)
  "If STX is a non-empty list syntax whose first element is an atom, return that symbol.
Otherwise return NIL."
  (declare (type stx:syntax-object stx)
           (values (or null symbol)))
  (let ((datum (stx:syntax-e stx)))
    (when (and (listp datum) datum)
      (let ((head (car datum)))
        (when (stx:syntax-object-p head)
          (let ((head-datum (stx:syntax-e head)))
            (when (symbolp head-datum)
              head-datum)))))))

(defun stx-source-range (stx-list)
  "Return a span covering the range from the first to the last element in STX-LIST.
STX-LIST is a CL list of syntax objects."
  (declare (type list stx-list)
           (values cons))
  (cons
   (car (stx:syntax-object-source (first stx-list)))
   (cdr (stx:syntax-object-source (car (last stx-list))))))

;;;
;;; Mapping and Traversal
;;;

(defun stx-map (f stx)
  "Apply F to each element of list syntax STX, returning a new list syntax.

F receives each element as a syntax object and should return a syntax object.
The resulting list syntax has the same scopes and source as STX."
  (declare (type function f)
           (type stx:syntax-object stx)
           (values stx:syntax-object))
  (let ((datum (stx:syntax-e stx)))
    (unless (listp datum)
      (error "STX-MAP: not a list syntax: ~S" stx))
    (stx:make-syntax-object
     (mapcar f datum)
     :scopes (stx:syntax-object-scopes stx)
     :source (stx:syntax-object-source stx))))

(defun stx-for-each (f stx)
  "Apply F to each element of list syntax STX for side effects."
  (declare (type function f)
           (type stx:syntax-object stx)
           (values null))
  (let ((datum (stx:syntax-e stx)))
    (unless (listp datum)
      (error "STX-FOR-EACH: not a list syntax: ~S" stx))
    (mapc f datum)
    nil))

(defun stx-fold (f init stx)
  "Fold F over the elements of list syntax STX with initial value INIT.

F takes (accumulator element) and returns new accumulator."
  (declare (type function f)
           (type stx:syntax-object stx)
           (values t))
  (let ((datum (stx:syntax-e stx)))
    (unless (listp datum)
      (error "STX-FOLD: not a list syntax: ~S" stx))
    (reduce f datum :initial-value init)))

;;;
;;; Source Information
;;;

(defun stx-source (stx)
  "Return the source location span of STX, or NIL."
  (declare (type stx:syntax-object stx)
           (values (or null cons)))
  (stx:syntax-object-source stx))

(defun stx-scopes (stx)
  "Return the scope set of STX."
  (declare (type stx:syntax-object stx)
           (values scope:scope-set))
  (stx:syntax-object-scopes stx))

;;;
;;; Symbol Operations
;;;

(defun stx-symbol (stx)
  "Return the symbol wrapped by STX. Signals error if not a symbol."
  (declare (type stx:syntax-object stx)
           (values symbol))
  (let ((datum (stx:syntax-e stx)))
    (unless (symbolp datum)
      (error "STX-SYMBOL: not a symbol syntax: ~S" stx))
    datum))

(defun stx-symbol-name (stx)
  "Return the name of the symbol wrapped by STX."
  (declare (type stx:syntax-object stx)
           (values string))
  (symbol-name (stx-symbol stx)))

(defun stx-keyword (stx)
  "Return the keyword wrapped by STX. Signals error if not a keyword."
  (declare (type stx:syntax-object stx)
           (values keyword))
  (let ((datum (stx:syntax-e stx)))
    (unless (keywordp datum)
      (error "STX-KEYWORD: not a keyword syntax: ~S" stx))
    datum))

;;;
;;; Conversion from CST
;;;
;;; These functions convert concrete syntax tree nodes to syntax objects,
;;; preserving source location information.
;;;

(defun cst->syntax (cst &optional file-source)
  "Convert a CST node to a syntax object with empty scopes.

This recursively converts the entire CST tree, wrapping each node
in a syntax object and preserving source locations.
FILE-SOURCE, if provided, is the source:source object for error reporting."
  (declare (type cst:cst cst)
           (values stx:syntax-object))
  (cst->syntax-impl cst (scope:empty-scope-set) file-source))

(defun cst->syntax-with-scopes (cst scopes)
  "Convert a CST node to a syntax object with the given SCOPES.

This recursively converts the entire CST tree."
  (declare (type cst:cst cst)
           (type scope:scope-set scopes)
           (values stx:syntax-object))
  (cst->syntax-impl cst scopes nil))

(defun cst->syntax-impl (cst scopes file-source)
  "Internal: Convert a CST node to a syntax object."
  (declare (type cst:cst cst)
           (type scope:scope-set scopes)
           (values stx:syntax-object))
  (let ((source (cst:source cst)))
    (cond
      ((cst:atom cst)
       ;; Atomic value: wrap directly
       (stx:make-syntax-object (cst:raw cst)
                               :scopes scopes
                               :source source))
      ((cst:null cst)
       ;; Empty list
       (stx:make-syntax-object nil
                               :scopes scopes
                               :source source))
      (t
       ;; Cons: recursively convert children
       (stx:make-syntax-object
        (loop :for tail := cst :then (cst:rest tail)
              :while (cst:consp tail)
              :collect (cst->syntax-impl (cst:first tail) scopes file-source)
              :finally
                 (unless (cst:null tail)
                   ;; Dotted pair: signal a parse error.
                   ;; Syntax objects only support proper lists, so we
                   ;; detect dotted lists here and report them.
                   (if file-source
                       (source:error "Malformed list"
                                     (source:note
                                      (source:make-location file-source (cst:source cst))
                                      "unexpected dotted list"))
                       (cl:error "Unexpected dotted list in CST conversion"))))
        :scopes scopes
        :source source)))))
