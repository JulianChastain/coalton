;;;; coalton-repl.lisp - Interactive Coalton REPL with type display
;;;;
;;;; Usage: ./scripts/coalton-repl
;;;;    or: sbcl --noinform --load scripts/coalton-repl.lisp
;;;;
;;;; Features:
;;;;   - Shows both type and value of evaluated expressions
;;;;   - Supports all Coalton toplevel forms (define, define-type, etc.)
;;;;   - Command history with up/down arrow keys
;;;;   - Line editing (cursor movement, backspace, delete, etc.)
;;;;   - Persistent history saved to ~/.coalton_history

(require :asdf)

;; Suppress output during loading
(let ((*standard-output* (make-broadcast-stream))
      (*error-output* (make-broadcast-stream)))
  (handler-bind ((warning #'muffle-warning))
    (asdf:load-system :coalton :verbose nil)))

;; Load our pure-Lisp line editor
;; The script is in PROJECT/scripts/, linedit is in PROJECT/src/
(load (merge-pathnames "../src/linedit.lisp" *load-truename*))

(defpackage #:coalton-repl
  (:use #:cl)
  (:local-nicknames
   (#:source #:coalton-impl/source)
   (#:parser #:coalton-impl/parser)
   (#:tc #:coalton-impl/typechecker)
   (#:codegen #:coalton-impl/codegen)
   (#:entry #:coalton-impl/entry)
   (#:settings #:coalton-impl/settings)
   (#:linedit #:coalton-impl/linedit)))

(in-package #:coalton-repl)

;;;
;;; History Management
;;;

(defvar *history* (linedit:make-history))
(defvar *history-file*
  (merge-pathnames ".coalton_history" (user-homedir-pathname)))

(defun init-history ()
  "Load history from file."
  (linedit:history-load *history* *history-file*))

(defun save-history ()
  "Save history to file."
  (ignore-errors
    (linedit:history-save *history* *history-file*)))

;;;
;;; Toplevel form detection
;;;

(defvar *toplevel-operators*
  '(coalton:define
    coalton:declare
    coalton:define-type
    coalton:define-struct
    coalton:define-class
    coalton:define-instance
    coalton:define-type-alias
    coalton:specialize
    coalton:monomorphize
    coalton:inline
    coalton:repr
    coalton:progn)
  "List of Coalton toplevel form operators.")

(defun toplevel-form-p (input-string)
  "Check if INPUT-STRING appears to be a toplevel form.
   Returns the operator symbol if it is, NIL otherwise."
  (let* ((*package* (find-package "COALTON-USER"))
         (*read-eval* nil))
    (ignore-errors
      (with-input-from-string (s input-string)
        (let ((form (read s nil nil)))
          (when (and (consp form)
                     (symbolp (car form)))
            (let ((op (car form)))
              ;; Check against known toplevel operators
              (find op *toplevel-operators* :test #'eq))))))))

;;;
;;; Toplevel form evaluation
;;;

(defun get-defined-names (program)
  "Extract names defined in PROGRAM for reporting."
  (let ((names '()))
    ;; Collect define names
    (dolist (def (parser:program-defines program))
      (push (cons :define (parser:node-variable-name
                           (parser:toplevel-define-name def)))
            names))
    ;; Collect type names
    (dolist (def (parser:program-types program))
      (push (cons :type (parser:identifier-src-name
                         (parser:toplevel-define-type-name def)))
            names))
    ;; Collect struct names
    (dolist (def (parser:program-structs program))
      (push (cons :struct (parser:identifier-src-name
                           (parser:toplevel-define-struct-name def)))
            names))
    ;; Collect class names
    (dolist (def (parser:program-classes program))
      (push (cons :class (parser:identifier-src-name
                          (parser:toplevel-define-class-name def)))
            names))
    ;; Collect instance info (use the predicate for display)
    (dolist (def (parser:program-instances program))
      (let ((pred (parser:toplevel-define-instance-pred def)))
        (push (cons :instance (format nil "~A" pred)) names)))
    ;; Collect type alias names
    (dolist (def (parser:program-type-aliases program))
      (push (cons :alias (parser:identifier-src-name
                          (parser:toplevel-define-type-alias-name def)))
            names))
    (nreverse names)))

(defun format-type-for-name (name env)
  "Get the type string for NAME from ENV."
  (let ((scheme (tc:lookup-value-type env name :no-error t)))
    (when scheme
      (tc:with-pprint-variable-context ()
        (with-output-to-string (s)
          (write scheme :stream s))))))

(defun eval-coalton-toplevel (input-string)
  "Parse and evaluate a Coalton toplevel form.
   Returns a list of (kind name &optional type-string) for each definition."
  (let* ((*package* (find-package "COALTON-USER"))
         (source (source:make-source-string input-string :name "repl"))
         (results '()))
    (with-open-stream (stream (source:source-stream source))
      (parser:with-reader-context stream
        ;; Create an empty program
        (let ((program (parser:make-program))
              (attributes (make-array 8 :adjustable t :fill-pointer 0)))
          ;; Read and parse the form
          (multiple-value-bind (form presentp)
              (parser:maybe-read-form stream source parser:*coalton-eclector-client*)
            (unless presentp
              (error "No form to evaluate"))
            ;; Parse as toplevel form
            (parser:parse-toplevel-form form program attributes source)
            ;; Check for unparsed attributes
            (when (plusp (length attributes))
              (error "Trailing attributes without definition"))
            ;; Reverse the lists since parse-toplevel-form pushes
            (setf (parser:program-defines program) (nreverse (parser:program-defines program)))
            (setf (parser:program-types program) (nreverse (parser:program-types program)))
            (setf (parser:program-structs program) (nreverse (parser:program-structs program)))
            (setf (parser:program-classes program) (nreverse (parser:program-classes program)))
            (setf (parser:program-instances program) (nreverse (parser:program-instances program)))
            (setf (parser:program-type-aliases program) (nreverse (parser:program-type-aliases program)))
            (setf (parser:program-declares program) (nreverse (parser:program-declares program)))
            (setf (parser:program-specializations program) (nreverse (parser:program-specializations program)))
            ;; Get names before compilation
            (let ((defined-names (get-defined-names program)))
              ;; Compile and evaluate
              (multiple-value-bind (compiled-code new-env)
                  (entry:entry-point program)
                ;; Update global environment
                (setf entry:*global-environment* new-env)
                ;; Evaluate the compiled code
                (eval compiled-code)
                ;; Build results with types
                (dolist (def defined-names)
                  (let* ((kind (car def))
                         (name (cdr def))
                         (type-str (when (and (symbolp name)
                                              (member kind '(:define)))
                                     (format-type-for-name name new-env))))
                    (push (list kind name type-str) results)))))))))
    (nreverse results)))

;;;
;;; AST Formatting
;;;

(defvar *last-parsed-ast* nil
  "Stores the most recently parsed AST for display purposes.")

(defgeneric format-ast (node)
  (:documentation "Convert a parser AST node to a readable S-expression form."))

(defgeneric format-pattern (pattern)
  (:documentation "Convert a parser pattern to a readable form."))

;; Default fallback
(defmethod format-ast (node)
  `(:unknown ,(type-of node)))

(defmethod format-pattern (pattern)
  `(:unknown-pattern ,(type-of pattern)))

;; Variables
(defmethod format-ast ((node parser:node-variable))
  (parser:node-variable-name node))

;; Literals
(defmethod format-ast ((node parser:node-integer-literal))
  (parser:node-integer-literal-value node))

(defmethod format-ast ((node parser:node-literal))
  (parser:node-literal-value node))

;; Application
(defmethod format-ast ((node parser:node-application))
  `(,(format-ast (parser:node-application-rator node))
    ,@(mapcar #'format-ast (parser:node-application-rands node))))

;; Helper for body formatting
(defun format-body (body)
  "Format a node-body, returning a list of body forms."
  (let ((bindings (parser:node-body-nodes body))
        (last-node (parser:node-body-last-node body)))
    (if (null bindings)
        (list (format-ast last-node))
        (append (mapcar (lambda (elem)
                          (cond
                            ((typep elem 'parser:node-bind)
                             `(:let ,(format-pattern (parser:node-bind-pattern elem))
                                    := ,(format-ast (parser:node-bind-expr elem))))
                            (t (format-ast elem))))
                        bindings)
                (list (format-ast last-node))))))

;; Abstraction (lambda)
(defmethod format-ast ((node parser:node-abstraction))
  `(:fn ,(mapcar #'format-pattern (parser:node-abstraction-params node))
        ,@(format-body (parser:node-abstraction-body node))))

;; Let binding
(defmethod format-ast ((node parser:node-let))
  `(:let ,(mapcar (lambda (binding)
                    `(,(format-ast (parser:node-let-binding-name binding))
                      ,(format-ast (parser:node-let-binding-value binding))))
                  (parser:node-let-bindings node))
         ,@(format-body (parser:node-let-body node))))

;; Lisp form
(defmethod format-ast ((node parser:node-lisp))
  `(:lisp ,(parser:node-lisp-type node)
          ,(parser:node-lisp-vars node)
          :body-omitted))

;; Match
(defmethod format-ast ((node parser:node-match))
  `(:match ,(format-ast (parser:node-match-expr node))
           ,@(mapcar (lambda (branch)
                       `(,(format-pattern (parser:node-match-branch-pattern branch))
                         ,@(format-body (parser:node-match-branch-body branch))))
                     (parser:node-match-branches node))))

;; Progn
(defmethod format-ast ((node parser:node-progn))
  `(:progn ,@(format-body (parser:node-progn-body node))))

;; If
(defmethod format-ast ((node parser:node-if))
  `(:if ,(format-ast (parser:node-if-expr node))
        ,(format-ast (parser:node-if-then node))
        ,(format-ast (parser:node-if-else node))))

;; If/cond
(defmethod format-ast ((node parser:node-cond))
  `(:cond ,@(mapcar (lambda (clause)
                      `(,(format-ast (parser:node-cond-clause-expr clause))
                        ,(format-ast (parser:node-cond-clause-body clause))))
                    (parser:node-cond-clauses node))))

;; Do block
(defmethod format-ast ((node parser:node-do))
  `(:do ,@(mapcar (lambda (elem)
                    (cond
                      ((typep elem 'parser:node-do-bind)
                       `(:<- ,(format-pattern (parser:node-do-bind-pattern elem))
                             ,(format-ast (parser:node-do-bind-expr elem))))
                      ((typep elem 'parser:node-bind)
                       `(:let ,(format-pattern (parser:node-bind-pattern elem))
                              := ,(format-ast (parser:node-bind-expr elem))))
                      (t (format-ast elem))))
                  (parser:node-do-nodes node))
         ,(format-ast (parser:node-do-last-node node))))

;; The expression
(defmethod format-ast ((node parser:node-the))
  `(:the ,(parser:node-the-type node)
         ,(format-ast (parser:node-the-expr node))))

;; Return
(defmethod format-ast ((node parser:node-return))
  `(:return ,(format-ast (parser:node-return-expr node))))

;; Pattern formatting
(defmethod format-pattern ((pattern parser:pattern-var))
  (parser:pattern-var-name pattern))

(defmethod format-pattern ((pattern parser:pattern-wildcard))
  '_)

(defmethod format-pattern ((pattern parser:pattern-literal))
  (parser:pattern-literal-value pattern))

(defmethod format-pattern ((pattern parser:pattern-constructor))
  (let ((name (parser:pattern-constructor-name pattern))
        (patterns (parser:pattern-constructor-patterns pattern)))
    (if (null patterns)
        name
        `(,name ,@(mapcar #'format-pattern patterns)))))

(defun ast-to-string (node)
  "Convert an AST node to a readable string representation."
  (handler-case
      (let ((*print-pretty* t)
            (*print-right-margin* 60)
            (*package* (find-package "COALTON-USER")))
        (format nil "~S" (format-ast node)))
    (error (e)
      (format nil "#<AST format error: ~A>" e))))

;;;
;;; Expression evaluation
;;;

(defun eval-coalton-expression (input-string)
  "Parse and evaluate a Coalton expression, returning (values result type-string).
   Signals an error if parsing or type checking fails."
  (let* ((*package* (find-package "COALTON-USER"))
         (source (source:make-source-string input-string :name "repl"))
         (env entry:*global-environment*))
    (with-open-stream (stream (source:source-stream source))
      (parser:with-reader-context stream
        (let ((node (parser:read-expressions stream source)))
          ;; Capture AST before renaming for display
          (setf *last-parsed-ast* node)
          ;; Rename variables for hygiene
          (setf node (parser:rename-variables node))

          ;; Infer type
          (multiple-value-bind (ty preds accessors node subs)
              (tc:infer-expression-type node
                                        (tc:make-variable)
                                        nil
                                        (tc:make-tc-env :env env))
            ;; Solve fundeps
            (multiple-value-bind (preds subs)
                (tc:solve-fundeps env preds subs)

              (setf accessors (tc:apply-substitution subs accessors))

              ;; Solve accessors
              (multiple-value-bind (accessors subs_)
                  (tc:solve-accessors accessors env)
                (setf subs (tc:compose-substitution-lists subs subs_))

                (when accessors
                  (error "Ambiguous accessor"))

                ;; Reduce context and apply defaults
                (let* ((preds (tc:reduce-context env preds subs))
                       (subs (tc:compose-substitution-lists
                              (tc:default-subs env nil preds)
                              subs))
                       (preds (tc:reduce-context env preds subs))
                       (node (tc:apply-substitution subs node))
                       (ty (tc:apply-substitution subs ty))
                       (qual-ty (tc:qualify preds ty))
                       (scheme (tc:quantify (tc:type-variables qual-ty) qual-ty)))

                  ;; Format the type as a string
                  ;; The print-object method for ty-scheme uses pprint-scheme internally
                  (let ((type-string
                          (tc:with-pprint-variable-context ()
                            (with-output-to-string (s)
                              (write scheme :stream s)))))

                    ;; Check for unresolved predicates
                    (when preds
                      (error "Unable to resolve type class constraints: ~S" preds))

                    ;; Generate and evaluate the code
                    (let* ((translated (codegen:translate-expression node nil env))
                           (optimized (codegen:optimize-node translated env))
                           (with-direct-app (codegen:direct-application
                                             optimized
                                             (codegen:make-function-table env)))
                           (code (codegen:codegen-expression with-direct-app env))
                           (result (eval code)))
                      (values result type-string))))))))))))

;;;
;;; Unified evaluation
;;;

(defun eval-coalton-input (input-string)
  "Evaluate INPUT-STRING as either a toplevel form or an expression.
   Returns (values result-type result-data) where:
   - For expressions: result-type is :expression, result-data is (value type-string ast-string)
   - For toplevel: result-type is :toplevel, result-data is list of (kind name type-string)"
  (if (toplevel-form-p input-string)
      (values :toplevel (eval-coalton-toplevel input-string))
      (progn
        (setf *last-parsed-ast* nil)
        (multiple-value-bind (value type-string)
            (eval-coalton-expression input-string)
          (let ((ast-string (if *last-parsed-ast*
                                (ast-to-string *last-parsed-ast*)
                                "<no AST>")))
            (values :expression (list value type-string ast-string)))))))

;;;
;;; Tutorial display
;;;

(defun print-tutorial ()
  "Print a short tutorial with example expressions."
  (format t "~%")
  (format t "+----------------------------------------------------------+~%")
  (format t "|                  Welcome to the Coalton REPL             |~%")
  (format t "+----------------------------------------------------------+~%")
  (format t "|                                                          |~%")
  (format t "|  Expressions:                                            |~%")
  (format t "|    42                        ; Integer literal           |~%")
  (format t "|    (+ 1 2)                   ; Arithmetic                |~%")
  (format t "|    (fn (x) (+ x 1))          ; Lambda                    |~%")
  (format t "|    (map (+ 1) (make-list 1 2 3))                         |~%")
  (format t "|                                                          |~%")
  (format t "|  Definitions:                                            |~%")
  (format t "|    (define (double x) (* x 2))                           |~%")
  (format t "|    (define-type (Maybe :a) None (Some :a))               |~%")
  (format t "|    (declare triple (Integer -> Integer))                 |~%")
  (format t "|    (define (triple x) (* x 3))                           |~%")
  (format t "|                                                          |~%")
  (format t "|  Editing:                                                |~%")
  (format t "|    Up/Down       Navigate history                        |~%")
  (format t "|    Left/Right    Move cursor                             |~%")
  (format t "|    Ctrl+A/E      Start/End of line                       |~%")
  (format t "|    Ctrl+U/K      Clear before/after cursor               |~%")
  (format t "|                                                          |~%")
  (format t "|  Commands:                                               |~%")
  (format t "|    :help         Show this message                       |~%")
  (format t "|    :quit         Exit the REPL                           |~%")
  (format t "|                                                          |~%")
  (format t "+----------------------------------------------------------+~%")
  (format t "~%"))

;;;
;;; Command handling
;;;

(defun exit-command-p (input)
  "Check if INPUT is an exit command."
  (let ((trimmed (string-trim '(#\Space #\Tab) input)))
    (or (string-equal trimmed ":quit")
        (string-equal trimmed ":exit")
        (string-equal trimmed ":q"))))

(defun help-command-p (input)
  "Check if INPUT is a help command."
  (let ((trimmed (string-trim '(#\Space #\Tab) input)))
    (or (string-equal trimmed ":help")
        (string-equal trimmed ":h")
        (string-equal trimmed ":?"))))

;;;
;;; Result formatting
;;;

(defun format-toplevel-result (results)
  "Format the results of a toplevel evaluation."
  (dolist (result results)
    (let ((kind (first result))
          (name (second result))
          (type-str (third result)))
      (case kind
        (:define
         (if type-str
             (format t "~C  ~A :: ~A~%" #\Return name type-str)
             (format t "~C  Defined: ~A~%" #\Return name)))
        (:type
         (format t "~C  Type defined: ~A~%" #\Return name))
        (:struct
         (format t "~C  Struct defined: ~A~%" #\Return name))
        (:class
         (format t "~C  Class defined: ~A~%" #\Return name))
        (:instance
         (format t "~C  Instance defined: ~A~%" #\Return name))
        (:alias
         (format t "~C  Type alias defined: ~A~%" #\Return name))
        (t
         (format t "~C  Defined: ~A~%" #\Return name)))))
  (format t "~%"))

(defun format-expression-result (result-data)
  "Format the result of an expression evaluation."
  (let ((value (first result-data))
        (type-string (second result-data))
        (ast-string (third result-data)))
    (format t "~C  AST:   ~A~%" #\Return ast-string)
    (format t "  Type:  ~A~%" type-string)
    (format t "  Value: ~S~%" value)
    (format t "~%")))

;;;
;;; REPL loop
;;;

(defun read-input ()
  "Read a line of input with editing support."
  (linedit:linedit :prompt "coalton> " :history *history*))

(defun repl-loop ()
  "Main REPL loop."
  (init-history)
  (print-tutorial)
  (unwind-protect
       (loop
         (let ((input (read-input)))
           (cond
             ;; EOF (Ctrl+D) or interrupt
             ((null input)
              (format t "~%Goodbye!~%")
              (return))

             ;; Empty line
             ((string= (string-trim '(#\Space #\Tab) input) "")
              nil)

             ;; Exit commands
             ((exit-command-p input)
              (format t "Goodbye!~%")
              (return))

             ;; Help command
             ((help-command-p input)
              (print-tutorial))

             ;; Evaluate Coalton input
             (t
              ;; Add to history
              (linedit:history-add *history* input)
              (handler-case
                  (multiple-value-bind (result-type result-data)
                      (eval-coalton-input input)
                    (case result-type
                      (:toplevel (format-toplevel-result result-data))
                      (:expression (format-expression-result result-data))))
                (source:source-error (e)
                  (format t "~C~A~%~%" #\Return e))
                (error (e)
                  (format t "~CError: ~A~%~%" #\Return e)))))))
    ;; Cleanup: save history
    (save-history)))

;; Run the REPL
(repl-loop)
(sb-ext:exit :code 0)
