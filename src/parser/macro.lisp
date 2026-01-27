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
   #:*use-hygienic-macros*))

(in-package #:coalton-impl/parser/macro)

(defun expand-macro (form source)
  "Expand the macro in FORM using MACROEXPAND-1, trying our best to preserve source information."
  (declare (type cst:cst form)
           (values cst:cst &optional))
  (let (;; Fallback to the macro source if unable to find something more specific.
        (fallback-source (cst:source form))
        ;; Table mapping forms within FORM to their sources. We will
        ;; check pointer equality of forms in the output of the macro
        ;; to these to retrieve source information.
        (source-table (make-hash-table :test #'eq)))
    (fill-source-table form source-table (make-hash-table :test #'eq))
    (handler-case
        (rebuild-cst (macroexpand-1 (cst:raw form))
                     source-table
                     fallback-source
                     (make-hash-table :test #'eq))
      (error (condition)
        (parse-error "Error during macro expansion"
                     (note source form (princ-to-string condition)))))))

(defun fill-source-table (cst source-table seen-forms)
  "Fill SOURCE-TABLE with source information in CST and its children."
  (declare (type cst:cst cst)
           (type hash-table source-table))
  (cond
    ;; If we have already seen this form then skip it.
    ((gethash cst seen-forms)
     nil)
    (t
     ;; When forms appear multiple times the later ones don't have any
     ;; source information. We can safely ignore these.
     (unless (or (cst:null cst)
                 (nth-value 1 (gethash (cst:raw cst) source-table)))
       (setf (gethash (cst:raw cst) source-table) (cst:source cst)))
     (when (cst:consp cst)
       (loop :for tail := cst :then (cst:rest tail)
             :while (cst:consp tail)
             :do (fill-source-table (cst:first tail) source-table seen-forms)
             :finally
                ;; Only walk the last form if it is not null. This is
                ;; only the case in dotted lists.
                (unless (cst:null tail)
                  (fill-source-table tail source-table seen-forms)))))))

(defun rebuild-cst (form source-table fallback-source seen-forms)
  "Rebuild a CST from the FORM.

SOURCE-TABLE contains a pointer mapping from macro input forms to source information.
FALLBACK-SOURCE is the source information of the macro to use as a fallback.
SEEN-FORMS is a hash table of known forms to prevent hang on cyclical list forms."
  (declare (type (or atom list) form)
           (type hash-table source-table seen-forms)
           (type cons fallback-source)
           (values cst:cst &optional))
  (let ((source (gethash form source-table fallback-source)))
    (cond ((nth-value 1 (gethash form seen-forms))
           (gethash form seen-forms))
          ((atom form)
           (make-instance
            'cst:atom-cst
            :raw form
            :source source))
          (t
           (let ((result (make-instance
                          'cst:cons-cst
                          :raw form
                          :source source)))
             (setf (gethash form seen-forms) result)
             (reinitialize-instance
              result
              :first (rebuild-cst (car form) source-table fallback-source seen-forms)
              :rest (rebuild-cst (cdr form) source-table fallback-source seen-forms)))))))

;;;
;;; Hygienic Macro Expansion
;;;
;;; This implements the "sets of scopes" hygiene algorithm from Flatt (POPL 2016).
;;; The key insight is that hygiene can be achieved by tracking scope sets on
;;; syntax objects and using the "flip" operation during expansion.
;;;

(defvar *use-hygienic-macros* nil
  "When T, use hygienic macro expansion. When NIL, use traditional expansion.
This is a feature flag for gradual rollout.")

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
           (values function))
  (lambda (stx)
    (let* ((datum (stx:syntax->datum stx))
           (expanded (macroexpand-1 datum)))
      (stx:datum->syntax stx expanded))))

(defun expand-macro-hygienic-wrapper (form source)
  "Expand FORM hygienically, converting between CST and syntax objects.

FORM is a CST representing the macro invocation.
SOURCE is the source information context.

This is the main entry point for hygienic macro expansion in the parser.
It:
1. Converts the CST to a syntax object
2. Creates a transformer that calls CL's macroexpand-1
3. Expands hygienically using the flip algorithm
4. Converts the result back to a CST for the parser"
  (declare (type cst:cst form)
           (values cst:cst))
  (let* ((stx (stx-cst:cst->syntax form))
         (transformer (make-cl-macro-transformer (cst:raw form)))
         (expanded-stx (expand-macro-hygienic stx transformer))
         (fallback-source (cst:source form)))
    (syntax->cst expanded-stx fallback-source)))
