(in-package #:jynx-lisply)

(defvar *port* 9081
  "Default port for the Lisply HTTP backend.")

(defvar *server* nil
  "The running Hunchentoot acceptor, or NIL.")

;;;
;;; JSON helpers
;;;

(defun json-content-type ()
  "Set the response content type to JSON."
  (setf (hunchentoot:content-type*) "application/json"))

(defun parse-json-body ()
  "Parse the JSON body of the current request.
   Returns the parsed hash table, or NIL on failure."
  (let ((body (hunchentoot:raw-post-data :force-text t)))
    (when (and body (plusp (length body)))
      (yason:parse body))))

(defun encode-result-plist (result)
  "Encode a result plist (:success T/NIL :result/:error ...) as a JSON string."
  (with-output-to-string (s)
    (yason:with-output (s)
      (yason:with-object ()
        (if (getf result :success)
            (progn
              (yason:encode-object-element "success" t)
              (let ((val (getf result :result)))
                (yason:encode-object-element
                 "result"
                 (if (listp val)
                     ;; Convert list of strings or plists to JSON-friendly format
                     (mapcar (lambda (item)
                               (if (stringp item)
                                   item
                                   (format nil "~S" item)))
                             val)
                     val))))
            (progn
              (yason:encode-object-element "success" 'yason:false)
              (yason:encode-object-element "error" (getf result :error))))))))

;;;
;;; Endpoint: ping
;;;

(defun handle-ping ()
  "Handle GET /lisply/ping-lisp."
  (json-content-type)
  (with-output-to-string (s)
    (yason:with-output (s)
      (yason:with-object ()
        (yason:encode-object-element "status" "ok")
        (yason:encode-object-element "implementation" "jynx-lisply")
        (yason:encode-object-element "lisp-implementation"
                                     (lisp-implementation-type))
        (yason:encode-object-element "lisp-version"
                                     (lisp-implementation-version))))))

;;;
;;; Endpoint: lisp-eval
;;;

(defun handle-lisp-eval ()
  "Handle POST /lisply/lisp-eval."
  (json-content-type)
  (let* ((json (parse-json-body))
         (code (and json (gethash "code" json)))
         (package-name (and json (gethash "package" json))))
    (cond
      ((null code)
       (with-output-to-string (s)
         (yason:with-output (s)
           (yason:with-object ()
             (yason:encode-object-element "success" 'yason:false)
             (yason:encode-object-element "error" "Missing 'code' field in request")))))
      (t
       (let ((result (eval-input code package-name)))
         (with-output-to-string (s)
           (yason:with-output (s)
             (yason:with-object ()
               (if (getf result :success)
                   (progn
                     (yason:encode-object-element "success" t)
                     (yason:encode-object-element "result" (getf result :result))
                     (yason:encode-object-element "stdout" (or (getf result :stdout) "")))
                   (progn
                     (yason:encode-object-element "success" 'yason:false)
                     (yason:encode-object-element "error" (getf result :error))))))))))))

;;;
;;; Endpoint: type-of
;;;

(defun handle-type-of ()
  "Handle POST /lisply/type-of."
  (json-content-type)
  (let* ((json (parse-json-body))
         (name (and json (gethash "name" json))))
    (if (null name)
        (with-output-to-string (s)
          (yason:with-output (s)
            (yason:with-object ()
              (yason:encode-object-element "success" 'yason:false)
              (yason:encode-object-element "error" "Missing 'name' field"))))
        (encode-result-plist (lookup-type-of name)))))

;;;
;;; Endpoint: list-definitions
;;;

(defun handle-list-definitions ()
  "Handle POST /lisply/list-definitions."
  (json-content-type)
  (let* ((json (parse-json-body))
         (filter-package (and json (gethash "package" json))))
    (encode-result-plist (list-definitions filter-package))))

;;;
;;; Endpoint: apropos-coalton
;;;

(defun handle-apropos-coalton ()
  "Handle POST /lisply/apropos-coalton."
  (json-content-type)
  (let* ((json (parse-json-body))
         (search (and json (gethash "search" json))))
    (if (null search)
        (with-output-to-string (s)
          (yason:with-output (s)
            (yason:with-object ()
              (yason:encode-object-element "success" 'yason:false)
              (yason:encode-object-element "error" "Missing 'search' field"))))
        (encode-result-plist (apropos-coalton search)))))

;;;
;;; Endpoint: reset-environment
;;;

(defun handle-reset-environment ()
  "Handle POST /lisply/reset-environment."
  (json-content-type)
  (encode-result-plist (reset-environment)))

;;;
;;; Endpoint: type-check
;;;

(defun handle-type-check ()
  "Handle POST /lisply/type-check."
  (json-content-type)
  (let* ((json (parse-json-body))
         (code (and json (gethash "code" json))))
    (if (null code)
        (with-output-to-string (s)
          (yason:with-output (s)
            (yason:with-object ()
              (yason:encode-object-element "success" 'yason:false)
              (yason:encode-object-element "error" "Missing 'code' field"))))
        (encode-result-plist (type-check-expression code)))))

;;;
;;; Endpoint: multi-eval
;;;

(defun handle-multi-eval ()
  "Handle POST /lisply/multi-eval."
  (json-content-type)
  (let* ((json (parse-json-body))
         (code (and json (gethash "code" json)))
         (package-name (and json (gethash "package" json))))
    (if (null code)
        (with-output-to-string (s)
          (yason:with-output (s)
            (yason:with-object ()
              (yason:encode-object-element "success" 'yason:false)
              (yason:encode-object-element "error" "Missing 'code' field"))))
        (encode-result-plist (eval-multiple code package-name)))))

;;;
;;; Endpoint: describe-symbol
;;;

(defun handle-describe-symbol ()
  "Handle POST /lisply/describe-symbol."
  (json-content-type)
  (let* ((json (parse-json-body))
         (name (and json (gethash "name" json))))
    (if (null name)
        (with-output-to-string (s)
          (yason:with-output (s)
            (yason:with-object ()
              (yason:encode-object-element "success" 'yason:false)
              (yason:encode-object-element "error" "Missing 'name' field"))))
        (encode-result-plist (describe-symbol name)))))

;;;
;;; Endpoint: macroexpand-coalton
;;;

(defun handle-macroexpand-coalton ()
  "Handle POST /lisply/macroexpand-coalton."
  (json-content-type)
  (let* ((json (parse-json-body))
         (code (and json (gethash "code" json))))
    (if (null code)
        (with-output-to-string (s)
          (yason:with-output (s)
            (yason:with-object ()
              (yason:encode-object-element "success" 'yason:false)
              (yason:encode-object-element "error" "Missing 'code' field"))))
        (encode-result-plist (macroexpand-coalton code)))))

;;;
;;; Endpoint: disassemble-coalton
;;;

(defun handle-disassemble-coalton ()
  "Handle POST /lisply/disassemble-coalton."
  (json-content-type)
  (let* ((json (parse-json-body))
         (name (and json (gethash "name" json))))
    (if (null name)
        (with-output-to-string (s)
          (yason:with-output (s)
            (yason:with-object ()
              (yason:encode-object-element "success" 'yason:false)
              (yason:encode-object-element "error" "Missing 'name' field"))))
        (encode-result-plist (disassemble-coalton name)))))

;;;
;;; Endpoint: load-file
;;;

(defun handle-load-file ()
  "Handle POST /lisply/load-file."
  (json-content-type)
  (let* ((json (parse-json-body))
         (path (and json (gethash "path" json)))
         (package-name (and json (gethash "package" json))))
    (if (null path)
        (with-output-to-string (s)
          (yason:with-output (s)
            (yason:with-object ()
              (yason:encode-object-element "success" 'yason:false)
              (yason:encode-object-element "error" "Missing 'path' field"))))
        (encode-result-plist (load-coalton-file path package-name)))))

;;;
;;; Endpoint: tools/list
;;;

(defun handle-tools-list ()
  "Handle GET /lisply/tools/list."
  (json-content-type)
  (with-output-to-string (s)
    (yason:with-output (s)
      (yason:with-object ()
        (yason:encode-object-element
         "tools"
         (list
          ;; lisp_eval tool
          (alexandria:plist-hash-table
           (list "name" "lisp_eval"
                 "description" "Evaluates Lisp code directly within the Jynx (Coalton) environment. Coalton toplevel forms (define, define-type, etc.) are automatically detected. Use package COALTON-USER to evaluate Coalton expressions."
                 "inputSchema" (alexandria:plist-hash-table
                                (list "type" "object"
                                      "properties" (alexandria:plist-hash-table
                                                    (list "code" (alexandria:plist-hash-table
                                                                  (list "type" "string"
                                                                        "description" "The Lisp or Coalton code to evaluate"))
                                                          "package" (alexandria:plist-hash-table
                                                                     (list "type" "string"
                                                                           "description" "The package to use for evaluation (optional). Use COALTON-USER for Coalton expressions."))))
                                      "required" (list "code"))
                                :test #'equal))
           :test #'equal)
          ;; ping_lisp tool
          (alexandria:plist-hash-table
           (list "name" "ping_lisp"
                 "description" "Checks if the Jynx Lisply backend is available"
                 "inputSchema" (alexandria:plist-hash-table
                                (list "type" "object"
                                      "properties" (make-hash-table :test #'equal))
                                :test #'equal))
           :test #'equal)))))))

;;;
;;; Endpoint: docs
;;;

(defun docs-directory ()
  "Return the path to the docs/ directory in the project root."
  (merge-pathnames #p"docs/" (asdf:system-source-directory :jynx-lisply)))

(defun doc-id-from-path (path)
  "Derive a document ID from a pathname (filename without .md extension)."
  (pathname-name path))

(defun list-doc-files ()
  "Return a list of .md files in the docs directory (non-recursive)."
  (let ((pattern (merge-pathnames #p"*.md" (docs-directory))))
    (directory pattern)))

(defun handle-docs-list ()
  "Handle GET /lisply/docs/list."
  (json-content-type)
  (let ((files (list-doc-files)))
    (with-output-to-string (s)
      (yason:with-output (s)
        (yason:with-object ()
          (yason:encode-object-element
           "docs"
           (mapcar (lambda (path)
                     (let ((id (doc-id-from-path path)))
                       (alexandria:plist-hash-table
                        (list "id" id
                              "filename" (file-namestring path))
                        :test #'equal)))
                   files)))))))

(defun handle-get-doc ()
  "Handle GET /lisply/docs/:id."
  (json-content-type)
  (let* ((uri (hunchentoot:request-uri*))
         (id (car (last (uiop:split-string uri :separator "/"))))
         (path (merge-pathnames (make-pathname :name id :type "md")
                                (docs-directory))))
    (cond
      ((or (null id) (string= id ""))
       (setf (hunchentoot:return-code*) 400)
       (with-output-to-string (s)
         (yason:with-output (s)
           (yason:with-object ()
             (yason:encode-object-element "error" "Missing document ID")))))
      ((not (probe-file path))
       (setf (hunchentoot:return-code*) 404)
       (with-output-to-string (s)
         (yason:with-output (s)
           (yason:with-object ()
             (yason:encode-object-element "error"
                                          (format nil "Document not found: ~A" id))))))
      (t
       (with-output-to-string (s)
         (yason:with-output (s)
           (yason:with-object ()
             (yason:encode-object-element "id" id)
             (yason:encode-object-element "content"
                                          (uiop:read-file-string path)))))))))

;;;
;;; Dispatch table and server lifecycle
;;;

(defun make-dispatch-table ()
  "Create the Hunchentoot dispatch table for Lisply endpoints."
  (list
   (hunchentoot:create-regex-dispatcher "^/lisply/ping-lisp$" #'handle-ping)
   (hunchentoot:create-regex-dispatcher "^/lisply/lisp-eval$" #'handle-lisp-eval)
   (hunchentoot:create-regex-dispatcher "^/lisply/tools/list$" #'handle-tools-list)
   (hunchentoot:create-regex-dispatcher "^/lisply/docs/list$" #'handle-docs-list)
   (hunchentoot:create-regex-dispatcher "^/lisply/docs/[^/]+$" #'handle-get-doc)
   ;; New tool endpoints
   (hunchentoot:create-regex-dispatcher "^/lisply/type-of$" #'handle-type-of)
   (hunchentoot:create-regex-dispatcher "^/lisply/list-definitions$" #'handle-list-definitions)
   (hunchentoot:create-regex-dispatcher "^/lisply/apropos-coalton$" #'handle-apropos-coalton)
   (hunchentoot:create-regex-dispatcher "^/lisply/reset-environment$" #'handle-reset-environment)
   (hunchentoot:create-regex-dispatcher "^/lisply/type-check$" #'handle-type-check)
   (hunchentoot:create-regex-dispatcher "^/lisply/multi-eval$" #'handle-multi-eval)
   (hunchentoot:create-regex-dispatcher "^/lisply/describe-symbol$" #'handle-describe-symbol)
   (hunchentoot:create-regex-dispatcher "^/lisply/macroexpand-coalton$" #'handle-macroexpand-coalton)
   (hunchentoot:create-regex-dispatcher "^/lisply/disassemble-coalton$" #'handle-disassemble-coalton)
   (hunchentoot:create-regex-dispatcher "^/lisply/load-file$" #'handle-load-file)))

(defun start-server (&key (port *port*))
  "Start the Lisply HTTP backend on PORT."
  (when *server*
    (format t "~&Stopping existing server...~%")
    (stop-server))
  (setf *port* port)
  ;; Snapshot the environment at startup for reset support
  (snapshot-environment)
  (let ((acceptor (make-instance 'hunchentoot:easy-acceptor
                                 :port port
                                 :taskmaster (make-instance 'hunchentoot:single-threaded-taskmaster)
                                 :access-log-destination nil
                                 :message-log-destination nil)))
    (setf hunchentoot:*dispatch-table* (make-dispatch-table))
    (hunchentoot:start acceptor)
    (setf *server* acceptor)
    (format t "~&Jynx Lisply backend started on port ~D~%" port)
    (format t "  Ping:  http://127.0.0.1:~D/lisply/ping-lisp~%" port)
    (format t "  Eval:  http://127.0.0.1:~D/lisply/lisp-eval~%" port)
    (format t "  Tools: http://127.0.0.1:~D/lisply/tools/list~%" port)
    acceptor))

(defun stop-server ()
  "Stop the Lisply HTTP backend."
  (when *server*
    (hunchentoot:stop *server*)
    (setf *server* nil)
    (format t "~&Jynx Lisply backend stopped.~%")))
