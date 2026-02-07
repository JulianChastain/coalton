(defpackage #:coalton-impl/parser/base
  (:use
   #:cl)
  (:shadow
   #:parse-error)
  (:local-nicknames
   (#:source #:coalton-impl/source)
   (#:util #:coalton-impl/util)
   (#:stx #:coalton-impl/parser/syntax-object)
   (#:stx-cst #:coalton-impl/parser/syntax-cst))
  (:export
   #:identifier                         ; TYPE
   #:identifierp                        ; FUNCTION
   #:identifier-list                    ; TYPE
   #:keyword-src                        ; STRUCT
   #:make-keyword-src                   ; CONSTRUCTOR
   #:keyword-src-name                   ; ACCESSOR
   #:keyword-src-list                   ; TYPE
   #:identifier-src                     ; STRUCT
   #:make-identifier-src                ; CONSTRUCTOR
   #:identifier-src-name                ; ACCESSOR
   #:identifier-src-source-name         ; ACCESSOR
   #:identifier-src-list                ; TYPE
   #:parse-list                         ; FUNCTION
   #:parse-error
   #:note
   #:secondary-note
   #:note-end
   #:help
   #:form-location))

(in-package #:coalton-impl/parser/base)

;;;
;;; Shared definitions for source parser
;;;

(deftype identifier ()
  '(and symbol (not boolean) (not keyword)))

(defun identifierp (x)
  (typep x 'identifier))

(defun identifier-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'identifierp x)))

(deftype identifier-list ()
  '(satisfies identifier-list-p))

(defstruct (keyword-src
            (:copier nil))
  (name     (util:required 'name)     :type keyword :read-only t)
  (location (util:required 'location) :type source:location :read-only t))

(defmethod source:location ((self keyword-src))
  (keyword-src-location self))

(defun keyword-src-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'keyword-src-p x)))

(deftype keyword-src-list ()
  '(satisfies keyword-src-list-p))

(defstruct (identifier-src
            (:copier nil))
  (name     (util:required 'name)     :type identifier :read-only t)
  (source-name nil                    :type (or null string) :read-only t)
  (location (util:required 'location) :type source:location :read-only t))

(defmethod source:location ((self identifier-src))
  (identifier-src-location self))

(defun identifier-src-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'identifier-src-p x)))

(deftype identifier-src-list ()
  '(satisfies identifier-src-list-p))

(defun parse-list (f list_ file)
  (declare (type function f)
           (type stx:syntax-object list_)
           (values list))

  (loop :for list := list_ :then (stx-cst:stx-rest list)
        :while (stx-cst:stx-consp list)
        :collect (funcall f (stx-cst:stx-first list) file)))

;;; Condition types and helper functions specific to errors
;;; encountered during parsing.
;;;
;;; A complex parse error may be signaled with:
;;;
;;;   (parse-error "Overall description of condition"
;;;                (note SOURCE CST1 "Primary ~A: ~A" ARG1 ARG2)
;;;                (note SOURCE CST2 "Related: ~A" ARG3)
;;;                ... )

(define-condition parse-error (source:source-error)
  ()
  (:documentation "A condition indicating a syntax error in Coalton source code."))

(defun parse-error (message &rest notes)
  "Signal PARSE-ERROR with provided MESSAGE and source NOTES."
  (error 'parse-error :message message :notes notes))

(defun ensure-span (spanning)
  "If SPANNING is a span, return it unchanged; if it is a syntax object, return its source span."
  (etypecase spanning
    (stx:syntax-object (stx-cst:stx-source spanning))
    (source:span spanning)))

(defun note (source locatable format-string &rest format-args)
  "Make a source note using SOURCE and CST:SOURCE as location."
  (declare (type string format-string))
  (apply #'source:note (source:make-location source (ensure-span locatable))
         format-string format-args))

(defun secondary-note (source locatable format-string &rest format-args)
  "Make a source note using SOURCE and CST:SOURCE as location."
  (declare (type string format-string))
  (apply #'source:secondary-note (source:make-location source (ensure-span locatable))
         format-string format-args))

(defun note-end (source locatable format-string &rest format-args)
  "Make a source note using SOURCE and the location immediately following CST:SOURCE as location."
  (apply #'source:note
         (source:end-location (source:make-location source
                                                    (ensure-span locatable)))
         format-string format-args))

(defun help (source locatable replace format-string &rest format-args)
  "Make a help note using SOURCE and CST:SOURCE as location."
  (declare (type string format-string))
  (apply #'source:help (source:make-location source (ensure-span locatable))
         replace format-string format-args))

(defun form-location (source form)
  "Make a source location from a SOURCE and a syntax object."
  (declare (type stx:syntax-object form))
  (source:make-location source (stx-cst:stx-source form)))
