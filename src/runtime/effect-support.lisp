;;;; effect-support.lisp
;;;;
;;;; Runtime support for algebraic effects built on CL conditions/restarts.
;;;;
;;;; Effects use CL's condition system:
;;;; - perform signals an EFFECT-SIGNAL condition and establishes a RESUME-EFFECT restart
;;;; - handle uses handler-bind to catch matching signals and invoke-restart to resume
;;;;
;;;; This gives single-shot resumable continuations: the handler can call
;;;; (resume value) to return a value to the perform site.

(in-package #:coalton-impl/runtime)

(define-condition effect-signal ()
  ((tag :initarg :tag :reader effect-signal-tag)
   (arg :initarg :arg :reader effect-signal-arg))
  (:documentation "Condition signaled by PERFORM to invoke an effect handler."))

(defvar *unhandled-sentinel* (gensym "UNHANDLED"))

(defun perform-effect (tag arg)
  "Perform an effect operation. Signals an EFFECT-SIGNAL condition and
establishes a RESUME-EFFECT restart. The handler should invoke the restart
with the resume value. Raises an error if no handler is installed."
  (let ((result
          (restart-case
              (progn
                (signal 'effect-signal :tag tag :arg arg)
                *unhandled-sentinel*)
            (resume-effect (value)
              :report "Resume the effect computation with a value."
              value))))
    (when (eq result *unhandled-sentinel*)
      (error "Unhandled effect operation: ~A~@[ with argument ~S~]" tag arg))
    result))
