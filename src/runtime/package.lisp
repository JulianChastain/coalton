(uiop:define-package #:coalton-impl/runtime
  (:use #:cl)
  (:import-from #:coalton-impl/util #:coalton-bug)
  (:mix-reexport
   #:coalton-impl/runtime/function-entry
   #:coalton-impl/runtime/optional)
  (:export
   #:coalton-bug
   #:effect-signal
   #:effect-signal-tag
   #:effect-signal-arg
   #:perform-effect))
