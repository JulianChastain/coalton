(defpackage #:coalton-library/continuations
  (:documentation "Delimited continuations for Coalton.

This package provides first-class delimited continuations using shift/reset.
Delimited continuations allow capturing a portion of the program's control flow
and manipulating it as a first-class value.

Key concepts:
- reset: Establishes a delimiter (prompt) that limits continuation capture
- shift: Captures the continuation up to the nearest enclosing reset
- call/cc: Captures the full continuation (non-delimited)

Example:
  (reset
    (+ 1 (shift k
           (+ 10 (k 5)))))
  ;; => 16

The captured continuation k represents the computation (+ 1 [_]) where [_]
is the hole to be filled. Calling (k 5) fills the hole with 5, giving 6,
and the outer + 10 gives 16.

Implementation: Uses cl-cont at runtime for actual continuation capture.")
  (:use
   #:coalton
   #:coalton-library/classes
   #:coalton-library/functions)
  (:export
   ;; Core continuation operations (syntax)
   ;; Note: reset, shift, call/cc are syntax forms exported from coalton package

   ;; Continuation type
   #:Cont
   #:ContFn
   #:Prompt
   #:MkPrompt

   ;; CPS utilities
   #:run-cont
   #:cont-pure
   #:cont-bind
   #:cont-map
   #:cont-ap

   ;; Prompt/delimiter utilities
   #:with-prompt
   #:abort-to-prompt

   ;; Control operators
   #:control
   #:control0
   #:shift0

   ;; CPS transformation utilities
   #:cps
   #:reflect
   #:reify

   ;; Advanced continuation operations
   #:call-with-continuation
   #:cont-callcc
   #:cont-reset
   #:cont-shift

   ;; CPS List Operations
   #:cps-map
   #:cps-for-each
   #:cps-fold
   #:cps-fold-right
   #:cps-filter
   #:cps-find

   ;; CPS Optional Operations
   #:cps-map-optional
   #:cps-and-then

   ;; CPS Result Operations
   #:cps-map-ok
   #:cps-map-err
   #:cps-and-then-result

   ;; CPS Function Combinators
   #:cps-compose
   #:cps-flip
   #:cps-const
   #:cps-id

   ;; CPS Numeric Operations
   #:cps-sum
   #:cps-product

   ;; CPS Boolean Operations
   #:cps-all
   #:cps-any

   ;; CPS Traversable-like Operations
   #:cps-sequence
   #:cps-sequence_
   #:cps-replicate

   ;; CPS Iteration
   #:cps-iterate
   #:cps-unfold

   ;; CPS Exception-like Control
   #:cps-catch
   #:cps-throw
   #:cps-try))

(in-package #:coalton-library/continuations)
