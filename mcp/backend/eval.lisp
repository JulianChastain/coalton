(in-package #:jynx-lisply)

;;;
;;; Timeout support (W6)
;;;

(defvar *eval-timeout* 30
  "Timeout in seconds for eval operations.")

(defmacro with-eval-timeout ((&optional (seconds '*eval-timeout*)) &body body)
  "Execute BODY with a timeout of SECONDS seconds."
  `(handler-case (sb-ext:with-timeout ,seconds ,@body)
     (sb-ext:timeout ()
       (error "Evaluation timed out after ~D seconds" ,seconds))))

;;;
;;; Environment snapshot (for reset support)
;;;

(defvar *initial-environment* nil
  "Snapshot of the environment at server startup, used for reset.")

(defun snapshot-environment ()
  "Save the current global environment as the initial snapshot."
  (setf *initial-environment* entry:*global-environment*))

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
;;; Instance predicate formatting (W7)
;;;

(defun format-parser-ty (ty)
  "Format a parser type object into a readable string."
  (typecase ty
    (coalton-impl/parser/types:tycon
     (symbol-name (coalton-impl/parser/types:tycon-name ty)))
    (coalton-impl/parser/types:tyvar
     (symbol-name (coalton-impl/parser/types:tyvar-name ty)))
    (t (format nil "~S" ty))))

(defun format-instance-pred (pred)
  "Format a parser ty-predicate into a readable string like 'Eq MyColor'.
   The pred is a coalton-impl/parser/types:ty-predicate whose class slot
   is an identifier-src (with source-name) and whose types are parser ty objects."
  (let ((class-id (coalton-impl/parser/types:ty-predicate-class pred))
        (types (coalton-impl/parser/types:ty-predicate-types pred)))
    (let ((class-name (or (parser:identifier-src-source-name class-id)
                          (symbol-name (parser:identifier-src-name class-id)))))
      (if types
          (format nil "~A ~{~A~^ ~}" class-name
                  (mapcar #'format-parser-ty types))
          class-name))))

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
            ;; Compile and evaluate (W6: timeout)
            (multiple-value-bind (compiled-code new-env)
                (entry:entry-point program)
              (setf entry:*global-environment* new-env)
              (with-eval-timeout ()
                (eval compiled-code))
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
                  ;; W7: Better instance display
                  (dolist (def (parser:program-instances program))
                    (unless first (write-string "; " out))
                    (format out "Instance defined: ~A"
                            (format-instance-pred
                             (parser:toplevel-define-instance-pred def)))
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
                           ;; W6: timeout
                           (result (with-eval-timeout ()
                                     (eval code))))
                      (values (format nil "~S" result) type-string))))))))))))

;;;
;;; Type-check only (no eval)
;;;

(defun type-check-expression (input-string)
  "Type-check a Coalton expression without evaluating it.
   Returns a plist with :success and :result (the type string)."
  (handler-case
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
                (declare (ignore node))
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
                           (ty (tc:apply-substitution subs ty))
                           (qual-ty (tc:qualify preds ty))
                           (scheme (tc:quantify (tc:type-variables qual-ty) qual-ty)))
                      (list :success t
                            :result (tc:with-pprint-variable-context ()
                                      (with-output-to-string (s)
                                        (write scheme :stream s))))))))))))
    (error (e)
      (list :success nil
            :error (format nil "[~A] ~A" (type-of e) e)))))

;;;
;;; Macroexpand Coalton expression
;;;

(defun macroexpand-coalton (input-string)
  "Compile a Coalton expression through the codegen pipeline, returning the
   generated Common Lisp code as a string instead of evaluating it.
   Returns a plist with :success and :result."
  (handler-case
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
                      (declare (ignore scheme))
                      (when preds
                        (error "Unable to resolve type class constraints: ~S" preds))
                      (let* ((translated (codegen:translate-expression node nil env))
                             (optimized (codegen:optimize-node translated env))
                             (with-direct-app (codegen:direct-application
                                               optimized
                                               (codegen:make-function-table env)))
                             (code (codegen:codegen-expression with-direct-app env)))
                        (list :success t
                              :result (with-output-to-string (s)
                                        (let ((*package* (find-package "COALTON-USER")))
                                          (pprint code s)))))))))))))
    (error (e)
      (list :success nil
            :error (format nil "[~A] ~A" (type-of e) e)))))

;;;
;;; Standard CL evaluation (W3: multi-value, W4: multi-form)
;;;

(defun eval-cl (code-string &optional package-name)
  "Evaluate CODE-STRING as standard Common Lisp.
   Reads and evaluates all forms. Captures multiple values.
   Returns (values result-string stdout-string)."
  (let* ((*package* (if package-name
                        (or (find-package (string-upcase package-name))
                            (find-package "CL-USER"))
                        (find-package "CL-USER")))
         (*read-eval* t)
         (stdout-capture (make-string-output-stream)))
    (let ((*standard-output* (make-broadcast-stream *standard-output* stdout-capture)))
      ;; W4: Read and eval all forms in the string
      (let ((results nil)
            (sentinel (gensym "EOF")))
        (with-input-from-string (s code-string)
          (loop for form = (read s nil sentinel)
                until (eq form sentinel)
                do (setf results
                         ;; W3: Capture multiple values
                         (with-eval-timeout ()
                           (multiple-value-list (eval form))))))
        (values
         (if results
             (format nil "~{~S~^; ~}" (or results '(nil)))
             "NIL")
         (get-output-stream-string stdout-capture))))))

;;;
;;; Main dispatch (W2: progn interception fix)
;;;

(defun eval-input (code &optional package-name)
  "Evaluate CODE, routing to the appropriate evaluator.
   Returns a plist (:success T/NIL :result \"...\" :stdout \"...\" :error \"...\")."
  (handler-case
      (cond
        ;; W2: Only route to Coalton toplevel when package is COALTON-USER or unspecified
        ((and (or (null package-name)
                  (string-equal (string-upcase package-name) "COALTON-USER"))
              (coalton-toplevel-form-p code))
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
    ;; W10: Include condition type in error messages
    (error (e)
      (list :success nil
            :error (format nil "[~A] ~A" (type-of e) e)))))

;;;
;;; Lookup type of a symbol
;;;

(defun lookup-type-of (name-string)
  "Look up the type of a Coalton symbol by name.
   Returns a plist with :success and :result."
  (handler-case
      (let* ((*package* (find-package "COALTON-USER"))
             (sym (read-from-string name-string))
             (env entry:*global-environment*)
             (scheme (tc:lookup-value-type env sym :no-error t)))
        (if scheme
            (list :success t
                  :result (tc:with-pprint-variable-context ()
                            (with-output-to-string (s)
                              (format s "~A :: " sym)
                              (write scheme :stream s))))
            (list :success nil
                  :error (format nil "No type found for: ~A" name-string))))
    (error (e)
      (list :success nil
            :error (format nil "[~A] ~A" (type-of e) e)))))

;;;
;;; List definitions in environment
;;;

(defun list-definitions (&optional filter-package)
  "List all value definitions in the current environment.
   Optionally filter to symbols from FILTER-PACKAGE.
   Returns a plist with :success and :result (a list of strings)."
  (handler-case
      (let* ((env entry:*global-environment*)
             (val-env (tc:environment-value-environment env))
             (entries nil))
        (fset:do-map (sym scheme (algo:immutable-map-data val-env))
          (when (or (null filter-package)
                    (and (symbol-package sym)
                         (string-equal (package-name (symbol-package sym))
                                       (string-upcase filter-package))))
            (push (tc:with-pprint-variable-context ()
                    (with-output-to-string (s)
                      (format s "~A :: " sym)
                      (write scheme :stream s)))
                  entries)))
        (list :success t
              :result (sort entries #'string<)))
    (error (e)
      (list :success nil
            :error (format nil "[~A] ~A" (type-of e) e)))))

;;;
;;; Apropos for Coalton symbols
;;;

(defun apropos-coalton (search-string)
  "Search for Coalton value definitions matching SEARCH-STRING (case-insensitive).
   Returns a plist with :success and :result (a list of strings)."
  (handler-case
      (let* ((env entry:*global-environment*)
             (val-env (tc:environment-value-environment env))
             (upper (string-upcase search-string))
             (entries nil))
        (fset:do-map (sym scheme (algo:immutable-map-data val-env))
          (when (search upper (symbol-name sym))
            (push (tc:with-pprint-variable-context ()
                    (with-output-to-string (s)
                      (format s "~A :: " sym)
                      (write scheme :stream s)))
                  entries)))
        (list :success t
              :result (sort entries #'string<)))
    (error (e)
      (list :success nil
            :error (format nil "[~A] ~A" (type-of e) e)))))

;;;
;;; Reset environment
;;;

(defun reset-environment ()
  "Reset the global environment to the initial snapshot.
   Returns a plist with :success and :result."
  (handler-case
      (if *initial-environment*
          (progn
            (setf entry:*global-environment* *initial-environment*)
            (list :success t
                  :result "Environment reset to initial state."))
          (list :success nil
                :error "No initial environment snapshot available. Server may need restart."))
    (error (e)
      (list :success nil
            :error (format nil "[~A] ~A" (type-of e) e)))))

;;;
;;; Eval multiple forms
;;;

(defun eval-multiple (code-string &optional package-name)
  "Evaluate multiple Coalton/CL forms from CODE-STRING.
   Each form is dispatched through eval-input independently.
   Returns a plist with :success and :result (a list of result plists)."
  (handler-case
      (let* ((*package* (if package-name
                            (or (find-package (string-upcase package-name))
                                (find-package "COALTON-USER"))
                            (find-package "COALTON-USER")))
             (*read-eval* nil)
             (results nil)
             (sentinel (gensym "EOF")))
        (with-input-from-string (s code-string)
          (loop for form = (read s nil sentinel)
                for i from 0
                until (eq form sentinel)
                do (let* ((form-string (with-output-to-string (out)
                                         (let ((*package* (find-package "COALTON-USER")))
                                           (write form :stream out))))
                          (result (eval-input form-string package-name)))
                     (push (list :index i :form form-string :result result) results))))
        (list :success t
              :result (nreverse results)))
    (error (e)
      (list :success nil
            :error (format nil "[~A] ~A" (type-of e) e)))))

;;;
;;; Describe symbol
;;;

(defun describe-symbol (name-string)
  "Describe a Coalton symbol comprehensively: its type, type-def, class-def, and CL description.
   Returns a plist with :success and :result."
  (handler-case
      (let* ((*package* (find-package "COALTON-USER"))
             (sym (read-from-string name-string))
             (env entry:*global-environment*)
             (sections nil))
        ;; Value type
        (let ((scheme (tc:lookup-value-type env sym :no-error t)))
          (when scheme
            (push (tc:with-pprint-variable-context ()
                    (format nil "Value type: ~A :: ~A" sym
                            (with-output-to-string (s)
                              (write scheme :stream s))))
                  sections)))
        ;; Type definition
        (let ((type-entry (tc:lookup-type env sym :no-error t)))
          (when type-entry
            (push (format nil "Type: ~A~@[ (constructors: ~{~A~^, ~})~]"
                          (tc:type-entry-name type-entry)
                          (tc:type-entry-constructors type-entry))
                  sections)))
        ;; Class definition
        (let ((class-entry (tc:lookup-class env sym :no-error t)))
          (when class-entry
            (push (format nil "Class: ~A~@[ (superclasses: ~{~A~^, ~})~]"
                          (tc:ty-class-name class-entry)
                          (mapcar #'tc:ty-predicate-class
                                  (tc:ty-class-superclasses class-entry)))
                  sections)))
        ;; CL describe
        (let ((cl-desc (with-output-to-string (s)
                         (describe sym s))))
          (when (plusp (length cl-desc))
            (push (format nil "CL description:~%~A" cl-desc) sections)))
        (if sections
            (list :success t
                  :result (format nil "~{~A~^~%~%~}" (nreverse sections)))
            (list :success nil
                  :error (format nil "No information found for: ~A" name-string))))
    (error (e)
      (list :success nil
            :error (format nil "[~A] ~A" (type-of e) e)))))

;;;
;;; Disassemble Coalton
;;;

(defun disassemble-coalton (name-string)
  "Look up the stored code for a Coalton function.
   Returns a plist with :success and :result."
  (handler-case
      (let* ((*package* (find-package "COALTON-USER"))
             (sym (read-from-string name-string))
             (env entry:*global-environment*)
             (code (tc:lookup-code env sym :no-error t)))
        (if code
            (list :success t
                  :result (with-output-to-string (s)
                            (let ((*package* (find-package "COALTON-USER")))
                              (pprint code s))))
            ;; Fall back to CL disassemble if no stored code
            (let ((fun (and (fboundp sym) (symbol-function sym))))
              (if fun
                  (list :success t
                        :result (with-output-to-string (s)
                                  (disassemble fun :stream s)))
                  (list :success nil
                        :error (format nil "No code found for: ~A" name-string))))))
    (error (e)
      (list :success nil
            :error (format nil "[~A] ~A" (type-of e) e)))))

;;;
;;; Load Coalton file
;;;

(defun load-coalton-file (file-path &optional package-name)
  "Load and evaluate a file containing Coalton/CL forms.
   Returns a plist with :success and :result."
  (handler-case
      (let ((content (uiop:read-file-string file-path)))
        (eval-multiple content package-name))
    (error (e)
      (list :success nil
            :error (format nil "[~A] ~A" (type-of e) e)))))
