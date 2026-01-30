;;;; coalton-repl.lisp - Interactive Coalton REPL with type display
;;;;
;;;; Usage: ./scripts/coalton-repl
;;;;    or: sbcl --noinform --load scripts/coalton-repl.lisp
;;;;
;;;; Features:
;;;;   - Shows both type and value of evaluated expressions
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
  (format t "|    (let ((f (fn (x) (* x 2)))) (f 21))           |~%")
  (format t "|                          ; Named function        |~%")
  (format t "|    (map (+ 1) (make-list 1 2 3))                 |~%")
  (format t "|    id                    ; Polymorphic function  |~%")
  (format t "|    True                  ; Boolean               |~%")
  (format t "|    (if True 1 2)         ; Conditional           |~%")
  (format t "|                                                  |~%")
  (format t "|  Editing:                                        |~%")
  (format t "|    Up/Down     Navigate history                  |~%")
  (format t "|    Left/Right  Move cursor                       |~%")
  (format t "|    Ctrl+A/E    Start/End of line                 |~%")
  (format t "|    Ctrl+U/K    Clear before/after cursor         |~%")
  (format t "|    Ctrl+W      Delete word                       |~%")
  (format t "|    Ctrl+L      Clear screen                      |~%")
  (format t "|                                                  |~%")
  (format t "|  Commands:                                       |~%")
  (format t "|    :help                 Show this message       |~%")
  (format t "|    :quit or :exit        Exit the REPL           |~%")
  (format t "|    Ctrl+D                Exit the REPL           |~%")
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

             ;; Evaluate expression
             (t
              ;; Add to history
              (linedit:history-add *history* input)
              (handler-case
                  (multiple-value-bind (result type-string)
                      (eval-coalton-expression input)
                    ;; Ensure we start at column 0 (carriage return)
                    (format t "~C  Type:  ~A~%" #\Return type-string)
                    (format t "  Value: ~S~%" result)
                    (format t "~%"))
                (source:source-error (e)
                  (format t "~C~A~%~%" #\Return e))
                (error (e)
                  (format t "~CError: ~A~%~%" #\Return e)))))))
    ;; Cleanup: save history
    (save-history)))

;; Run the REPL
(repl-loop)
(sb-ext:exit :code 0)
