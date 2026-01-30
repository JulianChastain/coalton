;;;; coalton-repl.lisp - Interactive Coalton REPL with type display
;;;;
;;;; Usage: ./scripts/coalton-repl
;;;;    or: sbcl --noinform --load scripts/coalton-repl.lisp

(require :asdf)

;; Suppress output during loading
(let ((*standard-output* (make-broadcast-stream))
      (*error-output* (make-broadcast-stream)))
  (handler-bind ((warning #'muffle-warning))
    (asdf:load-system :coalton :verbose nil)))

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
  (format t "|    :quit                 ; Exit the REPL         |~%")
  (format t "|                                                  |~%")
  (format t "+--------------------------------------------------+~%")
  (format t "~%"))

;;;
;;; REPL loop
;;;

(defun read-input ()
  "Read a line of input, returning NIL on EOF."
  (format t "coalton> ")
  (finish-output)
  (read-line *standard-input* nil nil))

(defun repl-loop ()
  "Main REPL loop."
  (print-tutorial)
  (loop
    (let ((input (read-input)))
      (cond
        ;; EOF
        ((null input)
         (format t "~%Goodbye!~%")
         (return))

        ;; Empty line
        ((string= (string-trim '(#\Space #\Tab) input) "")
         nil)

        ;; :quit command
        ((string-equal (string-trim '(#\Space #\Tab) input) ":quit")
         (format t "Goodbye!~%")
         (return))

        ;; :help command
        ((string-equal (string-trim '(#\Space #\Tab) input) ":help")
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
             (format t "Error: ~A~%~%" e))))))))

;; Run the REPL
(repl-loop)
(sb-ext:exit :code 0)
