(in-package #:jynx-lisply)

;;;
;;; Coalton toplevel form detection
;;;

(defvar *coalton-toplevel-operators*
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

(defun coalton-toplevel-form-p (input-string)
  "Check if INPUT-STRING appears to be a Coalton toplevel form.
   Returns the operator symbol if it is, NIL otherwise."
  (let* ((*package* (find-package "COALTON-USER"))
         (*read-eval* nil))
    (ignore-errors
      (with-input-from-string (s input-string)
        (let ((form (read s nil nil)))
          (when (and (consp form)
                     (symbolp (car form)))
            (find (car form) *coalton-toplevel-operators* :test #'eq)))))))

;;;
;;; Coalton toplevel evaluation
;;;

(defun eval-coalton-toplevel (input-string)
  "Parse and evaluate a Coalton toplevel form.
   Returns a string describing what was defined."
  (let* ((*package* (find-package "COALTON-USER"))
         (source (source:make-source-string input-string :name "lisply")))
    (with-open-stream (stream (source:source-stream source))
      (parser:with-reader-context stream
        (let ((program (parser:make-program))
              (attributes (make-array 8 :adjustable t :fill-pointer 0)))
          (multiple-value-bind (form presentp)
              (parser:maybe-read-form stream source parser:*coalton-eclector-client*)
            (unless presentp
              (error "No form to evaluate"))
            (parser:parse-toplevel-form (stx-cst:cst->syntax form source) program attributes source)
            (when (plusp (length attributes))
              (error "Trailing attributes without definition"))
            ;; Reverse lists since parse-toplevel-form pushes
            (setf (parser:program-defines program) (nreverse (parser:program-defines program)))
            (setf (parser:program-types program) (nreverse (parser:program-types program)))
            (setf (parser:program-structs program) (nreverse (parser:program-structs program)))
            (setf (parser:program-classes program) (nreverse (parser:program-classes program)))
            (setf (parser:program-instances program) (nreverse (parser:program-instances program)))
            (setf (parser:program-type-aliases program) (nreverse (parser:program-type-aliases program)))
            (setf (parser:program-declares program) (nreverse (parser:program-declares program)))
            (setf (parser:program-specializations program) (nreverse (parser:program-specializations program)))
            ;; Compile and evaluate
            (multiple-value-bind (compiled-code new-env)
                (entry:entry-point program)
              (setf entry:*global-environment* new-env)
              (eval compiled-code)
              ;; Build result description
              (with-output-to-string (out)
                (let ((first t))
                  (dolist (def (parser:program-defines program))
                    (let* ((name (parser:node-variable-name
                                  (parser:toplevel-define-name def)))
                           (type-str (let ((scheme (tc:lookup-value-type new-env name :no-error t)))
                                       (when scheme
                                         (tc:with-pprint-variable-context ()
                                           (with-output-to-string (s)
                                             (write scheme :stream s)))))))
                      (unless first (write-string "; " out))
                      (if type-str
                          (format out "~A :: ~A" name type-str)
                          (format out "Defined: ~A" name))
                      (setf first nil)))
                  (dolist (def (parser:program-types program))
                    (unless first (write-string "; " out))
                    (format out "Type defined: ~A"
                            (parser:identifier-src-name
                             (parser:toplevel-define-type-name def)))
                    (setf first nil))
                  (dolist (def (parser:program-structs program))
                    (unless first (write-string "; " out))
                    (format out "Struct defined: ~A"
                            (parser:identifier-src-name
                             (parser:toplevel-define-struct-name def)))
                    (setf first nil))
                  (dolist (def (parser:program-classes program))
                    (unless first (write-string "; " out))
                    (format out "Class defined: ~A"
                            (parser:identifier-src-name
                             (parser:toplevel-define-class-name def)))
                    (setf first nil))
                  (dolist (def (parser:program-instances program))
                    (unless first (write-string "; " out))
                    (format out "Instance defined: ~A"
                            (parser:toplevel-define-instance-pred def))
                    (setf first nil))
                  (dolist (def (parser:program-type-aliases program))
                    (unless first (write-string "; " out))
                    (format out "Type alias defined: ~A"
                            (parser:identifier-src-name
                             (parser:toplevel-define-type-alias-name def)))
                    (setf first nil)))))))))))

;;;
;;; Coalton expression evaluation
;;;

(defun eval-coalton-expression (input-string)
  "Parse and evaluate a Coalton expression.
   Returns (values result-string type-string)."
  (let* ((*package* (find-package "COALTON-USER"))
         (source (source:make-source-string input-string :name "lisply"))
         (env entry:*global-environment*))
    (with-open-stream (stream (source:source-stream source))
      (parser:with-reader-context stream
        (let ((node (parser:read-expressions stream source)))
          (setf node (parser:rename-variables node))
          (multiple-value-bind (ty preds accessors node subs)
              (tc:infer-expression-type node
                                        (tc:make-variable)
                                        nil
                                        (tc:make-tc-env :env env))
            (multiple-value-bind (preds subs)
                (tc:solve-fundeps env preds subs)
              (setf accessors (tc:apply-substitution subs accessors))
              (multiple-value-bind (accessors subs_)
                  (tc:solve-accessors accessors env)
                (setf subs (tc:compose-substitution-lists subs subs_))
                (when accessors
                  (error "Ambiguous accessor"))
                (let* ((preds (tc:reduce-context env preds subs))
                       (subs (tc:compose-substitution-lists
                              (tc:default-subs env nil preds)
                              subs))
                       (preds (tc:reduce-context env preds subs))
                       (node (tc:apply-substitution subs node))
                       (ty (tc:apply-substitution subs ty))
                       (qual-ty (tc:qualify preds ty))
                       (scheme (tc:quantify (tc:type-variables qual-ty) qual-ty)))
                  (let ((type-string
                          (tc:with-pprint-variable-context ()
                            (with-output-to-string (s)
                              (write scheme :stream s)))))
                    (when preds
                      (error "Unable to resolve type class constraints: ~S" preds))
                    (let* ((translated (codegen:translate-expression node nil env))
                           (optimized (codegen:optimize-node translated env))
                           (with-direct-app (codegen:direct-application
                                             optimized
                                             (codegen:make-function-table env)))
                           (code (codegen:codegen-expression with-direct-app env))
                           (result (eval code)))
                      (values (format nil "~S" result) type-string))))))))))))

;;;
;;; Standard CL evaluation
;;;

(defun eval-cl (code-string &optional package-name)
  "Evaluate CODE-STRING as standard Common Lisp.
   Returns (values result-string stdout-string)."
  (let* ((*package* (if package-name
                        (or (find-package (string-upcase package-name))
                            (find-package "CL-USER"))
                        (find-package "CL-USER")))
         (*read-eval* t)
         (stdout-capture (make-string-output-stream)))
    (let* ((*standard-output* (make-broadcast-stream *standard-output* stdout-capture))
           (form (read-from-string code-string))
           (result (eval form)))
      (values (format nil "~S" result)
              (get-output-stream-string stdout-capture)))))

;;;
;;; Main dispatch
;;;

(defun eval-input (code &optional package-name)
  "Evaluate CODE, routing to the appropriate evaluator.
   Returns a plist (:success T/NIL :result \"...\" :stdout \"...\" :error \"...\")."
  (handler-case
      (cond
        ;; Coalton toplevel form
        ((coalton-toplevel-form-p code)
         (let ((stdout-capture (make-string-output-stream)))
           (let* ((*standard-output* (make-broadcast-stream *standard-output* stdout-capture))
                  (result (eval-coalton-toplevel code)))
             (list :success t
                   :result result
                   :stdout (get-output-stream-string stdout-capture)))))
        ;; Coalton expression (when package is COALTON-USER)
        ((and package-name
              (string-equal (string-upcase package-name) "COALTON-USER"))
         (let ((stdout-capture (make-string-output-stream)))
           (let ((*standard-output* (make-broadcast-stream *standard-output* stdout-capture)))
             (multiple-value-bind (result-str type-str)
                 (eval-coalton-expression code)
               (list :success t
                     :result (format nil "~A :: ~A" result-str type-str)
                     :stdout (get-output-stream-string stdout-capture))))))
        ;; Standard CL eval
        (t
         (multiple-value-bind (result-str stdout-str)
             (eval-cl code package-name)
           (list :success t
                 :result result-str
                 :stdout stdout-str))))
    (error (e)
      (list :success nil
            :error (format nil "~A" e)))))
