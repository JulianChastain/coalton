;;;; Shrubbery/Rhombus syntax frontend for Coalton
;;;;
;;;; Translates trapezoid's shrubbery notation into Coalton S-expression
;;;; forms wrapped in syntax objects, then feeds them into the existing
;;;; parser pipeline (parse-toplevel-form / parse-expression).
;;;;
;;;; Architecture:
;;;;   shrubbery text
;;;;     → trapezoid:parse-shrubbery  (produces shrubbery S-exprs)
;;;;     → coalton-enforest            (produces Coalton S-expression lists)
;;;;     → sexp->syntax               (wraps in Coalton syntax-objects)
;;;;     → parse-toplevel-form         (existing Coalton parser)

(defpackage #:coalton-impl/parser/shrubbery
  (:use #:cl)
  (:local-nicknames
   (#:stx #:coalton-impl/parser/syntax-object)
   (#:stx-cst #:coalton-impl/parser/syntax-cst)
   (#:scope #:coalton-impl/parser/scope)
   (#:source #:coalton-impl/source)
   (#:util #:coalton-impl/util)
   (#:parser #:coalton-impl/parser/toplevel)
   (#:trap #:trapezoid))
  (:export
   #:parse-shrubbery-toplevel            ; FUNCTION
   #:parse-shrubbery-expression          ; FUNCTION
   #:coalton-enforest                    ; FUNCTION
   #:shrubbery->coalton-sexps            ; FUNCTION
   ))

(in-package #:coalton-impl/parser/shrubbery)

;;; ============================================================
;;; Source Location Mapping
;;; ============================================================
;;;
;;; Trapezoid uses (line, column); Coalton uses byte-offset pairs (start . end).
;;; We build a line-offset table from the source text to convert.

(defun build-line-offsets (text)
  "Build a vector mapping 1-based line numbers to byte offsets.
Element 0 is unused; element N is the byte offset of the start of line N."
  (let ((offsets (make-array 16 :adjustable t :fill-pointer 0 :element-type 'fixnum)))
    ;; Index 0 placeholder
    (vector-push-extend 0 offsets)
    ;; Line 1 starts at offset 0
    (vector-push-extend 0 offsets)
    (loop :for i :from 0 :below (length text)
          :when (char= (char text i) #\Newline)
            :do (vector-push-extend (1+ i) offsets))
    offsets))

(defun line-col->offset (line-offsets line col)
  "Convert 1-based LINE and COL to a 0-based byte offset.
Returns 0 if line/col are nil."
  (if (and line col (> line 0) (<= line (1- (length line-offsets))))
      (+ (aref line-offsets line) (max 0 (1- col)))
      0))

(defun trap-source-span (line-offsets trap-form text-length)
  "Extract a source span (start . end) from a trapezoid form.
If the form is a trapezoid syntax object, use its line/column.
Otherwise return a default span."
  (if (trap:syntax-p trap-form)
      (let ((start (line-col->offset line-offsets
                                     (trap:syntax-line trap-form)
                                     (trap:syntax-column trap-form)))
            (end (line-col->offset line-offsets
                                   (or (trap:syntax-end-line trap-form)
                                       (trap:syntax-line trap-form))
                                   (or (trap:syntax-end-column trap-form)
                                       (trap:syntax-column trap-form)))))
        (cons start (max (1+ start) end)))
      (cons 0 text-length)))

;;; ============================================================
;;; S-expression → Coalton Syntax Object Conversion
;;; ============================================================

(defun sexp->syntax (sexp &optional (source-span nil))
  "Convert a Lisp S-expression SEXP into a Coalton syntax-object tree.
SOURCE-SPAN is a (start . end) cons for source locations."
  (cond
    ((consp sexp)
     (stx:make-syntax-object
      (mapcar (lambda (e) (sexp->syntax e source-span)) sexp)
      :source source-span))
    (t
     (stx:make-syntax-object sexp :source source-span))))

;;; ============================================================
;;; Trapezoid Shrubbery → Coalton S-expression Translation
;;; ============================================================
;;;
;;; This is the Coalton-specific enforester. It takes the plain
;;; S-expression output from trapezoid (with *produce-syntax-objects* nil)
;;; and translates it into Coalton S-expression lists.
;;;
;;; Trapezoid enforester produces forms like:
;;;   (call + a b)     → we want (+ a b)
;;;   (define name val) → we want (coalton:define name val)
;;;   (lambda (x) body) → we want (coalton:fn (x) body)
;;;   (if c t e)        → we want (coalton:if c t e)
;;;   (match v ...)     → we want (coalton:match v ...)
;;;
;;; We first run trapezoid's enforester on the shrubbery parse output,
;;; then post-process the result into Coalton forms.

(defun translate-enforested (form)
  "Translate an enforested trapezoid form into a Coalton S-expression.
FORM is the output of trapezoid:enforest (plain S-expressions)."
  (cond
    ;; NIL
    ((null form) nil)

    ;; Atoms pass through
    ((atom form) form)

    ;; (call op args...) → (op args...)
    ;; Trapezoid wraps all function calls and binary ops as (call ...)
    ((eq (car form) 'trap:call)
     (let ((op (translate-enforested (second form)))
           (args (mapcar #'translate-enforested (cddr form))))
       (cons op args)))

    ;; (define name value) → (coalton:define name value)
    ;; For function defs: (define name (lambda (args) body))
    ;;   → (coalton:define (name args...) body)
    ((eq (car form) 'trap:define)
     (let ((name (second form))
           (value (translate-enforested (third form))))
       (if (and (consp value) (eq (car value) 'coalton:fn))
           ;; Function definition: unwrap lambda into define
           `(coalton:define (,name ,@(second value)) ,@(cddr value))
           ;; Simple value definition
           `(coalton:define ,name ,value))))

    ;; (lambda (args) body) → (coalton:fn (args) body)
    ((eq (car form) 'lambda)
     (let ((args (second form))
           (body (translate-enforested-body (cddr form))))
       `(coalton:fn (,@args) ,body)))

    ;; (if cond then else) → (coalton:if cond then else)
    ((eq (car form) 'if)
     `(coalton:if ,(translate-enforested (second form))
                  ,(translate-enforested (third form))
                  ,@(when (fourth form)
                      (list (translate-enforested (fourth form))))))

    ;; (match val (pat body) ...) → (coalton:match val ((pat) body) ...)
    ((eq (car form) 'trap:match)
     `(coalton:match ,(translate-enforested (second form))
        ,@(mapcar #'translate-match-branch (cddr form))))

    ;; (progn forms...) → (coalton:progn forms...)
    ((eq (car form) 'progn)
     (let ((translated (mapcar #'translate-enforested (cdr form))))
       (if (= (length translated) 1)
           (first translated)
           `(coalton:progn ,@translated))))

    ;; (list ...) → (coalton:make-list ...)  or pass through
    ((eq (car form) 'list)
     (let ((elems (mapcar #'translate-enforested (cdr form))))
       `(coalton:make-list ,@elems)))

    ;; Unknown form — recurse on all elements
    (t
     (mapcar #'translate-enforested form))))

(defun translate-enforested-body (forms)
  "Translate a list of body forms. If single form, return it; otherwise wrap in progn."
  (let ((translated (mapcar #'translate-enforested forms)))
    (if (= (length translated) 1)
        (first translated)
        `(coalton:progn ,@translated))))

(defun translate-match-branch (branch)
  "Translate a match branch from trapezoid format to Coalton format.
Trapezoid: (pattern body)
Coalton: (pattern body)"
  (let ((pattern (translate-pattern (first branch)))
        (body (translate-enforested (second branch))))
    (list pattern body)))

(defun translate-pattern (pat)
  "Translate a pattern from trapezoid enforested form to Coalton format.
Coalton patterns are like: variable, literal, (Constructor args...)"
  (cond
    ((atom pat) pat)
    ;; (call Constructor args...) from enforester
    ((eq (car pat) 'trap:call)
     `(,(second pat) ,@(mapcar #'translate-pattern (cddr pat))))
    (t pat)))

;;; ============================================================
;;; Top-level Shrubbery-to-Coalton Translation
;;; ============================================================

(defun shrubbery->coalton-sexps (text)
  "Parse TEXT as shrubbery notation and return a list of Coalton S-expressions.
Uses trapezoid with plain S-expression output (no syntax objects)."
  (let ((trap:*produce-syntax-objects* nil))
    (let ((parsed (trap:parse-shrubbery text)))
      ;; parse-shrubbery returns a single group or a list of groups
      (let ((forms (if (and (consp parsed) (eq (car parsed) 'trap:group))
                       ;; Single top-level form
                       (list parsed)
                       ;; Multiple top-level forms (list of groups)
                       (if (consp parsed) parsed (list parsed)))))
        (mapcar (lambda (form)
                  (translate-enforested (trap:enforest form)))
                forms)))))

;;; ============================================================
;;; Entry Points
;;; ============================================================

(defun parse-shrubbery-toplevel (text source)
  "Parse TEXT as shrubbery notation, producing a Coalton parser:program.
SOURCE is a coalton source object for error reporting."
  (declare (type string text)
           (values parser:program &optional))
  (let* ((line-offsets (build-line-offsets text))
         (text-length (length text))
         (coalton-sexps (shrubbery->coalton-sexps text))
         (program (parser:make-program))
         (attributes (make-array 0 :adjustable t :fill-pointer t)))

    ;; Convert each Coalton S-expression into syntax objects and parse
    (dolist (sexp coalton-sexps)
      (let* ((span (cons 0 text-length))
             (stx-form (sexp->syntax sexp span)))
        (parser:parse-toplevel-form stx-form program attributes source)))

    ;; Reverse the accumulated lists (parse-toplevel-form pushes)
    (setf (parser:program-types program) (nreverse (parser:program-types program)))
    (setf (parser:program-type-aliases program) (nreverse (parser:program-type-aliases program)))
    (setf (parser:program-structs program) (nreverse (parser:program-structs program)))
    (setf (parser:program-declares program) (nreverse (parser:program-declares program)))
    (setf (parser:program-defines program) (nreverse (parser:program-defines program)))
    (setf (parser:program-classes program) (nreverse (parser:program-classes program)))
    (setf (parser:program-instances program) (nreverse (parser:program-instances program)))
    (setf (parser:program-lisp-forms program) (nreverse (parser:program-lisp-forms program)))
    (setf (parser:program-specializations program) (nreverse (parser:program-specializations program)))

    program))

(defun parse-shrubbery-expression (text source)
  "Parse TEXT as a single shrubbery expression, returning a Coalton parse node."
  (declare (type string text))
  (let* ((coalton-sexps (shrubbery->coalton-sexps text))
         (sexp (first coalton-sexps))
         (span (cons 0 (length text)))
         (stx-form (sexp->syntax sexp span)))
    (coalton-impl/parser/expression:parse-expression stx-form source)))
