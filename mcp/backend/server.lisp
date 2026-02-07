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
   (hunchentoot:create-regex-dispatcher "^/lisply/docs/[^/]+$" #'handle-get-doc)))

(defun start-server (&key (port *port*))
  "Start the Lisply HTTP backend on PORT."
  (when *server*
    (format t "~&Stopping existing server...~%")
    (stop-server))
  (setf *port* port)
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
