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
   #:coalton-library/functions)
  (:local-nicknames
   (#:cell #:coalton-library/cell))
  (:export
   ;; State effect
   #:State
   #:get
   #:put
   #:modify
   #:run-state
   ;; Reader effect
   #:Reader
   #:ask
   #:asks
   #:local
   #:run-reader
   ;; Writer effect
   #:Writer
   #:tell
   #:listen
   #:pass
   #:run-writer
   ;; Effect combinators
   #:pure
   #:with-effect))

(in-package #:coalton-library/effects)
