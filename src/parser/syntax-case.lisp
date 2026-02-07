;;;; Syntax patterns and templates for hygienic macro expansion
;;;;
;;;; This implements Racket-style syntax-case pattern matching and
;;;; quasisyntax templates for writing macros with hygiene support.
;;;;
;;;; Pattern Language:
;;;;   _              - Wildcard, matches any syntax
;;;;   symbol         - Pattern variable, binds matched syntax (unless in literals)
;;;;   (pat ...)      - List with ellipsis: pat matches zero or more times
;;;;   (p1 p2 ... pn) - List pattern: matches list of n elements
;;;;
;;;; Template Language:
;;;;   var            - Insert bound syntax
;;;;   (tmpl ...)     - Ellipsis: expand tmpl for each element in bound lists
;;;;   (a b ...)      - Literal a, then expand b...

(defpackage #:coalton-impl/parser/syntax-case
  (:use #:cl)
  (:local-nicknames
   (#:util #:coalton-impl/util)
   (#:scope #:coalton-impl/parser/scope)
   (#:stx #:coalton-impl/parser/syntax-object)
   (#:stx-cst #:coalton-impl/parser/syntax-cst))
  (:export
   ;; Pattern matching
   #:syntax-match                         ; FUNCTION
   #:pattern-variables                    ; FUNCTION

   ;; Syntax-case macro
   #:syntax-case                          ; MACRO
   #:with-syntax                          ; MACRO

   ;; Template construction
   #:syntax                               ; MACRO (quasisyntax)
   #:quasisyntax                          ; MACRO (alias)
   #:expand-template                      ; FUNCTION
   #:syntax->list                         ; FUNCTION

   ;; Ellipsis utilities
   #:ellipsis-p                           ; FUNCTION
   #:...                                  ; SYMBOL (exported for pattern use)
   ))

(in-package #:coalton-impl/parser/syntax-case)

;;;
;;; Ellipsis Detection
;;;

(defun ellipsis-p (x)
  "Return T if X is the ellipsis symbol."
  (and (symbolp x)
       (string= (symbol-name x) "...")))

;;;
;;; Pattern Variables
;;;

(defun pattern-variables (pattern &optional literals)
  "Return a list of pattern variable names in PATTERN.
LITERALS is a list of symbols that are treated as literals, not variables."
  (labels ((collect (pat depth)
             ;; depth tracks ellipsis nesting for future use
             (declare (ignore depth))
             (cond
               ;; Null (check before symbolp since NIL is a symbol)
               ((null pat) nil)
               ;; Wildcard (check by name since _ may be in different packages)
               ((and (symbolp pat) (string= (symbol-name pat) "_")) nil)
               ;; Ellipsis marker itself
               ((ellipsis-p pat) nil)
               ;; Literal symbol
               ((and (symbolp pat) (member pat literals)) nil)
               ;; Pattern variable
               ((symbolp pat) (list pat))
               ;; List pattern
               ((consp pat)
                (let ((rest (cdr pat)))
                  (if (and (consp rest) (ellipsis-p (car rest)))
                      ;; (pat ... rest...) - ellipsis pattern
                      (append (collect (car pat) (1+ 0))
                              (collect (cddr pat) 0))
                      ;; Regular list
                      (append (collect (car pat) 0)
                              (collect (cdr pat) 0)))))
               (t nil))))
    (remove-duplicates (collect pattern 0))))

;;;
;;; Pattern Matching Engine
;;;

(defvar *syntax-match-bindings* nil
  "Dynamic variable for collecting pattern bindings during syntax-match.")

(defun syntax-match (pattern stx &optional literals)
  "Match PATTERN against syntax object STX.
Returns (VALUES T BINDINGS) on success, (VALUES NIL NIL) on failure.
BINDINGS is an alist mapping pattern variable names to matched syntax.
LITERALS is a list of symbols that must match literally."
  (let ((*syntax-match-bindings* nil))
    (labels
        ((match-p (pat syn)
           (cond
             ;; Null pattern matches null syntax (check before symbolp since NIL is a symbol)
             ((null pat)
              (and (stx:syntax-object-p syn)
                   (null (stx:syntax-e syn))))

             ;; Wildcard matches anything (but doesn't bind)
             ((and (symbolp pat) (string= (symbol-name pat) "_")) t)

             ;; Ellipsis marker - should not appear at top level
             ((ellipsis-p pat)
              (error "Ellipsis ... cannot appear outside list pattern"))

             ;; Literal symbol - must match exactly
             ((and (symbolp pat) (member pat literals))
              (and (stx:syntax-object-p syn)
                   (eq pat (stx:syntax-e syn))))

             ;; Pattern variable - binds to syntax
             ((symbolp pat)
              (push (cons pat syn) *syntax-match-bindings*)
              t)

             ;; List pattern
             ((consp pat)
              (match-list pat syn))

             ;; Literal value (number, string, etc.)
             (t
              (and (stx:syntax-object-p syn)
                   (equal pat (stx:syntax-e syn))))))

         (match-list (pat syn)
           (unless (and (stx:syntax-object-p syn)
                        (listp (stx:syntax-e syn)))
             (return-from match-list nil))

           (let ((syn-list (stx:syntax-e syn)))
             ;; Check for ellipsis pattern at end
             (if (has-ellipsis-tail-p pat)
                 (match-ellipsis pat syn-list)
                 (match-simple-list pat syn-list))))

         (has-ellipsis-tail-p (pat)
           "Check if pattern ends with (... something ...)"
           (and (consp pat)
                (consp (cdr pat))
                (ellipsis-p (cadr pat))))

         (match-simple-list (pat syn-list)
           "Match non-ellipsis list pattern"
           (cond
             ;; Both empty
             ((and (null pat) (null syn-list)) t)
             ;; Pattern exhausted but syntax remains
             ((null pat) nil)
             ;; Syntax exhausted but pattern remains
             ((null syn-list) nil)
             ;; Check if we've reached an ellipsis pattern
             ((has-ellipsis-tail-p pat)
              (match-ellipsis pat syn-list))
             ;; Match head and recurse
             (t (and (match-p (car pat) (car syn-list))
                     (match-simple-list (cdr pat) (cdr syn-list))))))

         (match-ellipsis (pat syn-list)
           "Match pattern with ellipsis: (head-pat ... rest-pat...)"
           (let* ((ellipsis-pat (car pat))
                  (after-ellipsis (cddr pat))  ; patterns after ...
                  (ellipsis-vars (pattern-variables ellipsis-pat literals))
                  ;; Initialize collectors for ellipsis variables
                  (collectors (mapcar (lambda (v) (cons v nil)) ellipsis-vars))
                  ;; Calculate how many elements we need for after-ellipsis
                  (min-after (length after-ellipsis)))

             ;; Try to match as many as possible to ellipsis, leaving min-after for rest
             (when (< (length syn-list) min-after)
               (return-from match-ellipsis nil))

             (let* ((ellipsis-count (- (length syn-list) min-after))
                    (ellipsis-elements (subseq syn-list 0 ellipsis-count))
                    (after-elements (subseq syn-list ellipsis-count)))

               ;; Match each ellipsis element
               (dolist (elem ellipsis-elements)
                 ;; Temporarily use fresh bindings for this element
                 (let ((*syntax-match-bindings* nil))
                   (unless (match-p ellipsis-pat elem)
                     (return-from match-ellipsis nil))
                   ;; Collect bindings for ellipsis vars
                   (dolist (var ellipsis-vars)
                     (let ((binding (assoc var *syntax-match-bindings*)))
                       (when binding
                         (push (cdr binding) (cdr (assoc var collectors))))))))

               ;; Reverse the collected lists and add to main bindings
               (dolist (coll collectors)
                 (push (cons (car coll) (nreverse (cdr coll))) *syntax-match-bindings*))

               ;; Match the rest pattern
               (match-simple-list after-ellipsis after-elements)))))

      (if (match-p pattern stx)
          (values t (nreverse *syntax-match-bindings*))
          (values nil nil)))))

;;;
;;; Template Expansion
;;;

(defun expand-template (template bindings context-stx)
  "Expand TEMPLATE using BINDINGS, using CONTEXT-STX for scope context.
Returns a syntax object."
  (labels
      ((lookup (var)
         (let ((binding (assoc var bindings)))
           (if binding
               (cdr binding)
               (error "Unbound pattern variable in template: ~S" var))))

       (expand (tmpl)
         (cond
           ;; Syntax object - return as-is (preserves hygiene)
           ((stx:syntax-object-p tmpl) tmpl)

           ;; Pattern variable reference
           ((and (symbolp tmpl) (assoc tmpl bindings))
            (lookup tmpl))

           ;; Other symbol - wrap with context's scopes
           ((symbolp tmpl)
            (stx:datum->syntax context-stx tmpl))

           ;; List with potential ellipsis
           ((consp tmpl)
            (expand-list tmpl))

           ;; Literal value
           (t (stx:datum->syntax context-stx tmpl))))

       (expand-list (tmpl)
         (if (null tmpl)
             (stx:make-syntax-object nil
                                     :scopes (stx:syntax-object-scopes context-stx)
                                     :source (stx:syntax-object-source context-stx))
             (let ((expanded-elements (expand-list-elements tmpl)))
               (stx:make-list-syntax expanded-elements
                                     :scopes (stx:syntax-object-scopes context-stx)
                                     :source (stx:syntax-object-source context-stx)))))

       (expand-list-elements (tmpl)
         "Expand list elements, handling ellipsis"
         (cond
           ((null tmpl) nil)
           ;; Check for ellipsis following current element
           ((and (consp (cdr tmpl)) (ellipsis-p (cadr tmpl)))
            (let* ((ellipsis-tmpl (car tmpl))
                   (rest-tmpl (cddr tmpl))
                   (expanded-ellipsis (expand-ellipsis ellipsis-tmpl)))
              (append expanded-ellipsis (expand-list-elements rest-tmpl))))
           ;; Regular element
           (t (cons (expand (car tmpl))
                    (expand-list-elements (cdr tmpl))))))

       (expand-ellipsis (tmpl)
         "Expand an ellipsis template, returning a list of syntax objects"
         (let ((vars (template-variables tmpl)))
           (unless vars
             (error "Ellipsis template must contain pattern variables: ~S" tmpl))
           ;; Get the lists for each variable
           (let* ((first-var (car vars))
                  (first-list (lookup first-var))
                  (count (if (listp first-list) (length first-list) 0)))
             ;; Verify all ellipsis variables have same length
             (dolist (var (cdr vars))
               (let ((var-list (lookup var)))
                 (unless (and (listp var-list) (= (length var-list) count))
                   (error "Ellipsis variables must have same length: ~S vs ~S"
                          first-var var))))
             ;; Expand template for each index
             (loop for i from 0 below count
                   collect (expand-with-index tmpl vars i)))))

       (expand-with-index (tmpl vars index)
         "Expand template with ellipsis variables bound to their i-th elements"
         (let ((index-bindings
                 (mapcar (lambda (var)
                           (let ((list (lookup var)))
                             (cons var (nth index list))))
                         vars)))
           ;; Create new bindings with indexed values
           (let ((new-bindings (append index-bindings
                                       (remove-if (lambda (b) (member (car b) vars))
                                                  bindings))))
             (expand-template tmpl new-bindings context-stx))))

       (template-variables (tmpl)
         "Find pattern variables in template (those bound to lists for ellipsis)"
         (cond
           ((and (symbolp tmpl) (assoc tmpl bindings))
            (let ((val (lookup tmpl)))
              (if (listp val) (list tmpl) nil)))
           ((consp tmpl)
            (remove-duplicates
             (append (template-variables (car tmpl))
                     (unless (and (cdr tmpl) (ellipsis-p (cadr tmpl)))
                       (template-variables (cdr tmpl))))))
           (t nil))))

    (expand template)))

;;;
;;; syntax-case Macro
;;;

(defmacro syntax-case (stx-expr literals &body clauses)
  "Match STX-EXPR against patterns and execute the corresponding body.

LITERALS is a list of symbols that must match literally in patterns.
Each clause is (pattern body...) or (pattern fender body...).

Example:
  (syntax-case stx ()
    ((my-let ((var val) ...) body ...)
     (expand-let #'var #'val #'body)))"
  (let ((stx-var (gensym "STX"))
        (match-result (gensym "MATCH"))
        (bindings-var (gensym "BINDINGS")))
    `(let* ((,stx-var ,stx-expr)
            (%syntax-case-context% ,stx-var))
       (declare (ignorable %syntax-case-context%))
       (cond
         ,@(mapcar
            (lambda (clause)
              (let ((pattern (car clause))
                    (body (cdr clause)))
                `((multiple-value-bind (,match-result ,bindings-var)
                      (syntax-match ',pattern ,stx-var ',literals)
                    (when ,match-result
                      ;; Bind pattern variables
                      (let ,(mapcar (lambda (var)
                                      `(,var (cdr (assoc ',var ,bindings-var))))
                                    (pattern-variables pattern literals))
                        (declare (ignorable ,@(pattern-variables pattern literals)))
                        ,@body))))))
            clauses)
         (t (error "syntax-case: no matching clause for ~S" ,stx-var))))))

;;;
;;; with-syntax Macro
;;;

(defmacro with-syntax (bindings &body body)
  "Bind pattern variables for use in syntax templates.

Each binding is (pattern stx-expr).

Example:
  (with-syntax (((var ...) vars-stx)
                ((val ...) vals-stx))
    #'(let ((var val) ...) body))"
  (if (null bindings)
      `(progn ,@body)
      (let* ((binding (car bindings))
             (pattern (car binding))
             (stx-expr (cadr binding))
             (vars (pattern-variables pattern nil))
             (stx-var (gensym "STX"))
             (match-var (gensym "MATCH"))
             (bindings-var (gensym "BINDINGS")))
        `(let* ((,stx-var ,stx-expr)
                (%syntax-case-context% ,stx-var))
           (declare (ignorable %syntax-case-context%))
           (multiple-value-bind (,match-var ,bindings-var)
               (syntax-match ',pattern ,stx-var nil)
             (unless ,match-var
               (error "with-syntax: pattern ~S did not match ~S" ',pattern ,stx-var))
             (let ,(mapcar (lambda (var)
                             `(,var (cdr (assoc ',var ,bindings-var))))
                           vars)
               (with-syntax ,(cdr bindings)
                 ,@body)))))))

;;;
;;; syntax Template Macro
;;;

(defmacro syntax (template)
  "Construct a syntax object from TEMPLATE using pattern variables in scope.

Pattern variables in scope are substituted. Ellipsis expands repetitions.
This is the quasisyntax form for building hygienic macro output.

Requires a lexically visible %SYNTAX-CASE-CONTEXT% variable, which is
automatically bound by SYNTAX-CASE and WITH-SYNTAX.

Example:
  (syntax-case stx ()
    ((my-let ((var val) ...) body)
     (syntax (let ((var val) ...) body))))"
  (let ((pvars (pattern-variables template nil)))
    `(expand-template ',template
                      (list ,@(mapcar (lambda (v) `(cons ',v ,v)) pvars))
                      %syntax-case-context%)))

(defmacro quasisyntax (template)
  "Alias for syntax."
  `(syntax ,template))

;;;
;;; Helper for converting syntax to list
;;;

(defun syntax->list (stx)
  "Convert a syntax object containing a list to a regular list of syntax objects.
Returns NIL if STX is not a list syntax."
  (when (stx:syntax-object-p stx)
    (let ((datum (stx:syntax-e stx)))
      (when (listp datum)
        datum))))

;;;
;;; Bridge: export syntax API from the COALTON package
;;;
;;; The COALTON package is defined before syntax-case.lisp loads, so we
;;; cannot use :import-from at defpackage time. Instead we import and
;;; re-export at load time.
;;;

(eval-when (:compile-toplevel :load-toplevel :execute)
  (let ((coalton-pkg (find-package "COALTON")))
    (when coalton-pkg
      (import '(syntax-case with-syntax syntax quasisyntax) coalton-pkg)
      (export '(syntax-case with-syntax syntax quasisyntax) coalton-pkg))))
