;;;; Runtime package definition for trampoline-based async effect system
;;;;
;;;; This package provides:
;;;; - Trampolined continuation types for stack-safe execution
;;;; - Fiber-based lightweight virtual threads
;;;; - A cooperative scheduler for fiber execution
;;;; - Integration with cl-async/libuv for async I/O
;;;; - Structured concurrency primitives

(defpackage #:coalton-library/effects/runtime
  (:documentation "Trampoline-based async effect runtime for Coalton.

This package implements a stack-safe, cooperative runtime for executing
effectful computations. Inspired by TypeScript's Effect library.

Key components:
- Continuations: CPS-style suspended computations
- Fibers: Lightweight virtual threads with structured concurrency
- Scheduler: Round-robin fiber scheduler with yield threshold
- Async I/O: Integration with cl-async/libuv event loop")
  (:use
   #:coalton
   #:coalton-library/builtin
   #:coalton-library/classes
   #:coalton-library/functions)
  (:import-from #:coalton-library/symbol
   #:Symbol)
  (:local-nicknames
   (#:cell #:coalton-library/cell)
   (#:list #:coalton-library/list)
   (#:iter #:coalton-library/iterator)
   (#:hash #:coalton-library/hashtable)
   (#:result #:coalton-library/result))
  (:export
   ;; Continuation types
   #:Step
   #:StepContinue
   #:StepYield
   #:StepPerform
   #:StepDone
   #:StepFail
   #:StepAsync

   ;; Continuation constructors and runners
   #:cont-pure
   #:cont-fail
   #:cont-yield
   #:cont-perform
   #:cont-async
   #:cont-bind
   #:cont-map
   #:cont-ap
   #:run-sync
   #:run
   #:run!
   #:run-with-scheduler

   ;; Effect operation type
   #:EffectOp
   #:make-effect-op
   #:effect-op-tag
   #:effect-op-value

   ;; Step builders
   #:step
   #:step-lift
   #:step-when
   #:step-unless
   #:step-repeat
   #:step-while
   #:step-for-each
   #:step-fold
   #:step-trace
   #:step-trace-value
   #:step-from-thunk
   #:step-protect

   ;; Effect performers
   #:perform-state-get
   #:perform-state-put
   #:perform-reader-ask
   #:perform-writer-tell
   #:perform-fail

   ;; Effect operations
   #:state-get-op
   #:state-put-op
   #:reader-ask-op
   #:writer-tell-op
   #:fail-op

   ;; Effect handlers
   #:EffectHandler
   #:make-handler
   #:make-effect-handler
   #:make-resuming-handler
   #:make-state-handler
   #:handler-tag
   #:apply-handler
   #:with-handler
   #:with-handlers
   #:run-state-step
   #:run-reader-step
   #:run-writer-step
   #:catch-step
   #:try-step

   ;; Fiber types and operations
   #:FiberStatus
   #:FiberPending
   #:FiberRunning
   #:FiberSuspended
   #:FiberDone
   #:FiberFailed
   #:FiberInterrupted

   #:Fiber
   #:make-fiber
   #:make-child-fiber
   #:fiber-id
   #:fiber-status
   #:fiber-set-status!
   #:fiber-interrupt!
   #:fiber-interrupted?
   #:fiber-done?
   #:fiber-result
   #:fiber-error
   #:fiber-step!

   ;; Scheduler operations
   #:Scheduler
   #:make-scheduler
   #:make-scheduler-with-threshold
   #:scheduler-spawn!
   #:scheduler-spawn-child!
   #:scheduler-run!
   #:scheduler-step!
   #:scheduler-stop!
   #:scheduler-yield-threshold
   #:scheduler-set-yield-threshold!
   #:scheduler-running?
   #:scheduler-current
   #:scheduler-ready-count
   #:scheduler-suspended-count
   #:scheduler-empty?
   #:scheduler-enqueue!
   #:scheduler-dequeue!
   #:scheduler-suspend!
   #:scheduler-resume!
   #:scheduler-add-handler!
   #:scheduler-find-handler
   #:default-yield-threshold

   ;; Structured concurrency
   #:fork
   #:await-fiber
   #:await-fiber-unwrap
   #:race
   #:all-fibers
   #:with-scope

   ;; Async I/O integration
   #:with-async-runtime
   #:delay
   #:delay-seconds
   #:async-callback
   #:async-callback-with-error
   #:poll-until
   #:with-timeout
   #:yield-now
   #:yield-loop
   #:async-for-each
   #:async-map

   ;; Configuration
   #:*default-yield-threshold*))

(in-package #:coalton-library/effects/runtime)
