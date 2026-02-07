;;;; run-parser-tests.lisp - Run parser tests with summary output
;;;;
;;;; Usage: qlot exec sbcl --load scripts/run-parser-tests.lisp
;;;;
;;;; Outputs a compact summary showing total tests, passing tests,
;;;; and names of any failing tests.

(require :asdf)

;; Suppress most output during loading
(let ((*standard-output* (make-broadcast-stream))
      (*error-output* (make-broadcast-stream)))
  (handler-bind ((warning #'muffle-warning))
    (asdf:load-system :fiasco :verbose nil)
    (asdf:load-system :coalton :verbose nil)))

;; Load test files
(let ((*standard-output* (make-broadcast-stream)))
  (load "tests/parser/scope-tests.lisp")
  (load "tests/parser/syntax-object-tests.lisp")
  (load "tests/parser/binding-table-tests.lisp")
  (load "tests/parser/syntax-cst-tests.lisp")
  (load "tests/parser/hygienic-macro-tests.lisp")
  (load "tests/parser/hygienic-integration-tests.lisp")
  (load "tests/parser/syntax-case-tests.lisp")
  (load "tests/parser/definition-context-tests.lisp")
  (load "tests/parser/parser-integration-tests.lisp"))

;; Custom test runner that captures results
(defun run-tests-with-summary (package-names)
  "Run tests in PACKAGE-NAMES and print a compact summary."
  (let ((total 0)
        (passed 0)
        (failed-names '()))
    ;; Capture fiasco's output and parse it
    (let ((output (make-string-output-stream)))
      (let ((*standard-output* output)
            (*error-output* output))
        (fiasco:run-tests package-names))
      (let ((result-string (get-output-stream-string output)))
        ;; Parse the output to count tests and find failures
        (with-input-from-string (s result-string)
          (loop for line = (read-line s nil nil)
                while line
                do (cond
                     ;; Count passing tests
                     ((search "[ OK ]" line)
                      (incf total)
                      (incf passed))
                     ;; Count and record failing tests
                     ((or (search "[FAIL]" line)
                          (search "UNEXPECTED-ERROR" line))
                      (incf total)
                      ;; Extract test name from line
                      (let* ((trimmed (string-trim '(#\Space #\Tab) line))
                             (dot-pos (position #\. trimmed))
                             (name (if dot-pos
                                       (subseq trimmed 0 dot-pos)
                                       trimmed)))
                        (push name failed-names))))))))
    ;; Print summary
    (format t "~%========================================~%")
    (format t "Parser Test Summary~%")
    (format t "========================================~%")
    (format t "Total:  ~D~%" total)
    (format t "Passed: ~D~%" passed)
    (format t "Failed: ~D~%" (length failed-names))
    (when failed-names
      (format t "~%Failed tests:~%")
      (dolist (name (nreverse failed-names))
        (format t "  - ~A~%" name)))
    (format t "========================================~%")
    ;; Return success/failure
    (zerop (length failed-names))))

;; Run tests
(let ((success (run-tests-with-summary
                '(coalton-impl/parser/scope-tests
                  coalton-impl/parser/syntax-object-tests
                  coalton-impl/parser/binding-table-tests
                  coalton-impl/parser/syntax-cst-tests
                  coalton-impl/parser/hygienic-macro-tests
                  coalton-impl/parser/hygienic-integration-tests
                  coalton/tests/parser/syntax-case-tests
                  coalton-impl/parser/definition-context-tests
                  coalton-impl/parser/parser-integration-tests))))
  (sb-ext:exit :code (if success 0 1)))
