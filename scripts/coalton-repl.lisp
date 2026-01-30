;;;; coalton-repl.lisp - Interactive Coalton REPL with type display
;;;;
;;;; Usage: ./scripts/coalton-repl
;;;;    or: sbcl --noinform --load scripts/coalton-repl.lisp
;;;;
;;;; Features:
;;;;   - Shows both type and value of evaluated expressions
;;;;   - Command history with up/down arrow keys (requires cl-readline)

(require :asdf)

;; Suppress output during loading
(let ((*standard-output* (make-broadcast-stream))
      (*error-output* (make-broadcast-stream)))
  (handler-bind ((warning #'muffle-warning))
    (asdf:load-system :coalton :verbose nil)))

;; Try to load cl-readline for history support
(defvar *use-readline* nil)
(ignore-errors
  (let ((*standard-output* (make-broadcast-stream))
        (*error-output* (make-broadcast-stream)))
    (handler-bind ((warning #'muffle-warning))
      ;; Try ASDF first
      (or (ignore-errors (asdf:load-system :cl-readline :verbose nil))
          ;; Try Quicklisp if available
          (when (find-package "QL")
            (funcall (find-symbol "QUICKLOAD" "QL") :cl-readline :silent t)))))
  (setf *use-readline* (not (null (find-package "RL")))))

(defpackage #:coalton-repl
  (:use #:cl)
  (:local-nicknames
   (#:source #:coalton-impl/source)
   (#:parser #:coalton-impl/parser)
   (#:tc #:coalton-impl/typechecker)
   (#:codegen #:coalton-impl/codegen)
   (#:entry #:coalton-impl/entry)
   (#:settings #:coalton-impl/settings)))

(in-package #:coalton-repl)

;;;
;;; Readline support (dynamically accessed to avoid read-time errors)
;;;

(defvar *use-readline* cl-user::*use-readline*)
(defvar *history-file*
  (merge-pathnames ".coalton_history" (user-homedir-pathname)))

(defun rl-symbol (name)
  "Get a symbol from the RL package by name, or NIL if not found."
  (let ((pkg (find-package "RL")))
    (when pkg
      (let ((sym (find-symbol (string name) pkg)))
        (when (and sym (fboundp sym))
          sym)))))

(defun init-readline ()
  "Initialize readline with history."
  (when *use-readline*
    ;; Load history from file if it exists
    (when (probe-file *history-file*)
      (ignore-errors
        (let ((read-history (rl-symbol "READ-HISTORY")))
          (when read-history
            (funcall read-history (namestring *history-file*))))))))

(defun save-readline-history ()
  "Save readline history to file."
  (when *use-readline*
    (ignore-errors
      (let ((write-history (rl-symbol "WRITE-HISTORY")))
        (when write-history
          (funcall write-history (namestring *history-file*)))))))

(defun read-input-readline ()
  "Read a line using readline with history support."
  (let* ((readline-fn (rl-symbol "READLINE"))
         (add-history-fn (rl-symbol "ADD-HISTORY"))
         (line (when readline-fn
                 (funcall readline-fn :prompt "coalton> "))))
    (when (and line
               (plusp (length (string-trim '(#\Space #\Tab) line)))
               add-history-fn)
      (funcall add-history-fn line))
    line))

(defun read-input-basic ()
  "Read a line using basic input (no history)."
  (format t "coalton> ")
  (finish-output)
  (read-line *standard-input* nil nil))

(defun read-input ()
  "Read a line of input, returning NIL on EOF."
  (if *use-readline*
      (read-input-readline)
      (read-input-basic)))

;;;
;;; Type-capturing evaluation
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
;;; Tutorial display
;;;

(defun print-tutorial ()
  "Print a short tutorial with example expressions."
  (format t "~%")
  (format t "+--------------------------------------------------+~%")
  (format t "|              Welcome to the Coalton REPL         |~%")
  (format t "+--------------------------------------------------+~%")
  (format t "|                                                  |~%")
  (format t "|  Try these examples:                             |~%")
  (format t "|                                                  |~%")
  (format t "|    42                    ; Integer literal       |~%")
  (format t "|    (+ 1 2)               ; Arithmetic            |~%")
  (format t "|    (fn (x) (+ x 1))      ; Lambda                |~%")
  (format t "|    (map (+ 1) (make-list 1 2 3))                 |~%")
  (format t "|    id                    ; Polymorphic function  |~%")
  (format t "|    True                  ; Boolean               |~%")
  (format t "|    (if True 1 2)         ; Conditional           |~%")
  (format t "|                                                  |~%")
  (format t "|  Commands:                                       |~%")
  (format t "|    :help                 ; Show this message     |~%")
  (format t "|    :quit or :exit        ; Exit the REPL         |~%")
  (format t "|    Ctrl+D                ; Exit the REPL         |~%")
  (if *use-readline*
      (progn
        (format t "|                                                  |~%")
        (format t "|  History: Up/Down arrows to navigate history     |~%"))
      (progn
        (format t "|                                                  |~%")
        (format t "|  Note: Install cl-readline for history support   |~%")))
  (format t "|                                                  |~%")
  (format t "+--------------------------------------------------+~%")
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
;;; REPL loop
;;;

(defun repl-loop ()
  "Main REPL loop."
  (init-readline)
  (print-tutorial)
  (unwind-protect
       (loop
         (let ((input (read-input)))
           (cond
             ;; EOF (Ctrl+D)
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

             ;; Evaluate expression
             (t
              (handler-case
                  (multiple-value-bind (result type-string)
                      (eval-coalton-expression input)
                    (format t "  Type:  ~A~%" type-string)
                    (format t "  Value: ~S~%" result)
                    (format t "~%"))
                (source:source-error (e)
                  (format t "~A~%~%" e))
                (error (e)
                  (format t "Error: ~A~%~%" e)))))))
    ;; Cleanup: save history
    (save-readline-history)))

;; Run the REPL
(repl-loop)
(sb-ext:exit :code 0)
