;;;; coalton-run.lisp - Execute Coalton source files
;;;;
;;;; Usage: ./scripts/coalton-run <file.coal>
;;;;    or: echo '(package foo) ...' | ./scripts/coalton-run
;;;;    or: sbcl --noinform --load scripts/coalton-run.lisp <file.coal>

(require :asdf)

;; Load coalton silently
(let ((*standard-output* (make-broadcast-stream))
      (*error-output* (make-broadcast-stream)))
  (handler-bind ((warning #'muffle-warning))
    (asdf:load-system :coalton :verbose nil)))

(defpackage #:coalton-run
  (:use #:cl)
  (:local-nicknames
   (#:source #:coalton-impl/source)
   (#:entry #:coalton-impl/entry)))

(in-package #:coalton-run)

(defun get-input-file ()
  "Get the input filename from command-line arguments, or NIL for stdin."
  (let ((args (uiop:command-line-arguments)))
    (when (and args
               (or (string= (first args) "--help")
                   (string= (first args) "-h")))
      (format *error-output* "Usage: coalton-run [<file.coal>]~%")
      (format *error-output* "~%Compile, typecheck, and execute a Coalton source file.~%")
      (format *error-output* "If no file is given, reads Coalton source from stdin.~%")
      (sb-ext:exit :code 0))
    (first args)))

(defun read-stdin ()
  "Read all of stdin into a string."
  (with-output-to-string (out)
    (loop :for line := (read-line *standard-input* nil nil)
          :while line
          :do (write-line line out))))

(defun extract-package-name-from-string (text)
  "Extract the package name from a Coalton source string's (package ...) header."
  (with-input-from-string (s text)
    (let ((*read-eval* nil)
          (*package* (find-package "KEYWORD")))
      (let ((form (ignore-errors (read s nil nil))))
        (when (and (consp form) (eq (car form) :package))
          (string (cadr form)))))))

(defun extract-package-name (path)
  "Extract the package name from a Coalton source file's (package ...) header."
  (with-open-file (s path :direction :input)
    (let ((*read-eval* nil)
          (*package* (find-package "KEYWORD")))
      (let ((form (ignore-errors (read s nil nil))))
        (when (and (consp form) (eq (car form) :package))
          (string (cadr form)))))))

(defun call-main (pkg-name)
  "Find and call a MAIN function in the given package, if it exists."
  (when pkg-name
    (let* ((pkg (find-package (string-upcase pkg-name)))
           (main-sym (and pkg (find-symbol "MAIN" pkg))))
      (when (and main-sym (fboundp main-sym))
        (funcall main-sym)))))

(defun run-file (path)
  "Compile, typecheck, and execute a Coalton source file."
  (let ((source (source:make-source-file (truename path)))
        (pkg-name (extract-package-name path)))
    (entry:compile source :load t)
    (call-main pkg-name)))

(defun run-stdin ()
  "Read Coalton source from stdin, compile, typecheck, and execute it."
  (let* ((text (read-stdin))
         (pkg-name (extract-package-name-from-string text))
         (source (source:make-source-string text :name "<stdin>")))
    (entry:compile source :load t)
    (call-main pkg-name)))

(defun main ()
  (let ((file (get-input-file)))
    (handler-case
        (if file
            (progn
              (unless (probe-file file)
                (format *error-output* "Error: File not found: ~A~%" file)
                (sb-ext:exit :code 1))
              (run-file file))
            (run-stdin))
      (source:source-error (e)
        (format *error-output* "~A~%" e)
        (sb-ext:exit :code 1))
      (error (e)
        (format *error-output* "Error: ~A~%" e)
        (sb-ext:exit :code 1)))))

(main)
(sb-ext:exit :code 0)
