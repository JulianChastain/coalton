(in-package #:coalton-library/effects)

(coalton-toplevel

  ;;;
  ;;; Writer Effect
  ;;;
  ;;; The Writer effect provides append-only output accumulation.
  ;;; Output is collected as the computation runs.
  ;;;

  (declare tell (:w -> Unit ! (Writer :w)))
  (define (tell output)
    "Append output to the accumulated output."
    (perform (writer.tell output)))

  (declare listen ((Unit -> :a ! (Writer :w)) -> (Tuple :a (List :w)) ! (Writer :w)))
  (define (listen computation)
    "Run a computation and collect its output along with the result.

Returns a tuple of (result, output-list)."
    (let ((collected (the (List :w) Nil)))
      (let ((result
              (handle (computation)
                (writer.tell (w resume)
                  ;; Collect locally
                  (lisp Unit (w collected)
                    (push w collected)
                    'coalton:Unit)
                  (resume Unit))
                (return (x) x))))
        (Tuple result (reverse collected)))))

  (declare pass ((Unit -> (Tuple :a ((List :w) -> (List :w))) ! (Writer :w)) -> :a ! (Writer :w)))
  (define (pass computation)
    "Run a computation that returns a result and an output modifier.

The modifier is applied to the output produced by the computation."
    (match (listen computation)
      ((Tuple (Tuple result modifier) output)
       ;; Re-emit the modified output
       (map tell (modifier output))
       result)))

  (declare run-writer ((Unit -> :a ! (Writer :w)) -> (Tuple :a (List :w))))
  (define (run-writer computation)
    "Run a writer computation, collecting all output.

Returns a tuple of (result, output-list)."
    (let ((output (the (List :w) Nil)))
      (let ((result
              (handle (computation)
                (writer.tell (w resume)
                  (lisp Unit (w output)
                    (push w output)
                    'coalton:Unit)
                  (resume Unit))
                (return (x) x))))
        (Tuple result (reverse output))))))
