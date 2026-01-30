;;;; async-runtime-tests.lisp
;;;;
;;;; Tests for the trampoline-based async effect runtime

(cl:in-package #:coalton-native-tests)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Basic Step/Continuation Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare step-pure-test (Unit -> (Result String IFix)))
  (define (step-pure-test)
    "Test that cont-pure creates a completed step."
    (runtime:run (runtime:cont-pure 42)))

  (declare step-fail-test (Unit -> (Result String IFix)))
  (define (step-fail-test)
    "Test that cont-fail creates a failed step."
    (runtime:run (runtime:cont-fail "test error")))

  (declare step-bind-test (Unit -> (Result String IFix)))
  (define (step-bind-test)
    "Test monadic bind on steps."
    (runtime:run
     (>>= (runtime:cont-pure 10)
          (fn (x) (runtime:cont-pure (* x 2))))))

  (declare step-chain-test (Unit -> (Result String IFix)))
  (define (step-chain-test)
    "Test chaining multiple steps."
    (runtime:run
     (>>= (runtime:cont-pure 1)
          (fn (a)
            (>>= (runtime:cont-pure 2)
                 (fn (b)
                   (>>= (runtime:cont-pure 3)
                        (fn (c) (runtime:cont-pure (+ a (+ b c)))))))))))

  (declare step-map-test (Unit -> (Result String IFix)))
  (define (step-map-test)
    "Test mapping over steps."
    (runtime:run
     (map (fn (x) (* x 3))
          (runtime:cont-pure 7)))))

(define-test test-step-pure ()
  (match (step-pure-test)
    ((Ok v) (is (== v 42)))
    ((Err _) (is False))))

(define-test test-step-fail ()
  (match (step-fail-test)
    ((Ok _) (is False))
    ((Err msg) (is (== msg "test error")))))

(define-test test-step-bind ()
  (match (step-bind-test)
    ((Ok v) (is (== v 20)))
    ((Err _) (is False))))

(define-test test-step-chain ()
  (match (step-chain-test)
    ((Ok v) (is (== v 6)))
    ((Err _) (is False))))

(define-test test-step-map ()
  (match (step-map-test)
    ((Ok v) (is (== v 21)))
    ((Err _) (is False))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Trampoline/Stack Safety Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare deep-recursion-step (UFix -> (runtime:Step UFix)))
  (define (deep-recursion-step n)
    "Create a deeply nested step computation."
    (if (<= n 0)
        (runtime:cont-pure 0)
        ;; This would overflow the stack without trampolining
        (>>= (runtime:cont-pure 1)
             (fn (one)
               (>>= (deep-recursion-step (- n 1))
                    (fn (rest) (runtime:cont-pure (+ one rest))))))))

  (declare deep-recursion-test (Unit -> (Result String UFix)))
  (define (deep-recursion-test)
    "Test that deep recursion doesn't overflow the stack."
    (runtime:run (deep-recursion-step 10000)))

  (declare step-repeat-test (Unit -> (Result String UFix)))
  (define (step-repeat-test)
    "Test step-repeat for many iterations."
    (let ((counter (cell:new (the UFix 0))))
      (runtime:run
       (>>= (runtime:step-repeat 1000
              (runtime:StepContinue
               (fn ()
                 (progn
                   (cell:increment! counter)
                   (runtime:StepDone Unit)))))
            (fn (_) (runtime:cont-pure (cell:read counter))))))))

(define-test test-deep-recursion ()
  (match (deep-recursion-test)
    ((Ok v) (is (== v 10000)))
    ((Err msg) (is False))))

(define-test test-step-repeat ()
  (match (step-repeat-test)
    ((Ok v) (is (== v 1000)))
    ((Err _) (is False))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Yield Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare yield-test (Unit -> (Result String IFix)))
  (define (yield-test)
    "Test explicit yielding."
    (runtime:run
     (>>= (runtime:yield-now)
          (fn (_)
            (>>= (runtime:yield-now)
                 (fn (_) (runtime:cont-pure 42)))))))

  (declare yield-loop-test (Unit -> (Result String UFix)))
  (define (yield-loop-test)
    "Test yield-loop combinator."
    (let ((counter (cell:new (the UFix 0))))
      (runtime:run
       (>>= (runtime:yield-loop 5
              (fn ()
                (progn
                  (cell:increment! counter)
                  (runtime:StepDone Unit))))
            (fn (_) (runtime:cont-pure (cell:read counter))))))))

(define-test test-yield ()
  (match (yield-test)
    ((Ok v) (is (== v 42)))
    ((Err _) (is False))))

