(defpackage #:coalton-impl/parser/expression
  (:use
   #:cl
   #:coalton-impl/parser/base
   #:coalton-impl/parser/types
   #:coalton-impl/parser/pattern
   #:coalton-impl/parser/macro)
  (:shadowing-import-from
   #:coalton-impl/parser/base
   #:parse-error)
  (:local-nicknames
   (#:stx #:coalton-impl/parser/syntax-object)
   (#:stx-cst #:coalton-impl/parser/syntax-cst)
   (#:source #:coalton-impl/source)
   (#:util #:coalton-impl/util)
   (#:const #:coalton-impl/constants))
  (:export
   #:node                               ; STRUCT
   #:node-list                          ; TYPE
   #:node-variable                      ; STRUCT
   #:make-node-variable                 ; CONSTRUCTOR
   #:node-variable-name                 ; ACCESSOR
   #:node-variable-list                 ; TYPE
   #:node-accessor                      ; STRUCT
   #:make-node-accessor                 ; CONSTRUCTOR
   #:node-accessor-name                 ; ACCESSOR
   #:node-literal                       ; STRUCT
   #:make-node-literal                  ; CONSTRUCTOR
   #:node-literal-value                 ; ACCESSOR
   #:node-integer-literal               ; STRUCT
   #:make-node-integer-literal          ; CONSTRUCTOR
   #:node-integer-literal-value         ; ACCESSOR
   #:node-bind                          ; STRUCT
   #:make-node-bind                     ; CONSTRUCTOR
   #:node-bind-pattern                  ; ACCESSOR
   #:node-bind-expr                     ; ACCESSOR
   #:node-body-element                  ; TYPE
   #:node-body-element-list             ; TYPE
   #:node-body                          ; STRUCT
   #:make-node-body                     ; CONSTRUCTOR
   #:node-body-nodes                    ; ACCESSOR
   #:node-body-last-node                ; ACCESSOR
   #:node-abstraction                   ; STRUCT
   #:make-node-abstraction              ; CONSTRUCTOR
   #:node-abstraction-params            ; ACCESSOR
   #:node-abstraction-body              ; ACCESSOR
   #:node-abstraction-p                 ; FUNCTION
   #:node-let-binding                   ; STRUCT
   #:make-node-let-binding              ; CONSTRUCTOR
   #:node-let-binding-name              ; ACCESSOR
   #:node-let-binding-value             ; ACCESSOR
   #:node-let-binding-list              ; TYPE
   #:node-let-declare                   ; STRUCT
   #:make-node-let-declare              ; CONSTRUCTOR
   #:node-let-declare-name              ; ACCESSOR
   #:node-let-declare-type              ; ACCESSOR
   #:node-let-declare-list              ; TYPE
   #:node-let                           ; STRUCT
   #:make-node-let                      ; CONSTRUCTOR
   #:node-let-bindings                  ; ACCESSOR
   #:node-let-declares                  ; ACCESSOR
   #:node-let-body                      ; ACCESSOR
   #:node-lisp                          ; STRUCT
   #:make-node-lisp                     ; CONSTRUCTOR
   #:node-lisp-type                     ; ACCESSOR
   #:node-lisp-vars                     ; ACCESSOR
   #:node-lisp-var-names                ; ACCESSOR
   #:node-lisp-body                     ; ACCESSOR
   #:node-match-branch                  ; STRUCT
   #:make-node-match-branch             ; CONSTRUCTOR
   #:node-match-branch-pattern          ; ACCESSOR
   #:node-match-branch-body             ; ACCESSOR
   #:node-match-branch-list             ; TYPE
   #:node-match                         ; STRUCT
   #:make-node-match                    ; CONSTRUCTOR
   #:node-match-expr                    ; ACCESSOR
   #:node-match-branches                ; ACCESSOR
   #:node-catch-branch                  ; STRUCT
   #:make-node-catch-branch             ; CONSTRUCTOR
   #:node-catch-branch-pattern          ; ACCESSOR
   #:node-catch-branch-body             ; ACCESSOR
   #:node-catch-branch-list             ; TYPE
   #:node-catch                         ; STRUCT
   #:make-node-catch                    ; CONSTRUCTOR
   #:node-catch-expr                    ; ACCESSOR
   #:node-catch-branches                ; ACCESSOR
   #:node-resumable-branch              ; STRUCT
   #:make-node-resumable-branch         ; CONSTRUCTOR
   #:node-resumable-branch-pattern      ; ACCESSOR
   #:node-resumable-branch-body         ; ACCESSOR
   #:node-resumable-branch-list         ; TYPE
   #:node-resumable                     ; STRUCT
   #:make-node-resumable                ; CONSTRUCTOR
   #:node-resumable-expr                ; ACCESSOR
   #:node-resumable-branches            ; ACCESSOR
   #:node-progn                         ; STRUCT
   #:make-node-progn                    ; CONSTRUCTOR
   #:node-progn-body                    ; ACCESSOR
   #:node-the                           ; STRUCT
   #:make-node-the                      ; CONSTRUCTOR
   #:node-the-type                      ; ACCESSOR
   #:node-the-expr                      ; ACCESSOR
   #:node-return                        ; STRUCT
   #:make-node-return                   ; CONSTRUCTOR
   #:node-return-expr                   ; ACCESSOR
   #:node-throw                         ; STRUCT
   #:make-node-throw                    ; CONSTRUCTOR
   #:node-throw-expr                    ; ACCESSOR
   #:node-resume-to                     ; STRUCT
   #:make-node-resume-to                ; CONSTRUCTOR
   #:node-resume-to-expr                ; ACCESSOR
   ;; Effect system nodes
   #:node-perform                       ; STRUCT
   #:make-node-perform                  ; CONSTRUCTOR
   #:node-perform-effect                ; ACCESSOR
   #:node-perform-arg                   ; ACCESSOR
   #:node-handle-branch                 ; STRUCT
   #:make-node-handle-branch            ; CONSTRUCTOR
   #:node-handle-branch-effect          ; ACCESSOR
   #:node-handle-branch-resume          ; ACCESSOR
   #:node-handle-branch-body            ; ACCESSOR
   #:node-handle-branch-location        ; ACCESSOR
   #:node-handle-branch-list            ; TYPE
   #:node-handle                        ; STRUCT
   #:make-node-handle                   ; CONSTRUCTOR
   #:node-handle-expr                   ; ACCESSOR
   #:node-handle-branches               ; ACCESSOR
   #:node-handle-return                 ; ACCESSOR
   ;; Delimited continuation nodes
   #:node-reset                         ; STRUCT
   #:make-node-reset                    ; CONSTRUCTOR
   #:node-reset-body                    ; ACCESSOR
   #:node-shift                         ; STRUCT
   #:make-node-shift                    ; CONSTRUCTOR
   #:node-shift-cont-var                ; ACCESSOR
   #:node-shift-body                    ; ACCESSOR
   #:node-call/cc                       ; STRUCT
   #:make-node-call/cc                  ; CONSTRUCTOR
   #:node-call/cc-cont-var              ; ACCESSOR
   #:node-call/cc-body                  ; ACCESSOR
   #:node-application                   ; STRUCT
   #:make-node-application              ; CONSTRUCTOR
   #:node-application-rator             ; ACCESSOR
   #:node-application-rands             ; ACCESSOR
   #:node-or                            ; STRUCT
   #:make-node-or                       ; CONSTRUCTOR
   #:node-or-nodes                      ; ACCESSOR
   #:node-and                           ; STRUCT
   #:make-node-and                      ; CONSTRUCTOR
   #:node-and-nodes                     ; ACCESSOR
   #:node-if                            ; STRUCT
   #:make-node-if                       ; CONSTRUCTOR
   #:node-if-expr                       ; ACCESSOR
   #:node-if-then                       ; ACCESSOR
   #:node-if-else                       ; ACCESSOR
   #:node-when                          ; STRUCT
   #:make-node-when                     ; CONSTRUCTOR
   #:node-when-expr                     ; ACCESSOR
   #:node-when-body                     ; ACCESSOR
   #:node-unless                        ; STRUCT
   #:make-node-unless                   ; CONSTRUCTOR
   #:node-unless-expr                   ; ACCESSOR
   #:node-unless-body                   ; ACCESSOR
   #:node-cond-clause                   ; STRUCT
   #:make-node-cond-clause              ; CONSTRUCTOR
   #:node-cond-clause-expr              ; ACCESSOR
   #:node-cond-clause-body              ; ACCESSOR
   #:node-cond-clause-list              ; TYPE
   #:node-cond                          ; STRUCT
   #:make-node-cond                     ; CONSTRUCTOR
   #:node-cond-clauses                  ; ACCESSOR
   #:node-do-bind                       ; STRUCT
   #:make-node-do-bind                  ; CONSTRUCTOR
   #:node-do-bind-pattern               ; ACCESSOR
   #:node-do-bind-expr                  ; ACCESSOR
   #:node-do-body-element               ; TYPE
   #:node-body-element-list             ; TYPE
   #:node-do                            ; STRUCT
   #:node-while                         ; STRUCT
   #:make-node-while                    ; CONSTRUCTOR
   #:node-while-label                   ; ACCESSOR
   #:node-while-expr                    ; ACCESSOR
   #:node-while-body                    ; ACCESSOR
   #:node-while-let                     ; STRUCT
   #:make-node-while-let                ; CONSTRUCTOR
   #:node-while-let-label               ; ACCESSOR
   #:node-while-let-pattern             ; ACCESSOR
   #:node-while-let-expr                ; ACCESSOR
   #:node-while-let-body                ; ACCESSOR
   #:node-loop                          ; STRUCT
   #:make-node-loop                     ; CONSTRUCTOR
   #:node-loop-body                     ; ACCESSOR
   #:node-loop-label                    ; ACCESSOR
   #:node-break                         ; STRUCT
   #:make-node-break                    ; CONSTRUCTOR
   #:node-break-label                   ; ACCESSOR
   #:node-continue                      ; STRUCT
   #:make-node-continue                 ; CONSTRUCTOR
   #:node-continue-label                ; ACCESSOR
   #:node-for                           ; STRUCT
   #:make-node-for                      ; CONSTRUCTOR
   #:node-for-label                     ; ACCESSOR
   #:node-for-pattern                   ; ACCESSOR
   #:node-for-expr                      ; ACCESSOR
   #:node-for-body                      ; ACCESSOR
   #:make-node-do                       ; CONSTRUCTOR
   #:node-do-nodes                      ; ACCESSOR
   #:node-do-last-node                  ; ACCESSOR
   #:parse-expression                   ; FUNCTION
   #:parse-expressions                  ; FUNCTION
   #:parse-body                         ; FUNCTION
   #:parse-variable                     ; FUNCTION
   ))

;;;;
;;;; Parser AST - Untyped Expression Nodes
;;;;
;;;; This module defines the Abstract Syntax Tree structures used during parsing,
;;;; before type checking. These nodes represent the syntactic structure of Coalton
;;;; code as parsed from source text.
;;;;
;;;; This is the first of two AST systems in the Coalton compiler:
;;;; 1. Parser AST (this module): Untyped nodes used during parsing/syntax analysis
;;;; 2. Codegen AST (codegen/ast.lisp): Typed nodes used during code generation
;;;;

(in-package #:coalton-impl/parser/expression)

(defvar *macro-expansion-count* 0)

(declaim (type util:symbol-list *loop-label-context*))
(defvar *loop-label-context* nil
  "A list of known labels encountered during parse.

Parsing (BREAK label) and (CONTINUE label) forms fails unless the label is found in
this list.

Rebound to NIL parsing an anonymous FN.")

(defconstant +macro-expansion-max+ 500)

;;;; # Expression Parsing
;;;;
;;;; Note that "expression" in the EBNF corresponds to the struct "node" in the lisp code.
;;;;
;;;; node-literal := <a lisp literal value>
;;;;
;;;; node-variable := <a lisp symbol not including "_" or starting with ".">
;;;;
;;;; node-accessor := <a lisp symbol starting with ".">
;;;;
;;;; ty := <defined in src/parser/types.lisp>
;;;;
;;;; qualified-ty := <defined in src/parser/types.lisp>
;;;;
;;;; pattern := <defined in src/parser/pattern.lisp>
;;;;
;;;; lisp-form := <an arbitrary lisp form>
;;;;
;;;; expression := node-variable
;;;;             | node-accessor
;;;;             | node-literal
;;;;             | node-abstraction
;;;;             | node-let
;;;;             | node-rec
;;;;             | node-lisp
;;;;             | node-match
;;;;             | node-progn
;;;;             | node-the
;;;;             | node-return
;;;;             | node-application
;;;;             | node-or
;;;;             | node-and
;;;;             | node-if
;;;;             | node-when
;;;;             | node-unless
;;;;             | node-cond
;;;;             | node-do
;;;;
;;;; node-bind := "(" "let" pattern "=" expression ")"
;;;;
;;;; node-body-element := expression | shorthand-let
;;;;
;;;; node-body := node-body-element* expression
;;;;
;;;; node-abstraction := "(" "fn" "(" pattern* ")" node-body ")"
;;;;
;;;; node-let-binding := "(" identifier expression ")"
;;;;
;;;; node-let-declare := "(" "declare" identifier qualified-ty ")"
;;;;
;;;; node-let := "(" "let" "(" (node-let-binding | node-let-declare)+ ")" body ")"
;;;;
;;;; node-rec := "(" "rec" (identifier | "(" identifier [qualified-ty] ")" ) "(" (node-let-binding | node-let-declare)+ ")" body ")"
;;;;
;;;; node-lisp := "(" "lisp" type "(" variable* ")" lisp-form+ ")"
;;;;
;;;; node-match-branch := "(" pattern body ")"
;;;;
;;;; node-match := "(" "match" pattern match-branch* ")"
;;;;
;;;; node-progn := "(" "progn" body ")"
;;;;
;;;; node-the := "(" "the" type expression ")"
;;;;
;;;; node-return := "(" "return" expression? ")"
;;;;
;;;; node-application := "(" expression expression* ")"
;;;;
;;;; node-or := "(" "or" expression+ ")"
;;;;
;;;; node-and := "(" "and" expression+ ")"
;;;;
;;;; node-if := "(" "if" expression expression expression ")"
;;;;
;;;; node-when := "(" "when" expression body ")"
;;;;
;;;; node-unless := "(" "unless" expression body ")"
;;;;
;;;; node-cond-clause := "(" expression body ")"
;;;;
;;;; node-cond := "(" "cond" cond-clause+ ")"
;;;;
;;;; node-do-bind "(" pattern "<-" expression ")"
;;;;
;;;; node-do-body-element := expression
;;;;                       | node-bind
;;;;                       | node-do-bind
;;;;
;;;; node-do := node-do-body-element* expression

(defstruct (node
            (:constructor nil)
            (:copier nil))
  (location (util:required 'location) :type source:location :read-only t))

(defmethod source:location ((self node))
  (node-location self))

(defun node-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'node-p x)))

(deftype node-list ()
  '(satisfies node-list-p))

(defstruct (node-variable
            (:include node)
            (:copier nil))
  (name (util:required 'name) :type identifier :read-only t))

(defun node-variable-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'node-variable-p x)))

(deftype node-variable-list ()
  '(satisfies node-variable-list-p))

(defstruct (node-accessor
            (:include node)
            (:copier nil))
  (name (util:required 'name) :type string :read-only t))

(defstruct (node-literal
            (:include node)
            (:copier nil))
  (value (util:required 'value) :type (and util:literal-value (not integer)) :read-only t))

(defstruct (node-integer-literal
            (:include node)
            (:copier nil))
  (value (util:required 'value) :type integer :read-only t))

;;
;; Does not subclass node, can only appear in a node body
;;
(defstruct (node-bind
            (:copier nil))
  (pattern  (util:required 'pattern)   :type pattern  :read-only t)
  (expr     (util:required 'expr)      :type node     :read-only t)
  (location (util:required 'location)  :type source:location :read-only t))

(defmethod source:location ((self node-bind))
  (node-bind-location self))

(deftype node-body-element ()
  '(or node node-bind))

(defun node-body-element-p (x)
  (typep x 'node-body-element))

(defun node-body-element-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'node-body-element-p x)))

(deftype node-body-element-list ()
  '(satisfies node-body-element-list-p))

;;
;; Does not subclass node, can only appear directly within some nodes
;;
;; - must contain at least one node
;; - cannot be terminated by a `node-bind'
;; - does not have source information (but its children do)
;;
(defstruct (node-body
            (:copier nil))
  (nodes     (util:required 'nodes)     :type node-body-element-list :read-only t)
  (last-node (util:required 'last-node) :type node                   :read-only t))

(defstruct (node-abstraction
            (:include node)
            (:copier nil))
  (params (util:required 'params) :type pattern-list :read-only t)
  (body   (util:required 'body)   :type node-body    :read-only t))

(defstruct (node-let-binding
            (:copier nil))
  (name     (util:required 'name)     :type node-variable   :read-only t)
  (value    (util:required 'value)    :type node            :read-only t)
  (location (util:required 'location) :type source:location :read-only t))

(defmethod source:location ((self node-let-binding))
  (node-let-binding-location self))

(defun node-let-binding-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'node-let-binding-p x)))

(deftype node-let-binding-list ()
  '(satisfies node-let-binding-list-p))

(defstruct (node-let-declare
            (:copier nil))
  (name     (util:required 'name)     :type node-variable   :read-only t)
  (type     (util:required 'type)     :type qualified-ty    :read-only t)
  (location (util:required 'location) :type source:location :read-only t))

(defmethod source:location ((self node-let-declare))
  (node-let-declare-location self))

(defun node-let-declare-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'node-let-declare-p x)))

(deftype node-let-declare-list ()
  '(satisfies node-let-declare-list-p))

(defstruct (node-let
            (:include node)
            (:copier nil))
  (bindings (util:required 'bindings) :type node-let-binding-list :read-only t)
  (declares (util:required 'declares) :type node-let-declare-list :read-only t)
  (body     (util:required 'body)     :type node-body             :read-only t))

(defstruct (node-lisp
            (:include node)
            (:copier nil))
  (type      (util:required 'type)      :type ty                 :read-only t)
  (vars      (util:required 'vars)      :type node-variable-list :read-only t)
  (var-names (util:required 'var-names) :type util:symbol-list   :read-only t)
  (body      (util:required 'body)      :type t                  :read-only t))

(defstruct (node-match-branch
            (:copier nil))
  (pattern  (util:required 'pattern)  :type pattern         :read-only t)
  (body     (util:required 'body)     :type node-body       :read-only t)
  (location (util:required 'location) :type source:location :read-only t))

(defmethod source:location ((self node-match-branch))
  (node-match-branch-location self))

(defun node-match-branch-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'node-match-branch-p x)))

(deftype node-match-branch-list ()
  '(satisfies node-match-branch-list-p))

(defstruct (node-match
            (:include node)
            (:copier nil))
  (expr     (util:required 'expr)     :type node                   :read-only t)
  (branches (util:required 'branches) :type node-match-branch-list :read-only t))

(defstruct (node-progn
            (:include node)
            (:copier nil))
  (body (util:required 'body) :type node-body :read-only t))

(defstruct (node-the
            (:include node)
            (:copier nil))
  (type (util:required 'type) :type ty   :read-only t)
  (expr (util:required 'expr) :type node :read-only t))

(defstruct (node-return
            (:include node)
            (:copier nil))
  (expr (util:required 'expr) :type (or null node) :read-only t))

(defstruct (node-application
            (:include node)
            (:copier nil))
  (rator (util:required 'rator) :type node      :read-only t)
  (rands (util:required 'rands) :type node-list :read-only t))

(defstruct (node-or
            (:include node)
            (:copier nil))
  (nodes (util:required 'nodes) :type node-list :read-only t))

(defstruct (node-and
            (:include node)
            (:copier nil))
  (nodes (util:required 'nodes) :type node-list :read-only t))

(defstruct (node-if
            (:include node)
            (:copier nil))
  (expr (util:required 'expr) :type node :read-only t)
  (then (util:required 'expr) :type node :read-only t)
  (else (util:required 'else) :type node :read-only t))

(defstruct (node-when
            (:include node)
            (:copier nil))
  (expr (util:required 'expr) :type node      :read-only t)
  (body (util:required 'body) :type node-body :read-only t))

(defstruct (node-unless
            (:include node)
            (:copier nil))
  (expr (util:required 'expr) :type node      :read-only t)
  (body (util:required 'body) :type node-body :read-only t))

(defstruct (node-cond-clause
            (:copier nil))
  (expr   (util:required 'expr)   :type node            :read-only t)
  (body   (util:required 'body)   :type node-body       :read-only t)
  (location (util:required 'location) :type source:location :read-only t))

(defmethod source:location ((self node-cond-clause))
  (node-cond-clause-location self))

(defun node-cond-clause-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'node-cond-clause-p x)))

(deftype node-cond-clause-list ()
  '(satisfies node-cond-clause-list-p))

(defstruct (node-cond
            (:include node)
            (:copier nil))
  (clauses (util:required 'clauses) :type node-cond-clause-list :read-only t))

(defstruct (node-do-bind
            (:copier nil))
  (pattern (util:required 'name)   :type pattern         :read-only t)
  (expr    (util:required 'expr)   :type node            :read-only t)
  (location  (util:required 'location) :type source:location :read-only t))

(defmethod source:location ((self node-do-bind))
  (node-do-bind-location self))

(deftype node-do-body-element ()
  '(or node node-bind node-do-bind))

(defun node-do-body-element-p (x)
  (typep x 'node-do-body-element))

(defun node-do-body-element-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'node-do-body-element-p x)))

(deftype node-do-body-element-list ()
  '(satisfies node-do-body-element-list-p))

(defstruct (node-do
            (:include node)
            (:copier nil))
  (nodes     (util:required 'nodes)     :type node-do-body-element-list :read-only t)
  (last-node (util:required 'last-node) :type node                      :read-only t))

(defstruct (node-while
            (:include node)
            (:copier nil))
  (label (util:required 'label) :type keyword   :read-only t)
  (expr  (util:required 'expr)  :type node      :read-only t)
  (body  (util:required 'body)  :type node-body :read-only t))

(defstruct (node-while-let
            (:include node)
            (:copier nil))
  (label   (util:required 'label)   :type keyword   :read-only t)
  (pattern (util:required 'pattern) :type pattern   :read-only t)
  (expr    (util:required 'expr)    :type node      :read-only t)
  (body    (util:required 'body)    :type node-body :read-only t))

(defstruct (node-break
            (:include node)
            (:copier nil))
  (label (util:required 'label) :type keyword :read-only t))

(defstruct (node-continue
            (:include node)
            (:copier nil))
  (label (util:required 'label) :type keyword :read-only t))

(defstruct (node-loop
            (:include node)
            (:copier nil))
  (label (util:required 'label) :type keyword   :read-only t)
  (body  (util:required 'body)  :type node-body :read-only t))

(defstruct (node-for
            (:include node)
            (:copier nil))
  (label   (util:required 'label)   :type keyword   :read-only t)
  (pattern (util:required 'pattern) :type pattern   :read-only t)
  (expr    (util:required 'expr)    :type node      :read-only t)
  (body    (util:required 'body)    :type node-body :read-only t))

(defstruct (node-throw
            (:include node)
            (:copier nil))
  (expr (util:required 'expr) :type node :read-only t))

(defstruct (node-resume-to
            (:include node)
            (:copier nil))
  (expr (util:required 'expr) :type node :read-only t))

(defstruct (node-resumable-branch
            (:copier nil))
  (pattern  (util:required 'pattern)  :type pattern         :read-only t)
  (body     (util:required 'body)     :type node-body       :read-only t)
  (location (util:required 'location) :type source:location :read-only t))

(defmethod source:location ((self node-resumable-branch))
  (node-resumable-branch-location self))

(defun node-resumable-branch-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'node-resumable-branch-p x)))

(deftype node-resumable-branch-list ()
  '(satisfies node-resumable-branch-list-p))

(defstruct (node-resumable
            (:include node)
            (:copier nil))
  (expr     (util:required 'expr)     :type node                         :read-only t)
  (branches (util:required 'branches) :type node-resumable-branch-list :read-only t))

(defstruct (node-catch-branch
            (:copier nil))
  (pattern  (util:required 'pattern)  :type pattern         :read-only t)
  (body     (util:required 'body)     :type node-body       :read-only t)
  (location (util:required 'location) :type source:location :read-only t))

(defmethod source:location ((self node-catch-branch))
  (node-catch-branch-location self))

(defun node-catch-branch-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'node-catch-branch-p x)))

(deftype node-catch-branch-list ()
  '(satisfies node-catch-branch-list-p))

(defstruct (node-catch
            (:include node)
            (:copier nil))
  (expr     (util:required 'expr)     :type node                   :read-only t)
  (branches (util:required 'branches) :type node-catch-branch-list :read-only t))

;;;
;;; Algebraic Effect Nodes
;;;

(defstruct (node-perform
            (:include node)
            (:copier nil))
  "Perform an effect operation.

EFFECT: The effect operation symbol (e.g., STATE.GET, CONSOLE.READ-LINE)
ARG: Optional argument to the effect operation (may be nil)"
  (effect (util:required 'effect) :type symbol             :read-only t)
  (arg    nil                     :type (or null node)     :read-only t))

(defstruct (node-handle-branch
            (:copier nil))
  "A branch in an effect handler.

EFFECT: The effect operation being handled
RESUME: Variable name for the resumption function (or nil for non-resumable)
BODY: The handler body"
  (effect   (util:required 'effect)   :type symbol          :read-only t)
  (resume   nil                       :type (or null symbol) :read-only t)
  (body     (util:required 'body)     :type node-body       :read-only t)
  (location (util:required 'location) :type source:location :read-only t))

(defmethod source:location ((self node-handle-branch))
  (node-handle-branch-location self))

(defun node-handle-branch-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'node-handle-branch-p x)))

(deftype node-handle-branch-list ()
  '(satisfies node-handle-branch-list-p))

(defstruct (node-handle
            (:include node)
            (:copier nil))
  "Handle effect operations with resumption support.

EXPR: The expression whose effects are being handled
BRANCHES: List of node-handle-branch for effect handlers
RETURN: Optional handler for the final return value"
  (expr     (util:required 'expr)     :type node                    :read-only t)
  (branches (util:required 'branches) :type node-handle-branch-list :read-only t)
  (return   nil                       :type (or null node-body)     :read-only t))

;;;
;;; Delimited Continuation Nodes
;;;

(defstruct (node-reset
            (:include node)
            (:copier nil))
  "A reset (prompt/delimiter) for delimited continuations.

Reset delimits the extent of continuation capture. Continuations captured
by shift within the body will only extend up to this reset boundary.

(reset body) establishes a continuation delimiter around body."
  (body (util:required 'body) :type node-body :read-only t))

(defstruct (node-shift
            (:include node)
            (:copier nil))
  "Capture the current delimited continuation.

Shift captures the continuation up to the nearest enclosing reset and
binds it to the given variable. The captured continuation can be invoked
zero, once, or multiple times.

(shift k body) captures continuation k and evaluates body.

CONT-VAR: Variable name to bind the captured continuation
BODY: Expression to evaluate with the captured continuation"
  (cont-var (util:required 'cont-var) :type node-variable :read-only t)
  (body     (util:required 'body)     :type node-body     :read-only t))

(defstruct (node-call/cc
            (:include node)
            (:copier nil))
  "Call with current continuation (non-delimited).

This is the traditional call/cc that captures the entire continuation.
Delimited continuations (shift/reset) are generally preferred.

(call/cc (fn (k) body)) captures the full continuation as k.

CONT-VAR: Variable name to bind the captured continuation
BODY: Expression to evaluate with the captured continuation"
  (cont-var (util:required 'cont-var) :type node-variable :read-only t)
  (body     (util:required 'body)     :type node-body     :read-only t))

(defun parse-expression (form source)
  (declare (type stx:syntax-object form)
           (values node &optional))

  (cond
    ;;
    ;; Atoms
    ;;

    ((stx-cst:stx-atom-p form)
     (typecase (stx:syntax-e form)
       (null
        (parse-error "Malformed expression"
                     (note source form "unexpected `nil` or `()`")))

       (symbol
        (if (char= #\. (aref (symbol-name (stx:syntax-e form)) 0))
            (parse-accessor form source)
            (parse-variable form source)))

       (t
        (parse-literal form source))))

    ;;
    ;; Dotted Lists
    ;;

    ((not (stx-cst:stx-proper-list-p form))
     (parse-error "Malformed expression"
                  (note source form "unexpected dotted list")))

    ;;
    ;; Keywords
    ;;

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:fn (stx:syntax-e (stx-cst:stx-first form))))
     (let ((params)
           (body))

       ;; (fn)
       (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
         (parse-error "Malformed function"
                      (note-end source (stx-cst:stx-first form) "expected function arguments")))

       ;; (fn (...))
       (unless (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
         (parse-error "Malformed function"
                      (note-end source (stx-cst:stx-second form) "expected function body")))

       ;; (fn x ...)
       ;;
       ;; NOTE: (fn () ...) is allowed
       (when (and (stx-cst:stx-atom-p (stx-cst:stx-second form))
                  (not (null (stx:syntax-e (stx-cst:stx-second form)))))
         (parse-error "Malformed function"
                      (note source (stx-cst:stx-second form)
                            "malformed argument list")
                      (help source (stx-cst:stx-second form)
                            (lambda (existing)
                              (concatenate 'string "(" existing ")"))
                            "add parentheses")))
       ;; Bind *LOOP-LABEL-CONTEXT* to NIL to disallow BREAKing from
       ;; or CONTINUING with loops that enclose the FN form.
       (let ((*loop-label-context* nil))
         (setf params
               (loop :for vars := (stx-cst:stx-second form) :then (stx-cst:stx-rest vars)
                     :while (stx-cst:stx-consp vars)
                     :collect (parse-pattern (stx-cst:stx-first vars) source)))
         (setf body (parse-body (stx-cst:stx-nthrest 2 form) form source))
         (make-node-abstraction
          :params params
          :body body
          :location (form-location source form)))))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:throw (stx:syntax-e (stx-cst:stx-first form))))
     (let (expr)

       ;; (throw)
       (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
         (parse-error "Malformed throw expression"
                      (note source (stx-cst:stx-first form) "expression expected")))

       (setf expr (parse-expression (stx-cst:stx-second form) source))

       ;; (throw a b ...)
       (when (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
         (parse-error "Malformed throw expression"
                      (note source (stx-cst:stx-first (stx-cst:stx-rest (stx-cst:stx-rest form)))
                            "unexpected trailing form")))

       (make-node-throw
        :expr expr
        :location (form-location source form))))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:resume-to (stx:syntax-e (stx-cst:stx-first form))))
     (let (expr)

       ;; (resume-to)
       (unless (stx-cst:stx-consp (stx-cst:stx-rest form))

         (parse-error "Malformed resume-to expression"
                      (note-end source (stx-cst:stx-first form) "expression expected")))

       (setf expr (parse-expression (stx-cst:stx-second form) source))

       ;; (resume-to a b ...)
       (when (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
         (parse-error "Malformed resume-to expression"
                      (note source (stx-cst:stx-first (stx-cst:stx-rest (stx-cst:stx-rest form)))
                            "unexpected trailing form")))

       (make-node-resume-to
        :expr expr
        :location (form-location source form))))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:resumable (stx:syntax-e (stx-cst:stx-first form))))

     ;; (resumable)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed resumable expression"
                    (note-end source (stx-cst:stx-first form) "expected expression")))

     ;; (resumable expr)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
       (parse-error "Malformed resumable expression"
                    (note-end source (stx-cst:stx-second form) "expected resumeable cases")))

     (make-node-resumable
      :expr (parse-expression (stx-cst:stx-second form) source)
      :branches (loop :for branches := (stx-cst:stx-nthrest 2 form) :then (stx-cst:stx-rest branches)
                      :while (stx-cst:stx-consp branches)
                      :collect (parse-resumable-branch (stx-cst:stx-first branches) source))
      :location (form-location source form)))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:catch (stx:syntax-e (stx-cst:stx-first form))))

     ;; (catch)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed catch expression"
                    (note-end source (stx-cst:stx-first form) "expected expression")))

     ;; (catch expr)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
       (parse-error "Malformed catch expression"
                    (note-end source (stx-cst:stx-second form) "expected catch cases")))


     (make-node-catch
      :expr (parse-expression (stx-cst:stx-second form) source)
      :branches (loop :for branches := (stx-cst:stx-nthrest 2 form) :then (stx-cst:stx-rest branches)
                      :while (stx-cst:stx-consp branches)
                      :collect (parse-catch-branch (stx-cst:stx-first branches) source))
      :location (form-location source form)))

    ;;
    ;; Algebraic Effects: perform and handle
    ;;

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:perform (stx:syntax-e (stx-cst:stx-first form))))

     ;; (perform)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed perform expression"
                    (note-end source (stx-cst:stx-first form) "expected effect operation")))

     (let* ((effect-form (stx-cst:stx-second form))
            (effect-name nil)
            (effect-arg nil))

       ;; Parse effect operation: either EFFECT.OP or (EFFECT.OP arg)
       (cond
         ;; (perform EFFECT.OP) - nullary effect operation
         ((stx-cst:stx-atom-p effect-form)
          (unless (symbolp (stx:syntax-e effect-form))
            (parse-error "Malformed perform expression"
                         (note source effect-form "expected effect operation symbol")))
          (setf effect-name (stx:syntax-e effect-form)))

         ;; (perform (EFFECT.OP arg)) - effect operation with argument
         ((stx-cst:stx-consp effect-form)
          (unless (and (stx-cst:stx-atom-p (stx-cst:stx-first effect-form))
                       (symbolp (stx:syntax-e (stx-cst:stx-first effect-form))))
            (parse-error "Malformed perform expression"
                         (note source (stx-cst:stx-first effect-form) "expected effect operation symbol")))
          (setf effect-name (stx:syntax-e (stx-cst:stx-first effect-form)))
          ;; Parse the argument if present
          (when (stx-cst:stx-consp (stx-cst:stx-rest effect-form))
            (setf effect-arg (parse-expression (stx-cst:stx-second effect-form) source))
            ;; Check for extra arguments
            (when (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest effect-form)))
              (parse-error "Malformed perform expression"
                           (note source (stx-cst:stx-first (stx-cst:stx-rest (stx-cst:stx-rest effect-form)))
                                 "unexpected extra argument")))))

         (t
          (parse-error "Malformed perform expression"
                       (note source effect-form "expected effect operation"))))

       ;; Check for trailing forms after the effect
       (when (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
         (parse-error "Malformed perform expression"
                      (note source (stx-cst:stx-first (stx-cst:stx-rest (stx-cst:stx-rest form)))
                            "unexpected trailing form")))

       (make-node-perform
        :effect effect-name
        :arg effect-arg
        :location (form-location source form))))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:handle (stx:syntax-e (stx-cst:stx-first form))))

     ;; (handle)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed handle expression"
                    (note-end source (stx-cst:stx-first form) "expected expression")))

     ;; (handle expr)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
       (parse-error "Malformed handle expression"
                    (note-end source (stx-cst:stx-second form) "expected effect handlers")))

     (let ((expr (parse-expression (stx-cst:stx-second form) source))
           (branches nil)
           (return-handler nil))

       ;; Parse handler branches
       (loop :for rest := (stx-cst:stx-nthrest 2 form) :then (stx-cst:stx-rest rest)
             :while (stx-cst:stx-consp rest)
             :for branch-form := (stx-cst:stx-first rest)
             :do (multiple-value-bind (branch is-return)
                     (parse-handle-branch branch-form source)
                   (if is-return
                       (if return-handler
                           (parse-error "Duplicate return handler"
                                        (note source branch-form "return handler already defined"))
                           (setf return-handler branch))
                       (push branch branches))))

       (make-node-handle
        :expr expr
        :branches (nreverse branches)
        :return return-handler
        :location (form-location source form))))

    ;;
    ;; Delimited Continuations: reset, shift, call/cc
    ;;

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:cont/reset (stx:syntax-e (stx-cst:stx-first form))))

     ;; (reset)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed reset expression"
                    (note-end source (stx-cst:stx-first form) "expected body")))

     (make-node-reset
      :body (parse-body (stx-cst:stx-rest form) (stx-cst:stx-first form) source)
      :location (form-location source form)))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:cont/shift (stx:syntax-e (stx-cst:stx-first form))))

     ;; (shift)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed shift expression"
                    (note-end source (stx-cst:stx-first form) "expected continuation variable")))

     ;; (shift k)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
       (parse-error "Malformed shift expression"
                    (note-end source (stx-cst:stx-second form) "expected body")))

     ;; Validate continuation variable
     (unless (and (stx-cst:stx-atom-p (stx-cst:stx-second form))
                  (symbolp (stx:syntax-e (stx-cst:stx-second form))))
       (parse-error "Malformed shift expression"
                    (note source (stx-cst:stx-second form) "expected continuation variable name")))

     (make-node-shift
      :cont-var (parse-variable (stx-cst:stx-second form) source)
      :body (parse-body (stx-cst:stx-nthrest 2 form) (stx-cst:stx-second form) source)
      :location (form-location source form)))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:call/cc (stx:syntax-e (stx-cst:stx-first form))))

     ;; (call/cc)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed call/cc expression"
                    (note-end source (stx-cst:stx-first form) "expected continuation variable")))

     ;; (call/cc k)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
       (parse-error "Malformed call/cc expression"
                    (note-end source (stx-cst:stx-second form) "expected body")))

     ;; Validate continuation variable
     (unless (and (stx-cst:stx-atom-p (stx-cst:stx-second form))
                  (symbolp (stx:syntax-e (stx-cst:stx-second form))))
       (parse-error "Malformed call/cc expression"
                    (note source (stx-cst:stx-second form) "expected continuation variable name")))

     (make-node-call/cc
      :cont-var (parse-variable (stx-cst:stx-second form) source)
      :body (parse-body (stx-cst:stx-nthrest 2 form) (stx-cst:stx-second form) source)
      :location (form-location source form)))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:let (stx:syntax-e (stx-cst:stx-first form))))

     ;; (let)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed let"
                    (note-end source (stx-cst:stx-first form) "expected let binding list")))

     ;; (let (...))
     (unless (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
       (parse-error "Malformed let"
                    (note-end source (stx-cst:stx-second form) "expected let body")))

     (unless (stx-cst:stx-proper-list-p (stx-cst:stx-second form))
       (parse-error "Malformed let"
                    (note source (stx-cst:stx-second form) "expected binding list")))

     (let* (declares

            (bindings (loop :for bindings := (stx-cst:stx-second form) :then (stx-cst:stx-rest bindings)
                            :while (stx-cst:stx-consp bindings)
                            :for binding := (stx-cst:stx-first bindings)
                            ;; if binding is in the form (declare x y+)
                            :if (and (stx-cst:stx-consp binding)
                                     (stx-cst:stx-consp (stx-cst:stx-rest form))
                                     (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
                                     (stx-cst:stx-atom-p (stx-cst:stx-first binding))
                                     (eq (stx:syntax-e (stx-cst:stx-first binding)) 'coalton:declare))
                              :do (push (parse-let-declare binding source) declares)
                            :else
                              :collect (parse-let-binding binding source))))

       (make-node-let
        :bindings bindings
        :declares (nreverse declares)
        :body (parse-body (stx-cst:stx-nthrest 2 form) form source)
        :location (form-location source form))))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:rec (stx:syntax-e (stx-cst:stx-first form))))

     (multiple-value-bind (name type rec-bindings body)
         (cond
           ;; (rec)
           ((not (stx-cst:stx-consp (stx-cst:stx-rest form)))
            (parse-error "Malformed rec"
                         (note-end source (stx-cst:stx-first form)
                                   "expected function name")))
           ;; (rec name)
           ((not (stx-cst:stx-consp (stx-cst:stx-nthrest 2 form)))
            (parse-error "Malformed rec"
                         (note-end source (stx-cst:stx-second form)
                                   "expected binding list")))
           ;; (rec name bindings)
           ((stx-cst:stx-null-p (stx-cst:stx-nthrest 3 form))
            (parse-error "Malformed rec"
                         (note-end source (stx-cst:stx-third form)
                                   "expected rec body")))
           ((stx-cst:stx-null-p (stx-cst:stx-second form))
            (parse-error "Malformed rec"
                         (note source (stx-cst:stx-second form)
                               "unexpected empty list")))
           ;; (rec name bindings ...)
           ((stx-cst:stx-atom-p (stx-cst:stx-second form))
            (values (stx-cst:stx-second form)
                    nil
                    (stx-cst:stx-third form)
                    (stx-cst:stx-nthrest 3 form)))
           ;; (rec (name qual-ty) bindings ...)
           (t
            (cond
              ((stx-cst:stx-null-p (stx-cst:stx-rest (stx-cst:stx-second form)))
               (values (stx-cst:stx-first (stx-cst:stx-second form))
                       nil
                       (stx-cst:stx-third form)
                       (stx-cst:stx-nthrest 3 form)))
              ((stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-second form)))
               (when (stx-cst:stx-consp (stx-cst:stx-nthrest 2 (stx-cst:stx-second form)))
                 (parse-error "Malformed rec"
                              (note-end source (stx-cst:stx-second (stx-cst:stx-second form))
                                        "unexpected trailing form(s)")))
               (values (stx-cst:stx-first (stx-cst:stx-second form))
                       (stx-cst:stx-second (stx-cst:stx-second form))
                       (stx-cst:stx-third form)
                       (stx-cst:stx-nthrest 3 form)))
              (t
               (parse-error "Malformed rec"
                            (note source (stx-cst:stx-rest (stx-cst:stx-second form))
                                  "unexpected dotted list"))))))

       (unless (stx-cst:stx-proper-list-p rec-bindings)
         (parse-error "Malformed rec"
                      (note source rec-bindings
                            "expected binding list")))

       (multiple-value-bind (declares bindings vars)
           (loop :for bindings := rec-bindings :then (stx-cst:stx-rest bindings)
                 :while (stx-cst:stx-consp bindings)
                 :for binding := (stx-cst:stx-first bindings)
                 ;; if binding is in the form (declare x y+)
                 :if (and (stx-cst:stx-consp binding)
                          (stx-cst:stx-atom-p (stx-cst:stx-first binding))
                          (eq (stx:syntax-e (stx-cst:stx-first binding)) 'coalton:declare))
                   :collect (parse-let-declare binding source)
                     :into declares
                 :else
                   :collect (parse-rec-binding binding source) :into binding-list
                   :and :collect (stx-cst:stx-first binding) :into vars
                 :finally
                    (return (values declares binding-list vars)))

         (make-node-let
          :declares declares
          :bindings
          ;; Remove recursive bindings
          (remove-if
           (lambda (binding)
             (and (typep (node-let-binding-value binding)
                         'node-variable)

                  (eq (node-variable-name (node-let-binding-name binding))
                      (node-variable-name (node-let-binding-value binding)))))
           bindings)
          :body
          (make-node-body
           :nodes nil
           :last-node
           (make-node-let
            :declares (if type
                          (list
                           (make-node-let-declare
                            :name (parse-variable name source)
                            :type (parse-qualified-type type source)
                            :location (form-location source type)))
                          nil)
            :bindings (list (make-node-let-binding
                             :name (parse-variable name source)
                             :value
                             (make-node-abstraction
                              :params (mapcar (lambda (var)
                                                (parse-pattern var source))
                                              vars)
                              :body (parse-body body form source)
                              :location (form-location source form))
                             :location (form-location source form)))
            :body
            (make-node-body
             :nodes nil
             :last-node
             (make-node-application
              :rator (parse-expression name source)
              :rands (mapcar #'node-let-binding-name bindings)
              :location (form-location source form)))
            :location (form-location source form)))
          :location (form-location source form)))))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:lisp (stx:syntax-e (stx-cst:stx-first form))))
     ;; (lisp)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed lisp expression"
                    (note-end source (stx-cst:stx-first form) "expected expression type")))

     ;; (lisp T)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
       (parse-error "Malformed lisp expression"
                    (note-end source (stx-cst:stx-second form) "expected binding list")))

     ;; (lisp T (...))
     (unless (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest form))))
       (parse-error "Malformed lisp expression"
                    (note source form "expected body")))

     (let ((vars (loop :for vars := (stx-cst:stx-third form) :then (stx-cst:stx-rest vars)
                       :while (stx-cst:stx-consp vars)
                       :collect (parse-variable (stx-cst:stx-first vars) source))))
       (make-node-lisp
        :type (parse-type (stx-cst:stx-second form) source)
        :vars vars
        :var-names (mapcar #'node-variable-name vars)
        :body (mapcar #'stx:syntax->datum (stx:syntax-e (stx-cst:stx-nthrest 3 form)))
        :location (form-location source form))))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:match (stx:syntax-e (stx-cst:stx-first form))))

     ;; (match)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed match expression"
                    (note-end source (stx-cst:stx-first form) "expected expression")))

     (make-node-match
      :expr (parse-expression (stx-cst:stx-second form) source)
      :branches (loop :for branches := (stx-cst:stx-nthrest 2 form) :then (stx-cst:stx-rest branches)
                      :while (stx-cst:stx-consp branches)
                      :collect (parse-match-branch (stx-cst:stx-first branches) source))
      :location (form-location source form)))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:progn (stx:syntax-e (stx-cst:stx-first form))))
     (make-node-progn
      :body (parse-body (stx-cst:stx-rest form) (stx-cst:stx-first form) source)
      :location (form-location source form)))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:the (stx:syntax-e (stx-cst:stx-first form))))
     ;; (the)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed the expression"
                    (note-end source (stx-cst:stx-first form) "expected type")))

     ;; (the T)
     (unless (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
       (parse-error "Malformed the expression"
                    (note-end source (stx-cst:stx-second form) "expected value")))

     ;; (the a b c)
     (when (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest form))))
       (parse-error "Malformed the expression"
                    (note source (stx-cst:stx-first (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest form))))
                          "unexpected trailing form")))

     (make-node-the
      :type (parse-type (stx-cst:stx-second form) source)
      :expr (parse-expression (stx-cst:stx-third form) source)
      :location (form-location source form)))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:return (stx:syntax-e (stx-cst:stx-first form))))
     (let (expr)

       ;; (return ...)
       (when (stx-cst:stx-consp (stx-cst:stx-rest form))
         ;; (return a b ...)
         (when (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
           (parse-error "Malformed return expression"
                        (note source (stx-cst:stx-first (stx-cst:stx-rest (stx-cst:stx-rest form)))
                              "unexpected trailing form")))

         (setf expr (parse-expression (stx-cst:stx-second form) source)))

       (make-node-return
        :expr expr
        :location (form-location source form))))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:or (stx:syntax-e (stx-cst:stx-first form))))
     (make-node-or
      :nodes (loop :for args := (stx-cst:stx-rest form) :then (stx-cst:stx-rest args)
                   :while (stx-cst:stx-consp args)
                   :for arg := (stx-cst:stx-first args)
                   :collect (parse-expression arg source))
      :location (form-location source form)))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:and (stx:syntax-e (stx-cst:stx-first form))))

     (make-node-and
      :nodes (loop :for args := (stx-cst:stx-rest form) :then (stx-cst:stx-rest args)
                   :while (stx-cst:stx-consp args)
                   :for arg := (stx-cst:stx-first args)
                   :collect (parse-expression arg source))
      :location (form-location source form)))
    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:if (stx:syntax-e (stx-cst:stx-first form))))
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed if expression"
                    (note-end source (stx-cst:stx-first form) "expected a predicate")))

     (unless (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
       (parse-error "Malformed if expression"
                    (note-end source (stx-cst:stx-second form) "expected a form")))

     (unless (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest form))))
       (parse-error "Malformed if expression"
                    (note-end source (stx-cst:stx-third form) "expected a form")))

     (when (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest form)))))
       (parse-error "Malformed if expression"
                    (note source (stx-cst:stx-first (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest form)))))
                          "unexpected trailing form")))

     (make-node-if
      :expr (parse-expression (stx-cst:stx-second form) source)
      :then (parse-expression (stx-cst:stx-third form) source)
      :else (parse-expression (stx-cst:stx-nth 3 form) source)
      :location (form-location source form)))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:when (stx:syntax-e (stx-cst:stx-first form))))
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed when expression"
                    (note-end source (stx-cst:stx-first form) "expected a predicate")))

     (make-node-when
      :expr (parse-expression (stx-cst:stx-second form) source)
      :body (parse-body (stx-cst:stx-rest (stx-cst:stx-rest form)) (stx-cst:stx-second form) source)
      :location (form-location source form)))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:unless (stx:syntax-e (stx-cst:stx-first form))))
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed unless expression"
                    (note-end source (stx-cst:stx-first form) "expected a predicate")))

     (make-node-unless
      :expr (parse-expression (stx-cst:stx-second form) source)
      :body (parse-body (stx-cst:stx-rest (stx-cst:stx-rest form)) (stx-cst:stx-second form) source)
      :location (form-location source form)))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:cond (stx:syntax-e (stx-cst:stx-first form))))
     (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
       (parse-error "Malformed cond expression"
                    (note-end source (stx-cst:stx-first form) "expected one or more clauses")))

     (make-node-cond
      :clauses (loop :for clauses := (stx-cst:stx-rest form) :then (stx-cst:stx-rest clauses)
                     :while (stx-cst:stx-consp clauses)
                     :for clause := (stx-cst:stx-first clauses)
                     :collect (parse-cond-clause clause source))
      :location (form-location source form)))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:do (stx:syntax-e (stx-cst:stx-first form))))
     (parse-do form source))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:while (stx:syntax-e (stx-cst:stx-first form))))
     (multiple-value-bind (label labelled-body label-cst) (take-label form)
       ;; (while [label])
       (unless (stx-cst:stx-consp labelled-body)
         (parse-error "Malformed while expression"
                      (note-end source (or label-cst (stx-cst:stx-first form)) "expected condition")))
       ;; (while [label] condition)
       (unless (stx-cst:stx-consp (stx-cst:stx-rest labelled-body))
         (parse-error "Malformed while expression"
                      (note-end source (stx-cst:stx-first labelled-body) "expected body")))
       (let ((*loop-label-context*
               (if label
                   (list* label const:+default-loop-label+ *loop-label-context*)
                   (cons const:+default-loop-label+ *loop-label-context*))))

         (make-node-while
          :location (form-location source form)
          :label (or label const:+default-loop-label+)
          :expr (parse-expression (stx-cst:stx-first labelled-body) source)
          :body (parse-body (stx-cst:stx-rest labelled-body) form source)))))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:while-let (stx:syntax-e (stx-cst:stx-first form))))

     (multiple-value-bind (label labelled-body label-cst) (take-label form)
       ;; (while-let [label])
       (unless (stx-cst:stx-consp labelled-body)
         (parse-error "Malformed while-let expression"
                      (note-end source (or label-cst (stx-cst:stx-first form)) "expected pattern")))

       ;; (while-let [label] pattern)
       (unless (and (stx-cst:stx-consp (stx-cst:stx-rest labelled-body))
                    (eq 'coalton:= (stx:syntax-e (stx-cst:stx-second labelled-body))))
         (parse-error "Malformed while-let expression"
                      (if (stx-cst:stx-consp (stx-cst:stx-rest labelled-body))
                          (note source (stx-cst:stx-second labelled-body) "expected =")
                          (note-end source (stx-cst:stx-first labelled-body) "expected ="))))

       ;; (when-let [label] pattern =)
       (unless (stx-cst:stx-consp (stx-cst:stx-nthrest 2 labelled-body))
         (parse-error "Malformed while-let expression"
                      (note-end source (stx-cst:stx-second labelled-body) "expected expression")))

       ;; (when-let pattern = expr)
       (unless (stx-cst:stx-consp (stx-cst:stx-nthrest 3 labelled-body))
         (parse-error "Malformed while-let expression"
                      (note-end source (stx-cst:stx-third labelled-body) "expected body")))
       (let* ((*loop-label-context*
                (if label
                    (list* label const:+default-loop-label+ *loop-label-context*)
                    (cons const:+default-loop-label+ *loop-label-context*))))
         (make-node-while-let
          :location (form-location source form)
          :label (or label const:+default-loop-label+)
          :pattern (parse-pattern (stx-cst:stx-first labelled-body) source)
          :expr (parse-expression (stx-cst:stx-third labelled-body) source)
          :body (parse-body (stx-cst:stx-nthrest 3 labelled-body) form source)))))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:loop (stx:syntax-e (stx-cst:stx-first form))))
     (multiple-value-bind (label labelled-body label-cst) (take-label form)
       (unless (stx-cst:stx-consp labelled-body)
         (parse-error "Malformed loop expression"
                      (note-end source (or label-cst (stx-cst:stx-first form)) "expected a loop body")))

       (let* ((*loop-label-context*
                (if label
                    (list* label const:+default-loop-label+ *loop-label-context*)
                    (cons const:+default-loop-label+ *loop-label-context*))))
         (make-node-loop
          :location (form-location source form)
          :label (or label const:+default-loop-label+)
          :body (parse-body labelled-body form source)))))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:break (stx:syntax-e (stx-cst:stx-first form))))

     (multiple-value-bind (label postlabel) (take-label form)
       (unless (stx-cst:stx-null-p postlabel)
         (parse-error "Invalid argument in break"
                      (note-end source form
                                (if label
                                    "unexpected argument after label"
                                    "expected a keyword"))))

       (if label
           (unless (member label *loop-label-context*)
             (parse-error "Invalid label in break"
                          (note source (stx-cst:stx-second form)
                                "label not found in any enclosing loop")))
           (unless *loop-label-context*
             (parse-error "Invalid break"
                          (note source form
                                "break does not appear in an enclosing loop"))))

       (make-node-break :location (form-location source form)
                        :label (or label (car *loop-label-context*)))))

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:continue (stx:syntax-e (stx-cst:stx-first form))))

     (multiple-value-bind (label postlabel) (take-label form)
       (unless (stx-cst:stx-null-p postlabel)
         (parse-error "Invalid argument in continue"
                      (note source form
                            (if label
                                "unexpected argument after label"
                                "expected a keyword"))))

       (if label
           (unless (member label *loop-label-context*)
             (parse-error "Invalid label in continue"
                          (note source (stx-cst:stx-second form)
                                "label not found in any enclosing loop")))
           (unless *loop-label-context*
             (parse-error "Invalid continue"
                          (note source form
                                "continue does not appear in an enclosing loop"))))

       (make-node-continue :location (form-location source form)
                           :label (or label (car *loop-label-context*)))))


    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq 'coalton:for (stx:syntax-e (stx-cst:stx-first form))))

     (multiple-value-bind (label labelled-body label-cst) (take-label form)
       ;; (for [label])
       (unless (stx-cst:stx-consp labelled-body)
         (parse-error "Malformed for expression"
                      (note-end source (or label-cst (stx-cst:stx-first form)) "expected pattern")))

       ;; (for [label] pattern)
       (unless (and (stx-cst:stx-consp (stx-cst:stx-rest labelled-body))
                    (stx-cst:stx-atom-p (stx-cst:stx-second labelled-body))
                    (eq 'coalton:in (stx:syntax-e (stx-cst:stx-second labelled-body))))
         (parse-error "Malformed for expression"
                      (if (and (stx-cst:stx-consp (stx-cst:stx-rest labelled-body))
                               (stx-cst:stx-second labelled-body))
                          (note source (stx-cst:stx-second labelled-body) "expected in")
                          (note-end source (stx-cst:stx-first labelled-body) "expected in"))))

       ;; (for [label] pattern in)
       (unless (stx-cst:stx-consp (stx-cst:stx-nthrest 2 labelled-body))
         (parse-error "Malformed for expression"
                      (note-end source form "expected expression")))

       ;; (for [label] pattern in expr)
       (unless (stx-cst:stx-consp (stx-cst:stx-nthrest 3 labelled-body))
         (parse-error "Malformed for expression"
                      (note-end source (stx-cst:stx-third labelled-body) "expected body")))

       (let ((*loop-label-context*
               (if label
                   (list* label const:+default-loop-label+ *loop-label-context*)
                   (cons const:+default-loop-label+ *loop-label-context*))))
         (make-node-for
          :location (form-location source form)
          :label (or label const:+default-loop-label+)
          :pattern (parse-pattern (stx-cst:stx-first labelled-body) source)
          :expr (parse-expression (stx-cst:stx-third labelled-body) source)
          :body (parse-body (stx-cst:stx-nthrest 3 labelled-body) form  source)))))

    ;;
    ;; Macros
    ;;

    ((and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (symbolp (stx:syntax-e (stx-cst:stx-first form)))
          (macro-function (stx:syntax-e (stx-cst:stx-first form))))

     (let ((*macro-expansion-count* (+ 1 *macro-expansion-count*)))

       (when (= *macro-expansion-count* +macro-expansion-max+)
         (parse-error "Invalid macro expansion"
                      (note source form "macro expansion limit hit")))

       (source:with-context
           (:macro "Error occurs within macro context. Source locations may be imprecise")
         (parse-expression
          (if *use-hygienic-macros*
              (expand-macro-hygienic-wrapper form source)
              (expand-macro form source))
          source))))

    ;;
    ;; Function Application
    ;;

    (t
     (make-node-application
      :rator (parse-expression (stx-cst:stx-first form) source)
      :rands (loop :for rands := (stx-cst:stx-rest form) :then (stx-cst:stx-rest rands)
                   :while (stx-cst:stx-consp rands)
                   :for rand := (stx-cst:stx-first rands)
                   :collect (parse-expression rand source))
      :location (form-location source form)))))

(defun parse-expressions (forms source)
  (declare (type list forms)
           (values node &optional))
  (let ((nodes (mapcar (lambda (form) (parse-expression form source)) forms)))
    (make-node-progn
     :body (make-node-body
            :nodes (butlast nodes)
            :last-node (first (last nodes)))
     :location (source:make-location
                source
                (cons (source:span-start (stx-cst:stx-source (first forms)))
                      (source:span-end (stx-cst:stx-source (first (last forms)))))))))

(defun parse-variable (form source)
  (declare (type stx:syntax-object form)
           (values node-variable &optional))

  (unless (and (stx-cst:stx-atom-p form)
               (identifierp (stx:syntax-e form)))
    (parse-error "Invalid variable"
                 (note source form "expected identifier")))

  (when (string= "_" (symbol-name (stx:syntax-e form)))
    (parse-error "Invalid variable"
                 (note source form "invalid variable name '_'")))

  (when (char= #\. (aref (symbol-name (stx:syntax-e form)) 0))
    (parse-error "Invalid variable"
                 (note source form "variables cannot start with '.'")))

  (make-node-variable
   :name (stx:syntax-e form)
   :location (form-location source form)))

(defun parse-accessor (form source)
  (declare (type stx:syntax-object form)
           (values node-accessor))

  (assert (stx-cst:stx-atom-p form))
  (assert (symbolp (stx:syntax-e form)))
  (assert (char= #\. (aref (symbol-name (stx:syntax-e form)) 0)))

  (make-node-accessor
   :name (subseq (symbol-name (stx:syntax-e form)) 1)
   :location (form-location source form)))

(defun parse-literal (form source)
  (declare (type stx:syntax-object form)
           (values node &optional))

  (assert (stx-cst:stx-atom-p form))

  (typecase (stx:syntax-e form)
    (integer
     (make-node-integer-literal
      :value (stx:syntax-e form)
      :location (form-location source form)))

    (util:literal-value
     (make-node-literal
      :value (stx:syntax-e form)
      :location (form-location source form)))

    (t
     (parse-error "Invalid literal"
                  (note source form "unknown literal type")))))

(defun parse-body (form preceding-form source)
  (declare (type stx:syntax-object form)
           (values node-body &optional))

  (when (stx-cst:stx-atom-p form)
    (parse-error "Malformed function"
                 (note-end source preceding-form "expected body")))

  (assert (stx-cst:stx-proper-list-p form))

  (let* (last-node

         (nodes (loop :for nodes := form :then (stx-cst:stx-rest nodes)
                      :while (stx-cst:stx-consp nodes)

                      ;; Not the last node
                      :if (stx-cst:stx-consp (stx-cst:stx-rest nodes))
                        :collect (parse-body-element (stx-cst:stx-first nodes) source)

                      ;; The last node
                      :else
                        :do (setf last-node (parse-body-last-node (stx-cst:stx-first nodes) source)))))


    (make-node-body
     :nodes nodes
     :last-node last-node)))

(defun shorthand-let-p (form)
  "Returns t if FORM is in the form of (let x = y+)"
  (declare (type stx:syntax-object form)
           (values boolean))

  (cond
    ((stx-cst:stx-atom-p form)
     nil)

    ;; (let)
    ((not (stx-cst:stx-consp (stx-cst:stx-rest form)))
     nil)

    ;; (let x)
    ((not (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form))))
     nil)

    ;; (let x =)
    ((not (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest form)))))
     nil)

    (t
     (and (stx-cst:stx-atom-p (stx-cst:stx-first form))
          (eq (stx:syntax-e (stx-cst:stx-first form)) 'coalton:let)
          (stx-cst:stx-atom-p (stx-cst:stx-third form))
          (eq (stx:syntax-e (stx-cst:stx-third form)) 'coalton:=)))))

;; Forms passed to parse-node-bind must be previously verified by `shorthand-let-p'
(defun parse-node-bind (form source)
  (declare (type stx:syntax-object form)
           (values node-bind))

  (when (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest form)))))
    (parse-error "Malformed shorthand let"
                 (note source (stx-cst:stx-first (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest form)))))
                       "unexpected trailing form")))

  (make-node-bind
   :pattern (parse-pattern (stx-cst:stx-second form) source)
   :expr (parse-expression (stx-cst:stx-nth 3 form) source)
   :location (form-location source form)))

(defun parse-body-element (form source)
  (declare (type stx:syntax-object form)
           (values node-body-element &optional))

  (when (stx-cst:stx-atom-p form)
    (return-from parse-body-element
      (parse-expression form source)))

  (unless (stx-cst:stx-proper-list-p form)
    (parse-error "Malformed body expression"
                 (note source form "unexpected dotted list")))


  (if (shorthand-let-p form)
      (parse-node-bind form source)
      (parse-expression form source)))

(defun parse-body-last-node (form source)
  (declare (type stx:syntax-object form)
           (values node &optional))

  (when (shorthand-let-p form)
    (parse-error "Malformed body expression"
                 (note source form
                       "body forms cannot be terminated by a shorthand let")))

  (parse-expression form source))

(defun parse-let-binding (form source)
  (declare (type stx:syntax-object form)
           (values node-let-binding &optional))

  (when (stx-cst:stx-atom-p form)
    (parse-error "Malformed let binding"
                 (note source form "expected list")))

  (unless (stx-cst:stx-proper-list-p form)
    (parse-error "Malformed let binding"
                 (note source form "unexpected dotted list")))

  ;; (x)
  (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
    (parse-error "Malformed let binding"
                 (note-end source (stx-cst:stx-first form)
                           "let bindings must have a value")))

  ;; (a b c ...)
  (when (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
    (parse-error "Malformed let binding"
                 (note source (stx-cst:stx-first (stx-cst:stx-rest (stx-cst:stx-rest form)))
                       "unexpected trailing form")))

  (make-node-let-binding
   :name (parse-variable (stx-cst:stx-first form) source)
   :value (parse-expression (stx-cst:stx-second form) source)
   :location (form-location source form)))

(defun parse-rec-binding (form source)
  (declare (type stx:syntax-object form)
           (values node-let-binding &optional))

  (when (stx-cst:stx-atom-p form)
    (parse-error "Malformed rec binding"
                 (note source form "expected list")))

  (unless (stx-cst:stx-proper-list-p form)
    (parse-error "Malformed rec binding"
                 (note source form "unexpected dotted list")))

  ;; (x)
  (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
    (parse-error "Malformed rec binding"
                 (note-end source (stx-cst:stx-first form)
                           "rec bindings must have a value")))

  ;; (a b c ...)
  (when (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form)))
    (parse-error "Malformed rec binding"
                 (note source (stx-cst:stx-first (stx-cst:stx-rest (stx-cst:stx-rest form)))
                       "unexpected trailing form")))

  (make-node-let-binding
   :name (parse-variable (stx-cst:stx-first form) source)
   :value (parse-expression (stx-cst:stx-second form) source)
   :location (form-location source form)))

(defun parse-match-branch (form source)
  (declare (type stx:syntax-object form)
           (values node-match-branch &optional))

  (when (stx-cst:stx-atom-p form)
    (parse-error "Malformed match branch"
                 (note source form "expected list")))

  (unless (stx-cst:stx-proper-list-p form)
    (parse-error "Malformed match branch"
                 (note source form "unexpected dotted list")))

  ;; (P)
  (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
    (parse-error "Malformed match branch"
                 (note-end source (stx-cst:stx-first form) "expected body")))

  (make-node-match-branch
   :pattern (parse-pattern (stx-cst:stx-first form) source)
   :body (parse-body (stx-cst:stx-rest form) form source)
   :location (form-location source form)))

(defun parse-catch-branch (form source)
  (declare (type stx:syntax-object form)
           (values node-catch-branch &optional))

  (when (stx-cst:stx-atom-p form)
    (parse-error "Malformed catch branch"
                 (note source form "expected list")))

  (unless (stx-cst:stx-proper-list-p form)
    (parse-error "Malformed catch branch"
                 (note source form "unexpected dotted list")))

  ;; (P)
  (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
    (parse-error "Malformed catch branch"
                 (note-end source (stx-cst:stx-first form) "expected body")))

  (let ((pattern (parse-pattern (stx-cst:stx-first form) source)))
    (when (pattern-var-p pattern)
      (parse-error
       "Malformed catch branch"
       (note source (stx-cst:stx-first form)
             "Not Yet Allowed: Catching an exception with a pattern variable")))

    (unless (typep pattern '(or pattern-constructor pattern-wildcard))
      (parse-error
       "Malformed catch branch"
       (note source (stx-cst:stx-first form)
             "branch must be either an exception type constructor or a wildcard.")))

    (make-node-catch-branch
     :pattern pattern
     :body (parse-body (stx-cst:stx-rest form) form source)
     :location (form-location source form))))

(defun parse-resumable-branch (form source)
  (declare (type stx:syntax-object form)
           (values node-resumable-branch &optional))

  (when (stx-cst:stx-atom-p form)
    (parse-error "Malformed resumable branch"
                 (note source form "expected list")))

  (unless (stx-cst:stx-proper-list-p form)
    (parse-error "Malformed resumable branch"
                 (note source form "unexpected dotted list")))

  ;; (P)
  (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
    (parse-error "Malformed resumable branch"
                 (note-end source (stx-cst:stx-first form) "expected body")))

  (let ((pattern (parse-pattern (stx-cst:stx-first form) source)))
    (unless (typep pattern 'pattern-constructor)
      (parse-error "Malformed resumable branch"
                   (note
                    source
                    (stx-cst:stx-first form)
                    "pattern must match a resumption constructor.")))
    (make-node-resumable-branch
     :pattern  pattern
     :body (parse-body (stx-cst:stx-rest form) form source)
     :location (form-location source form))))

(defun parse-handle-branch (form source)
  "Parse a branch in a handle expression.

Valid forms:
- (EFFECT.OP (resume) body...) - effect handler with resumption
- (EFFECT.OP body...)          - effect handler without explicit resume
- (return (x) body...)         - return handler

Returns (VALUES branch is-return-handler-p)"
  (declare (type stx:syntax-object form)
           (values (or node-handle-branch node-body) boolean &optional))

  (when (stx-cst:stx-atom-p form)
    (parse-error "Malformed handle branch"
                 (note source form "expected list")))

  (unless (stx-cst:stx-proper-list-p form)
    (parse-error "Malformed handle branch"
                 (note source form "unexpected dotted list")))

  (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
    (parse-error "Malformed handle branch"
                 (note-end source (stx-cst:stx-first form) "expected handler body")))

  (let ((effect-part (stx-cst:stx-first form)))
    ;; Check if this is a return handler
    (when (and (stx-cst:stx-atom-p effect-part)
               (eq 'coalton:return (stx:syntax-e effect-part)))
      ;; Return handler: (return (x) body...)
      ;; The (x) part is optional - could be (return body...)
      (let ((rest (stx-cst:stx-rest form)))
        (cond
          ;; (return (x) body...) - with binding
          ((and (stx-cst:stx-consp rest)
                (stx-cst:stx-consp (stx-cst:stx-first rest))
                (stx-cst:stx-proper-list-p (stx-cst:stx-first rest))
                (= 1 (length (stx-cst:stx-listify (stx-cst:stx-first rest))))
                (stx-cst:stx-atom-p (stx-cst:stx-first (stx-cst:stx-first rest)))
                (symbolp (stx:syntax-e (stx-cst:stx-first (stx-cst:stx-first rest)))))
           ;; Has a binding variable
           ;; For now, just parse the body - type system will handle the binding
           (return-from parse-handle-branch
             (values (parse-body (stx-cst:stx-rest rest) form source) t)))
          ;; (return body...) - no binding
          (t
           (return-from parse-handle-branch
             (values (parse-body rest form source) t))))))

    ;; Effect handler: (EFFECT.OP (resume) body...) or (EFFECT.OP body...)
    (unless (and (stx-cst:stx-atom-p effect-part)
                 (symbolp (stx:syntax-e effect-part)))
      (parse-error "Malformed handle branch"
                   (note source effect-part "expected effect operation symbol")))

    (let ((effect-name (stx:syntax-e effect-part))
          (rest (stx-cst:stx-rest form))
          (resume-var nil))

      ;; Check for resumption variable: (EFFECT.OP (resume) body...)
      (when (and (stx-cst:stx-consp rest)
                 (stx-cst:stx-consp (stx-cst:stx-first rest))
                 (stx-cst:stx-proper-list-p (stx-cst:stx-first rest))
                 (= 1 (length (stx-cst:stx-listify (stx-cst:stx-first rest))))
                 (stx-cst:stx-atom-p (stx-cst:stx-first (stx-cst:stx-first rest)))
                 (symbolp (stx:syntax-e (stx-cst:stx-first (stx-cst:stx-first rest)))))
        (setf resume-var (stx:syntax-e (stx-cst:stx-first (stx-cst:stx-first rest))))
        (setf rest (stx-cst:stx-rest rest)))

      (unless (stx-cst:stx-consp rest)
        (parse-error "Malformed handle branch"
                     (note-end source effect-part "expected handler body")))

      (values
       (make-node-handle-branch
        :effect effect-name
        :resume resume-var
        :body (parse-body rest form source)
        :location (form-location source form))
       nil))))

(defun parse-cond-clause (form source)
  (declare (type stx:syntax-object form)
           (values node-cond-clause))

  (when (stx-cst:stx-atom-p form)
    (parse-error "Malformed cond clause"
                 (note source form "expected list")))

  (unless (stx-cst:stx-proper-list-p form)
    (parse-error "Malformed cond clause"
                 (note source form "unexpected dotted list")))

  (make-node-cond-clause
   :expr (parse-expression (stx-cst:stx-first form) source)
   :body (parse-body (stx-cst:stx-rest form) (stx-cst:stx-first form) source)
   :location (form-location source form)))

(defun parse-do (form source)
  (declare (type stx:syntax-object form))

  (assert (stx-cst:stx-consp form))

  (unless (stx-cst:stx-consp (stx-cst:stx-rest form))
    (parse-error "Malformed do expression"
                 (note-end source (stx-cst:stx-first form) "expected one or more forms")))

  (let* (last-node

         (nodes (loop :for nodes := (stx-cst:stx-rest form) :then (stx-cst:stx-rest nodes)
                      :while (stx-cst:stx-consp nodes)
                      :for node := (stx-cst:stx-first nodes)

                      ;; Not the last node
                      :if (stx-cst:stx-consp (stx-cst:stx-rest nodes))
                        :collect (parse-do-body-element node source)

                      :else
                        :do (setf last-node (parse-do-body-last-node node (stx-cst:stx-first form) source)))))

    (make-node-do
     :nodes nodes
     :last-node last-node
     :location (form-location source form))))

(defun do-bind-p (form)
  "Returns t if FORM is in the form of (x <- y+)"
  (declare (type stx:syntax-object form)
           (values boolean))

  (cond
    ((not (stx-cst:stx-consp form))
     nil)

    ;; (x)
    ((not (stx-cst:stx-consp (stx-cst:stx-rest form)))
     nil)

    ;; (x y)
    ((not (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form))))
     nil)

    ;; (x (y) ...)
    ((not (stx-cst:stx-atom-p (stx-cst:stx-second form)))
     nil)

    (t
     (eq 'coalton:<- (stx:syntax-e (stx-cst:stx-second form))))))

;; Forms passed to this function must first be validated with `do-bind-p'
(defun parse-node-do-bind (form source)
  (declare (type stx:syntax-object form)
           (values node-do-bind))

  (when (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest form))))
    (parse-error "Malformed bind form"
                 (note source (stx-cst:stx-first (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest form))))
                       "unexpected trailing form")))

  (make-node-do-bind
   :pattern (parse-pattern (stx-cst:stx-first form) source)
   :expr (parse-expression (stx-cst:stx-third form) source)
   :location (form-location source form)))

(defun parse-do-body-element (form source)
  (declare (type stx:syntax-object form)
           (values node-do-body-element &optional))

  (cond
    ((shorthand-let-p form)
     (parse-node-bind form source))

    ((do-bind-p form)
     (parse-node-do-bind form source))

    (t
     (parse-expression form source))))

(defun parse-do-body-last-node (form parent-form source)
  (declare (type stx:syntax-object form)
           (type stx:syntax-object parent-form)
           (values node &optional))

  (when (shorthand-let-p form)
    (parse-error "Malformed do expression"
                 (note source form
                       "do expressions cannot be terminated by a shorthand let")
                 (secondary-note source parent-form "when parsing do expression")))

  (when (do-bind-p form)
    (parse-error "Malformed do expression"
                 (note source form
                       "do expression cannot be terminated by a bind")
                 (secondary-note source parent-form "when parsing do expression")))

  (parse-expression form source))

(defun parse-let-declare (form source)
  (declare (type stx:syntax-object form)
           (values node-let-declare))

  (assert (stx-cst:stx-consp form))
  (assert (stx-cst:stx-consp (stx-cst:stx-rest form)))
  (assert (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest form))))

  (assert (stx-cst:stx-atom-p (stx-cst:stx-first form)))
  (assert (eq (stx:syntax-e (stx-cst:stx-first form)) 'coalton:declare))

  (when (stx-cst:stx-consp (stx-cst:stx-rest (stx-cst:stx-rest (stx-cst:stx-rest form))))
    (parse-error "Malformed declare"
                 (note source (stx-cst:stx-nth 3 form) "unexpected form")))

  (make-node-let-declare
   :name (parse-variable (stx-cst:stx-second form) source)
   :type (parse-qualified-type (stx-cst:stx-third form) source)
   :location (form-location source form)))

(defun take-label (form)
  "Takes form (HEAD . (MAYBEKEYWORD . REST)) and returns three values,
either

MAYBEKEYWORD REST MAYBECST

if MAYBEKEYWORD is a keyword, or else

NIL (MAYBEKEYWORD . REST) NIL

if (STX-CST:STX-SECOND FORM) is not a keyword."
  (declare (type stx:syntax-object form)
           (values (or keyword null) stx:syntax-object))
  (if (and (stx-cst:stx-consp (stx-cst:stx-rest form))
           (stx-cst:stx-atom-p (stx-cst:stx-second form))
           (keywordp (stx:syntax-e (stx-cst:stx-second form))))
      (values (stx:syntax-e (stx-cst:stx-second form))
              (stx-cst:stx-nthrest 2 form)
              (stx-cst:stx-second form))
      (values nil (stx-cst:stx-rest form) nil)))
