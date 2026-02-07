;;;; effects-library-tests.lisp
;;;;
;;;; Integration tests for the algebraic effects library (State, Reader, Writer)
;;;;

(in-package #:coalton-native-tests)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; State Effect Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  ;; Test helper functions for State effect
  ;; run-state returns (Tuple result final-state)
  (declare state-counter-test (Unit -> (Tuple (Tuple IFix IFix) IFix)))
  (define (state-counter-test)
    "Test State effect: increment a counter three times and return the count."
    (effects:run-state 0
      (fn ()
        (let ((initial (effects:get)))
          (effects:put (+ initial 1))
          (effects:put (+ (effects:get) 1))
          (effects:put (+ (effects:get) 1))
          (Tuple initial (effects:get))))))

  (declare state-modify-test (Unit -> (Tuple (Tuple IFix IFix) IFix)))
  (define (state-modify-test)
    "Test State effect: use modify to update state."
    (effects:run-state 10
      (fn ()
        (let ((before (effects:get)))
          (effects:modify (fn (x) (* x 2)))
          (Tuple before (effects:get))))))

  (declare state-nested-test (Unit -> IFix))
  (define (state-nested-test)
    "Test nested State effect handlers."
    (match (effects:run-state 0
             (fn ()
               (effects:put 5)
               (match (effects:run-state 100
                        (fn ()
                          (effects:put 200)
                          (effects:get)))
                 ((Tuple inner-result _inner-state)
                  inner-result))))
      ((Tuple result _outer-state)
       result)))

  (declare state-return-result (Unit -> IFix))
  (define (state-return-result)
    "Test that State effect returns the computation result correctly."
    (match (effects:run-state 0
             (fn ()
               (effects:put 42)
               (+ (effects:get) 10)))
      ((Tuple result _)
       result))))

(define-test test-state-counter ()
  (let ((result (state-counter-test)))
    (match result
      ((Tuple (Tuple initial final) _state)
       (is (== initial 0))
       (is (== final 3))))))

(define-test test-state-modify ()
  (let ((result (state-modify-test)))
    (match result
      ((Tuple (Tuple before after) _state)
       (is (== before 10))
       (is (== after 20))))))

(define-test test-state-nested ()
  (is (== (state-nested-test) 200)))