(define-test test-yield-loop ()
  (match (yield-loop-test)
    ((Ok v) (is (== v 1)))  ;; Body executes once after 5 yields
    ((Err _) (is False))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect Handler Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare state-handler-test (Unit -> (Result String (Tuple (Tuple IFix IFix) IFix))))
  (define (state-handler-test)
    "Test state effect handler in runtime."
    (runtime:run
     (runtime:run-state-step 0
       (>>= (runtime:perform-state-get)
            (fn (initial)
              (>>= (runtime:perform-state-put 10)
                   (fn (_)
                     (>>= (runtime:perform-state-get)
                          (fn (final)
                            (runtime:cont-pure (Tuple initial final)))))))))))

  (declare reader-handler-test (Unit -> (Result String IFix)))
  (define (reader-handler-test)
    "Test reader effect handler in runtime."
    (runtime:run
     (runtime:run-reader-step 42
       (runtime:perform-reader-ask))))

  (declare writer-handler-test (Unit -> (Result String (Tuple String (List String)))))
  (define (writer-handler-test)
    "Test writer effect handler in runtime."
    (runtime:run
     (runtime:run-writer-step
      (>>= (runtime:perform-writer-tell "hello")
           (fn (_)
             (>>= (runtime:perform-writer-tell "world")
                  (fn (_) (runtime:cont-pure "done")))))))))

(define-test test-runtime-state-handler ()
  (match (state-handler-test)
    ((Ok (Tuple (Tuple initial final) _state))
     (progn
       (is (== initial 0))
       (is (== final 10))))
    ((Err _) (is False))))

(define-test test-runtime-reader-handler ()
  (match (reader-handler-test)
    ((Ok v) (is (== v 42)))
    ((Err _) (is False))))

(define-test test-runtime-writer-handler ()
  (match (writer-handler-test)
    ((Ok (Tuple result log))
     (progn
       (is (== result "done"))
       (is (== (length log) 2))))
    ((Err _) (is False))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Error Handling Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare try-success-test (Unit -> (Result String (Result String IFix))))
  (define (try-success-test)
    "Test try-step on successful computation."
    (runtime:run
     (runtime:try-step (runtime:cont-pure 42))))

  (declare try-failure-test (Unit -> (Result String (Result String IFix))))
  (define (try-failure-test)
    "Test try-step on failing computation."
    (runtime:run
     (runtime:try-step (runtime:cont-fail "error"))))

  (declare catch-success-test (Unit -> (Result String IFix)))
  (define (catch-success-test)
    "Test catch-step with successful computation."
    (runtime:run
     (runtime:catch-step (runtime:cont-pure 42)
                         (fn (v) (runtime:cont-pure v))
                         (fn (_) (runtime:cont-pure 0)))))

  (declare catch-failure-test (Unit -> (Result String IFix)))
  (define (catch-failure-test)
    "Test catch-step with failing computation."
    (runtime:run
     (runtime:catch-step (runtime:cont-fail "error")
                         (fn (v) (runtime:cont-pure v))
                         (fn (_) (runtime:cont-pure -1))))))

(define-test test-try-success ()
  (match (try-success-test)
    ((Ok (Ok v)) (is (== v 42)))
    (_ (is False))))

(define-test test-try-failure ()
  (match (try-failure-test)
    ((Ok (Err msg)) (is (== msg "error")))
    (_ (is False))))

(define-test test-catch-success ()
  (match (catch-success-test)
    ((Ok v) (is (== v 42)))
    ((Err _) (is False))))

(define-test test-catch-failure ()
  (match (catch-failure-test)
    ((Ok v) (is (== v -1)))
    ((Err _) (is False))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Fiber Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare fiber-creation-test (Unit -> Boolean))
  (define (fiber-creation-test)
    "Test fiber creation."
    (let ((fiber (runtime:make-fiber (runtime:cont-pure 42))))
      (== (runtime:fiber-status fiber) runtime:FiberPending)))

  (declare fiber-id-uniqueness-test (Unit -> Boolean))
  (define (fiber-id-uniqueness-test)
    "Test that fiber IDs are unique."
    (let ((f1 (runtime:make-fiber (runtime:cont-pure 1))))
      (let ((f2 (runtime:make-fiber (runtime:cont-pure 2))))
        (not (== (runtime:fiber-id f1) (runtime:fiber-id f2)))))))

(define-test test-fiber-creation ()
  (is (fiber-creation-test)))

(define-test test-fiber-id-uniqueness ()
  (is (fiber-id-uniqueness-test)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Scheduler Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare scheduler-basic-test (Unit -> (Optional IFix)))
  (define (scheduler-basic-test)
    "Test basic scheduler operation."
    (let ((sched (runtime:make-scheduler)))
      (let ((fiber (runtime:scheduler-spawn! sched (runtime:cont-pure 42))))
        (progn
          (runtime:scheduler-run! sched)
          (runtime:fiber-result fiber)))))

  (declare scheduler-multiple-fibers-test (Unit -> (List (Optional IFix))))
  (define (scheduler-multiple-fibers-test)
    "Test scheduler with multiple fibers."
    (let ((sched (runtime:make-scheduler)))
      (let ((f1 (runtime:scheduler-spawn! sched (runtime:cont-pure 1))))
        (let ((f2 (runtime:scheduler-spawn! sched (runtime:cont-pure 2))))
          (let ((f3 (runtime:scheduler-spawn! sched (runtime:cont-pure 3))))
            (progn
              (runtime:scheduler-run! sched)
              (Cons (runtime:fiber-result f1)
                    (Cons (runtime:fiber-result f2)
                          (Cons (runtime:fiber-result f3) Nil)))))))))

  (declare scheduler-yield-threshold-test (Unit -> UFix))
  (define (scheduler-yield-threshold-test)
    "Test scheduler yield threshold configuration."
    (let ((sched (runtime:make-scheduler-with-threshold 100)))
      (runtime:scheduler-yield-threshold sched))))

