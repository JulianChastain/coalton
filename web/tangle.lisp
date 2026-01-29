;;;; Simple tangler for CLWEB files
;;;; This is a workaround for CLWEB compatibility issues with modern SBCL.
;;;; It extracts Lisp code from @l sections without the problematic indexing.

(defpackage #:coalton-web/tangle
  (:use #:cl)
  (:export #:tangle-file #:tangle-to-string))

(in-package #:coalton-web/tangle)

(defun read-web-sections (input-stream)
  "Read a CLWEB file and return a list of (type . content) pairs.
Type is :LIMBO, :TEXT, or :LISP."
  (let ((sections '())
        (current-type :limbo)
        (current-content (make-string-output-stream)))
    (labels ((save-section ()
               (let ((content (get-output-stream-string current-content)))
                 (when (plusp (length content))
                   (push (cons current-type content) sections))))
             (start-section (type)
               (save-section)
               (setf current-type type
                     current-content (make-string-output-stream))))
      (loop
        (let ((char (read-char input-stream nil nil)))
          (unless char
            (save-section)
            (return (nreverse sections)))
          (if (char= char #\@)
              (let ((next (read-char input-stream nil nil)))
                (case next
                  ;; @* = starred section (text)
                  (#\* (start-section :text)
                       ;; Skip optional section level digit and space
                       (let ((c (peek-char nil input-stream nil nil)))
                         (when (and c (digit-char-p c))
                           (read-char input-stream)
                           (let ((c2 (peek-char nil input-stream nil nil)))
                             (when (and c2 (char= c2 #\Space))
                               (read-char input-stream))))))
                  ;; @  = regular section (text)
                  (#\Space (start-section :text))
                  ;; @l = Lisp code section
                  ((#\l #\L) (start-section :lisp))
                  ;; @@ = literal @
                  (#\@ (write-char #\@ current-content))
                  ;; @i = include (skip for now)
                  ((#\i #\I)
                   ;; Read until end of line
                   (loop for c = (read-char input-stream nil nil)
                         while (and c (not (char= c #\Newline)))))
                  ;; Anything else, keep as-is
                  (otherwise
                   (write-char #\@ current-content)
                   (when next (write-char next current-content)))))
              (write-char char current-content)))))))

(defun tangle-to-string (input-file)
  "Tangle a CLWEB file and return the Lisp code as a string."
  (with-open-file (in input-file :direction :input)
    (let ((sections (read-web-sections in)))
      (with-output-to-string (out)
        (format out ";;;; Tangled from ~A~%;;;; DO NOT EDIT - edit the .clw file instead~%~%"
                (file-namestring input-file))
        (dolist (section sections)
          (when (eq (car section) :lisp)
            (write-string (cdr section) out)
            (terpri out)))))))

(defun tangle-file (input-file &optional output-file)
  "Tangle a CLWEB file to a Lisp file."
  (let* ((input-path (pathname input-file))
         (output-path (or output-file
                          (make-pathname :type "lisp" :defaults input-path))))
    (with-open-file (out output-path :direction :output :if-exists :supersede)
      (write-string (tangle-to-string input-path) out))
    (format t "Tangled ~A to ~A~%" input-file output-path)
    output-path))