(define-test test-state-return-result ()
  (is (== (state-return-result) 52)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Reader Effect Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  ;; run-reader returns just the result (no wrapping tuple)
  (declare reader-basic-test (Unit -> IFix))
  (define (reader-basic-test)
    "Test basic Reader effect: get environment and return it."
    (effects:run-reader 42
      (fn ()
        (effects:ask))))

  (declare reader-asks-test (Unit -> IFix))
  (define (reader-asks-test)
    "Test Reader effect with asks function."
    (effects:run-reader 10
      (fn ()
        (effects:asks (fn (x) (* x 3))))))

  (declare reader-local-test (Unit -> (Tuple IFix IFix)))
  (define (reader-local-test)
    "Test Reader effect with local modification."
    (effects:run-reader 5
      (fn ()
        (let ((outer (effects:ask)))
          (let ((inner (effects:local (fn (x) (* x 10))
                         (fn ()
                           (effects:ask)))))
            (Tuple outer inner))))))

  (declare reader-nested-test (Unit -> IFix))
  (define (reader-nested-test)
    "Test nested Reader effect handlers."
    (effects:run-reader 1
      (fn ()
        (let ((outer (effects:ask)))
          (+ outer (effects:run-reader 100
                     (fn () (effects:ask)))))))))

(define-test test-reader-basic ()
  (is (== (reader-basic-test) 42)))

(define-test test-reader-asks ()
  (is (== (reader-asks-test) 30)))

(define-test test-reader-local ()
  (let ((result (reader-local-test)))
    (match result
      ((Tuple outer inner)
       (is (== outer 5))
       (is (== inner 50))))))

(define-test test-reader-nested ()
  (is (== (reader-nested-test) 101)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Writer Effect Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  ;; run-writer returns (Tuple result (List output))
  (declare writer-basic-test (Unit -> (Tuple IFix (List IFix))))
  (define (writer-basic-test)
    "Test basic Writer effect: tell some values and return result."
    (effects:run-writer
      (fn ()
        (effects:tell 1)
        (effects:tell 2)
        (effects:tell 3)
        42)))

  (declare writer-listen-test (Unit -> (Tuple UFix (List IFix))))
  (define (writer-listen-test)
    "Test Writer effect with listen function."
    (effects:run-writer
      (fn ()
        (effects:tell 0)
        (match (effects:listen
                 (fn ()
                   (effects:tell 1)
                   (effects:tell 2)
                   (the UFix 10)))
          ((Tuple inner-result inner-log)
           (effects:tell 3)
           (+ inner-result (length inner-log)))))))

  (declare writer-nested-test (Unit -> (Tuple IFix (List IFix))))
  (define (writer-nested-test)
    "Test nested Writer effect handlers."
    (effects:run-writer
      (fn ()
        (effects:tell 1)
        (match (effects:run-writer
                 (fn ()
                   (effects:tell 100)
                   (effects:tell 200)
                   10))
          ((Tuple inner-result _inner-log)
           (effects:tell 2)
           inner-result))))))

(define-test test-writer-basic ()
  (let ((result (writer-basic-test)))
    (match result
      ((Tuple value log)
       (is (== value 42))
       (is (== (length log) 3))
       (is (== (head log) (Some 1)))))))

(define-test test-writer-listen ()
  (let ((result (writer-listen-test)))
    (match result
      ((Tuple value log)
       ;; 10 + 2 (length of inner log)
       (is (== value (the UFix 12)))
       ;; Log should have 0, 3 (outer tells)
       (is (== (length log) 2))))))

(define-test test-writer-nested ()
  (let ((result (writer-nested-test)))
    (match result
      ((Tuple value log)
       (is (== value 10))
       ;; Outer log should have 1, 2
       (is (== (length log) 2))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Combined Effect Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare state-reader-combined-test (Unit -> (Tuple IFix IFix)))
  (define (state-reader-combined-test)
    "Test combining State and Reader effects."
    (effects:run-reader 10
      (fn ()
        (match (effects:run-state 0
                 (fn ()
                   (let ((env (effects:ask)))
                     (effects:put env)
                     (effects:modify (fn (x) (+ x 5)))
                     (effects:get))))
          ((Tuple result state)
           (Tuple result state))))))

  (declare reader-writer-combined-test (Unit -> (Tuple String (List String))))
  (define (reader-writer-combined-test)
    "Test combining Reader and Writer effects."
    (effects:run-reader "Hello"
      (fn ()
        (effects:run-writer
          (fn ()
            (effects:tell (effects:ask))
            (effects:tell " World")
            "Result"))))))

(define-test test-state-reader-combined ()
  (let ((result (state-reader-combined-test)))
    (match result
      ((Tuple value state)
       (is (== value 15))
       (is (== state 15))))))

(define-test test-reader-writer-combined ()
  (let ((result (reader-writer-combined-test)))
    (match result
      ((Tuple value log)
       (is (== value "Result"))
       (is (== (length log) 2))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect Edge Case Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare state-zero-state-test (Unit -> (Tuple Unit Unit)))
  (define (state-zero-state-test)
    "Test State effect with Unit as state type."
    (effects:run-state Unit
      (fn ()
        (effects:get))))

  (declare reader-unit-env-test (Unit -> Unit))
  (define (reader-unit-env-test)
    "Test Reader effect with Unit as environment."
    (effects:run-reader Unit
      (fn ()
        (effects:ask))))

  (declare writer-empty-test (Unit -> (Tuple IFix (List IFix))))
  (define (writer-empty-test)
    "Test Writer effect with no tells."
    (effects:run-writer
      (fn ()
        42))))

(define-test test-state-zero-state ()
  (let ((result (state-zero-state-test)))
    (match result
      ((Tuple value state)
       (is (== value Unit))
       (is (== state Unit))))))

(define-test test-reader-unit-env ()
  (is (== (reader-unit-env-test) Unit)))

(define-test test-writer-empty ()
  (let ((result (writer-empty-test)))
    (match result
      ((Tuple value log)
       (is (== value 42))
       (is (== (length log) 0))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; State Effect Complex Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(coalton-toplevel
  (declare state-accumulator-test (Unit -> (Tuple UFix (List IFix))))
  (define (state-accumulator-test)
    "Test State effect as an accumulator."
    (effects:run-state (the (List IFix) Nil)
      (fn ()
        (effects:modify (fn (xs) (Cons 1 xs)))
        (effects:modify (fn (xs) (Cons 2 xs)))
        (effects:modify (fn (xs) (Cons 3 xs)))
        (length (effects:get)))))

  (declare state-multiple-gets-test (Unit -> (Tuple IFix IFix)))
  (define (state-multiple-gets-test)
    "Test multiple State.get calls."
    (effects:run-state 42
      (fn ()
        (let ((a (effects:get)))
          (let ((b (effects:get)))
            (let ((c (effects:get)))
              (+ a (+ b c)))))))))

(define-test test-state-accumulator ()
  (let ((result (state-accumulator-test)))
    (match result
      ((Tuple len final-state)
       (is (== len 3))
       (is (== (length final-state) 3))))))

(define-test test-state-multiple-gets ()
  (let ((result (state-multiple-gets-test)))
    (match result
      ((Tuple value state)
       (is (== value 126))  ; 42 + 42 + 42
       (is (== state 42))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Unhandled Effect Tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; CL-level test: verify performing an effect without a handler raises an error
(fiasco:deftest (test-unhandled-effect
                 :in fiasco-suites::coalton-tests) ()
  (fiasco:signals cl:simple-error
    (coalton:coalton (effects:get Unit))))
