(defpackage #:coalton-library/effects
  (:documentation "Standard algebraic effects for Coalton.

This package provides common effect types and handlers:
- State: Mutable state
- Reader: Read-only environment
- Writer: Append-only output
- Exception: Error handling (non-resumable)")
  (:use
   #:coalton
   #:coalton-library/classes
   #:coalton-library/functions
   #:coalton-library/list)
  (:local-nicknames
   (#:cell #:coalton-library/cell))
  (:export
   ;; State effect
   #:get
   #:put
   #:modify
   #:run-state
   ;; Reader effect
   #:ask
   #:asks
   #:local
   #:run-reader
   ;; Writer effect
   #:tell
   #:listen
   #:pass
   #:run-writer
   ))

(in-package #:coalton-library/effects)