(define-test test-scheduler-basic ()
  (match (scheduler-basic-test)
    ((Some v) (is (== v 42)))
    ((None) (is False))))

(define-test test-scheduler-multiple-fibers ()
  (let ((results (scheduler-multiple-fibers-test)))
    (progn
      (is (== (length results) 3))
      (is (== (head results) (Some (Some 1)))))))

(define-test test-scheduler-yield-threshold ()
  (is (== (scheduler-yield-threshold-test) 100)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Interruption Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare interruption-test (Unit -> Boolean))
  (define (interruption-test)
    "Test fiber interruption."
    (let ((fiber (runtime:make-fiber (runtime:cont-pure 42))))
      (progn
        (runtime:fiber-interrupt! fiber)
        (runtime:fiber-interrupted? fiber)))))

(define-test test-interruption ()
  (is (interruption-test)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Async Helper Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare async-for-each-test (Unit -> (Result String UFix)))
  (define (async-for-each-test)
    "Test async-for-each."
    (let ((counter (cell:new (the UFix 0))))
      (runtime:run
       (>>= (runtime:async-for-each
             (fn (x)
               (runtime:StepContinue
                (fn ()
                  (progn
                    (cell:write! counter (+ (cell:read counter) x))
                    (runtime:StepDone Unit)))))
             (make-list 1 2 3 4 5))
            (fn (_) (runtime:cont-pure (cell:read counter)))))))

  (declare async-map-test (Unit -> (Result String (List IFix))))
  (define (async-map-test)
    "Test async-map."
    (runtime:run
     (runtime:async-map
      (fn (x) (runtime:cont-pure (* x 2)))
      (make-list 1 2 3)))))

(define-test test-async-for-each ()
  (match (async-for-each-test)
    ((Ok v) (is (== v 15)))  ;; 1+2+3+4+5
    ((Err _) (is False))))

(define-test test-async-map ()
  (match (async-map-test)
    ((Ok lst)
     (progn
       (is (== (length lst) 3))
       (is (== (head lst) (Some 2)))))
    ((Err _) (is False))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Step Combinator Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare step-when-true-test (Unit -> (Result String UFix)))
  (define (step-when-true-test)
    "Test step-when with true condition."
    (let ((counter (cell:new (the UFix 0))))
      (runtime:run
       (>>= (runtime:step-when True
              (runtime:StepContinue
               (fn ()
                 (progn
                   (cell:increment! counter)
                   (runtime:StepDone Unit)))))
            (fn (_) (runtime:cont-pure (cell:read counter)))))))

  (declare step-when-false-test (Unit -> (Result String UFix)))
  (define (step-when-false-test)
    "Test step-when with false condition."
    (let ((counter (cell:new (the UFix 0))))
      (runtime:run
       (>>= (runtime:step-when False
              (runtime:StepContinue
               (fn ()
                 (progn
                   (cell:increment! counter)
                   (runtime:StepDone Unit)))))
            (fn (_) (runtime:cont-pure (cell:read counter)))))))

  (declare step-fold-test (Unit -> (Result String IFix)))
  (define (step-fold-test)
    "Test step-fold."
    (runtime:run
     (runtime:step-fold
      (fn (acc x) (runtime:cont-pure (+ acc x)))
      0
      (make-list 1 2 3 4 5)))))

(define-test test-step-when-true ()
  (match (step-when-true-test)
    ((Ok v) (is (== v 1)))
    ((Err _) (is False))))

(define-test test-step-when-false ()
  (match (step-when-false-test)
    ((Ok v) (is (== v 0)))
    ((Err _) (is False))))

(define-test test-step-fold ()
  (match (step-fold-test)
    ((Ok v) (is (== v 15)))
    ((Err _) (is False))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Handler Composition Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare combined-effects-test (Unit -> (Result String (Tuple (Tuple (Tuple IFix IFix) IFix) (List String)))))
  (define (combined-effects-test)
    "Test combining state and writer effects."
    (runtime:run
     (runtime:run-writer-step
      (runtime:run-state-step 0
       (>>= (runtime:perform-state-get)
            (fn (initial)
              (>>= (runtime:perform-writer-tell "got initial")
                   (fn (_)
                     (>>= (runtime:perform-state-put 42)
                          (fn (_)
                            (>>= (runtime:perform-writer-tell "set to 42")
                                 (fn (_)
                                   (>>= (runtime:perform-state-get)
                                        (fn (final)
                                          (runtime:cont-pure (Tuple initial final)))))))))))))))))

(define-test test-combined-effects ()
  (match (combined-effects-test)
    ((Ok (Tuple (Tuple (Tuple initial final) _state) log))
     (progn
       (is (== initial 0))
       (is (== final 42))
       (is (== (length log) 2))))
    ((Err _) (is False))))
