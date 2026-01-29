;;;; effects-standalone-tests.lisp
;;;;
;;;; Standalone unit tests for effect system infrastructure
;;;; that do not require the Coalton library to be loaded.
;;;;
;;;; These tests cover the types-sub.lisp and simplify.lisp effect functionality
;;;; which is part of the coalton-compiler system.

(defpackage #:coalton-effects-standalone-tests
  (:use #:cl)
  (:local-nicknames
   (#:tc #:coalton-impl/typechecker)))

(in-package #:coalton-effects-standalone-tests)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test utilities
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar *test-count* 0)
(defvar *pass-count* 0)
(defvar *fail-count* 0)

(defmacro deftest (name &body body)
  `(defun ,name ()
     (incf *test-count*)
     (handler-case
         (progn ,@body
                (incf *pass-count*)
                (format t "~&PASS: ~A~%" ',name))
       (error (e)
         (incf *fail-count*)
         (format t "~&FAIL: ~A - ~A~%" ',name e)))))

(defmacro is (form)
  `(unless ,form
     (error "Assertion failed: ~S" ',form)))

(defun run-all-tests ()
  (setf *test-count* 0 *pass-count* 0 *fail-count* 0)
  (format t "~&Running effect system standalone tests...~%")

  ;; ty-effecting-fn tests
  (test-ty-effecting-fn-creation)
  (test-ty-effecting-fn-with-effect)
  (test-ty-effecting-fn-kind)
  (test-ty-effecting-fn-equality)
  (test-ty-effecting-fn-type-variables)
  (test-ty-effecting-fn-with-effect-union)

  ;; ty-effect-op tests
  (test-ty-effect-op-creation)
  (test-ty-effect-op-kind)
  (test-ty-effect-op-equality)
  (test-ty-effect-op-type-variables)

  ;; Effect row predicates tests
  (test-pure-effect-p)
  (test-effect-row-p)
  (test-make-exception-effect)

  ;; Effect row simplification tests
  (test-simplify-effect-row-pure)
  (test-simplify-effect-row-single)
  (test-simplify-effect-row-with-pure)
  (test-simplify-effect-row-dedup)
  (test-simplify-type-effecting-fn)
  (test-simplify-type-effect-op)

  ;; Type printing tests
  (test-print-effecting-fn)
  (test-print-effect-op)

  ;; Polarity tracking tests
  (test-collect-type-occurrences-effecting-fn)
  (test-collect-type-occurrences-effect-op)

  ;; Substitution tests
  (test-substitute-tyvar-sub-effecting-fn)
  (test-substitute-tyvar-sub-effect-op)

  (format t "~&~%Results: ~D tests, ~D passed, ~D failed~%"
          *test-count* *pass-count* *fail-count*)
  (zerop *fail-count*))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; ty-effecting-fn tests (types-sub.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-ty-effecting-fn-creation
  (let ((eff-fn (tc:make-ty-effecting-fn
                 :domain tc:*integer-type*
                 :codomain tc:*string-type*
                 :effects tc:+ty-bot+)))
    (is (tc:ty-effecting-fn-p eff-fn))
    (is (tc:ty= (tc:ty-effecting-fn-domain eff-fn) tc:*integer-type*))
    (is (tc:ty= (tc:ty-effecting-fn-codomain eff-fn) tc:*string-type*))
    (is (tc:ty-bot-p (tc:ty-effecting-fn-effects eff-fn)))))

(deftest test-ty-effecting-fn-with-effect
  (let* ((state-effect (tc:make-ty-effect-op
                        :name 'state.get
                        :request-type tc:*unit-type*
                        :response-type tc:*integer-type*))
         (eff-fn (tc:make-ty-effecting-fn
                  :domain tc:*unit-type*
                  :codomain tc:*integer-type*
                  :effects state-effect)))
    (is (tc:ty-effecting-fn-p eff-fn))
    (is (tc:ty-effect-op-p (tc:ty-effecting-fn-effects eff-fn)))
    (is (eq 'state.get
            (tc:ty-effect-op-name (tc:ty-effecting-fn-effects eff-fn))))))

(deftest test-ty-effecting-fn-kind
  (let ((eff-fn (tc:make-ty-effecting-fn
                 :domain tc:*integer-type*
                 :codomain tc:*string-type*
                 :effects tc:+ty-bot+)))
    (is (tc:kstar-p (tc:kind-of eff-fn)))))

(deftest test-ty-effecting-fn-equality
  (let ((eff-fn-1 (tc:make-ty-effecting-fn
                   :domain tc:*integer-type*
                   :codomain tc:*string-type*
                   :effects tc:+ty-bot+))
        (eff-fn-2 (tc:make-ty-effecting-fn
                   :domain tc:*integer-type*
                   :codomain tc:*string-type*
                   :effects tc:+ty-bot+))
        (eff-fn-3 (tc:make-ty-effecting-fn
                   :domain tc:*string-type*
                   :codomain tc:*string-type*
                   :effects tc:+ty-bot+)))
    (is (tc:ty= eff-fn-1 eff-fn-2))
    (is (not (tc:ty= eff-fn-1 eff-fn-3)))))

(deftest test-ty-effecting-fn-type-variables
  (tc:reset-levels)
  (let* ((var (tc:make-variable-at-level))
         (eff-fn (tc:make-ty-effecting-fn
                  :domain var
                  :codomain tc:*string-type*
                  :effects tc:+ty-bot+)))
    (is (member var (tc:type-variables eff-fn)))))

(deftest test-ty-effecting-fn-with-effect-union
  (let* ((effect1 (tc:make-ty-effect-op
                   :name 'state.get
                   :request-type tc:*unit-type*
                   :response-type tc:*integer-type*))
         (effect2 (tc:make-ty-effect-op
                   :name 'reader.ask
                   :request-type tc:*unit-type*
                   :response-type tc:*string-type*))
         (effects (tc:make-ty-union :members (list effect1 effect2)))
         (eff-fn (tc:make-ty-effecting-fn
                  :domain tc:*unit-type*
                  :codomain tc:*integer-type*
                  :effects effects)))
    (is (tc:ty-effecting-fn-p eff-fn))
    (is (tc:ty-union-p (tc:ty-effecting-fn-effects eff-fn)))
    (is (= 2 (length (tc:ty-union-members (tc:ty-effecting-fn-effects eff-fn)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; ty-effect-op tests (types-sub.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-ty-effect-op-creation
  (let ((effect-op (tc:make-ty-effect-op
                    :name 'state.get
                    :request-type tc:*unit-type*
                    :response-type tc:*integer-type*)))
    (is (tc:ty-effect-op-p effect-op))
    (is (eq 'state.get (tc:ty-effect-op-name effect-op)))
    (is (tc:ty= (tc:ty-effect-op-request-type effect-op) tc:*unit-type*))
    (is (tc:ty= (tc:ty-effect-op-response-type effect-op) tc:*integer-type*))))

(deftest test-ty-effect-op-kind
  (let ((effect-op (tc:make-ty-effect-op
                    :name 'test-effect
                    :request-type tc:*unit-type*
                    :response-type tc:*integer-type*)))
    (is (tc:kstar-p (tc:kind-of effect-op)))))

(deftest test-ty-effect-op-equality
  (let ((op1 (tc:make-ty-effect-op
              :name 'test-effect
              :request-type tc:*unit-type*
              :response-type tc:*integer-type*))
        (op2 (tc:make-ty-effect-op
              :name 'test-effect
              :request-type tc:*unit-type*
              :response-type tc:*integer-type*))
        (op3 (tc:make-ty-effect-op
              :name 'other-effect
              :request-type tc:*unit-type*
              :response-type tc:*integer-type*)))
    (is (tc:ty= op1 op2))
    (is (not (tc:ty= op1 op3)))))

(deftest test-ty-effect-op-type-variables
  (tc:reset-levels)
  (let* ((var (tc:make-variable-at-level))
         (effect-op (tc:make-ty-effect-op
                     :name 'test-effect
                     :request-type tc:*unit-type*
                     :response-type var)))
    (is (member var (tc:type-variables effect-op)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect row predicates tests (types-sub.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-pure-effect-p
  (is (tc:pure-effect-p tc:+ty-bot+))
  (is (not (tc:pure-effect-p tc:+ty-top+)))
  (is (not (tc:pure-effect-p (tc:make-ty-effect-op
                              :name 'test
                              :request-type tc:*unit-type*
                              :response-type tc:*unit-type*)))))

(deftest test-effect-row-p
  ;; Pure is valid effect row
  (is (tc:effect-row-p tc:+ty-bot+))
  ;; Single effect op is valid
  (is (tc:effect-row-p (tc:make-ty-effect-op
                        :name 'test
                        :request-type tc:*unit-type*
                        :response-type tc:*unit-type*)))
  ;; Union of effects is valid
  (let ((effect-union (tc:make-ty-union
                       :members (list
                                 (tc:make-ty-effect-op
                                  :name 'effect1
                                  :request-type tc:*unit-type*
                                  :response-type tc:*unit-type*)
                                 (tc:make-ty-effect-op
                                  :name 'effect2
                                  :request-type tc:*unit-type*
                                  :response-type tc:*unit-type*)))))
    (is (tc:effect-row-p effect-union)))
  ;; Type variable is valid effect row
  (tc:reset-levels)
  (is (tc:effect-row-p (tc:make-variable-at-level))))

(deftest test-make-exception-effect
  (let ((exception (tc:make-exception-effect 'parse-error tc:*string-type*)))
    (is (tc:ty-effect-op-p exception))
    (is (eq 'parse-error (tc:ty-effect-op-name exception)))
    (is (tc:ty= (tc:ty-effect-op-request-type exception) tc:*string-type*))
    ;; Response type should be bottom (never returns)
    (is (tc:ty-bot-p (tc:ty-effect-op-response-type exception)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect row simplification tests (simplify.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-simplify-effect-row-pure
  (let ((result (tc:simplify-effect-row tc:+ty-bot+)))
    (is (tc:ty-bot-p result))))

(deftest test-simplify-effect-row-single
  (let* ((effect (tc:make-ty-effect-op
                  :name 'state.get
                  :request-type tc:*unit-type*
                  :response-type tc:*integer-type*))
         (result (tc:simplify-effect-row effect)))
    (is (tc:ty-effect-op-p result))
    (is (eq 'state.get (tc:ty-effect-op-name result)))))

(deftest test-simplify-effect-row-with-pure
  (let* ((effect (tc:make-ty-effect-op
                  :name 'effect
                  :request-type tc:*unit-type*
                  :response-type tc:*unit-type*))
         (union (tc:make-ty-union :members (list tc:+ty-bot+ effect)))
         (result (tc:simplify-effect-row union)))
    ;; Pure should be removed, leaving just the effect
    (is (tc:ty-effect-op-p result))
    (is (eq 'effect (tc:ty-effect-op-name result)))))

(deftest test-simplify-effect-row-dedup
  (let* ((effect (tc:make-ty-effect-op
                  :name 'effect
                  :request-type tc:*unit-type*
                  :response-type tc:*unit-type*))
         (union (tc:make-ty-union :members (list effect effect)))
         (result (tc:simplify-effect-row union)))
    ;; Duplicates should be removed
    (is (tc:ty-effect-op-p result))))

(deftest test-simplify-type-effecting-fn
  (let* ((eff-fn (tc:make-ty-effecting-fn
                  :domain tc:*integer-type*
                  :codomain tc:*string-type*
                  :effects tc:+ty-bot+))
         (result (tc:simplify-type eff-fn)))
    (is (tc:ty-effecting-fn-p result))
    (is (tc:ty= (tc:ty-effecting-fn-domain result) tc:*integer-type*))))

(deftest test-simplify-type-effect-op
  (let* ((effect-op (tc:make-ty-effect-op
                     :name 'test
                     :request-type tc:*unit-type*
                     :response-type tc:*integer-type*))
         (result (tc:simplify-type effect-op)))
    (is (tc:ty-effect-op-p result))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Type printing tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-print-effecting-fn
  (let ((eff-fn (tc:make-ty-effecting-fn
                 :domain tc:*integer-type*
                 :codomain tc:*string-type*
                 :effects tc:+ty-bot+)))
    ;; Should print without error
    (is (stringp (princ-to-string eff-fn)))))

(deftest test-print-effect-op
  (let ((effect-op (tc:make-ty-effect-op
                    :name 'state.get
                    :request-type tc:*unit-type*
                    :response-type tc:*integer-type*)))
    ;; Should print without error
    (is (stringp (princ-to-string effect-op)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Polarity tracking tests (simplify.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-collect-type-occurrences-effecting-fn
  (tc:reset-levels)
  (let ((var (tc:make-variable-at-level)))
    ;; Variable in domain (contravariant position)
    (let ((eff-fn (tc:make-ty-effecting-fn
                   :domain var
                   :codomain tc:*string-type*
                   :effects tc:+ty-bot+)))
      (multiple-value-bind (pos neg)
          (tc:collect-type-occurrences eff-fn var t)
        (is (= 0 pos))
        (is (= 1 neg))))
    ;; Variable in codomain (covariant position)
    (let ((eff-fn (tc:make-ty-effecting-fn
                   :domain tc:*integer-type*
                   :codomain var
                   :effects tc:+ty-bot+)))
      (multiple-value-bind (pos neg)
          (tc:collect-type-occurrences eff-fn var t)
        (is (= 1 pos))
        (is (= 0 neg))))
    ;; Variable in effects (covariant position)
    (let* ((effect (tc:make-ty-effect-op
                    :name 'test
                    :request-type tc:*unit-type*
                    :response-type var))
           (eff-fn (tc:make-ty-effecting-fn
                    :domain tc:*integer-type*
                    :codomain tc:*string-type*
                    :effects effect)))
      (multiple-value-bind (pos neg)
          (tc:collect-type-occurrences eff-fn var t)
        (is (= 1 pos))
        (is (= 0 neg))))))

(deftest test-collect-type-occurrences-effect-op
  (tc:reset-levels)
  (let ((var (tc:make-variable-at-level)))
    (let ((effect (tc:make-ty-effect-op
                   :name 'test
                   :request-type var
                   :response-type tc:*string-type*)))
      (multiple-value-bind (pos neg)
          (tc:collect-type-occurrences effect var t)
        (is (= 1 pos))
        (is (= 0 neg))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Substitution tests (simplify.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-substitute-tyvar-sub-effecting-fn
  (tc:reset-levels)
  (let* ((var (tc:make-variable-at-level))
         (eff-fn (tc:make-ty-effecting-fn
                  :domain var
                  :codomain var
                  :effects tc:+ty-bot+))
         (result (tc:substitute-tyvar-sub eff-fn (list (cons var tc:*integer-type*)))))
    (is (tc:ty-effecting-fn-p result))
    (is (tc:ty= (tc:ty-effecting-fn-domain result) tc:*integer-type*))
    (is (tc:ty= (tc:ty-effecting-fn-codomain result) tc:*integer-type*))))

(deftest test-substitute-tyvar-sub-effect-op
  (tc:reset-levels)
  (let* ((var (tc:make-variable-at-level))
         (effect (tc:make-ty-effect-op
                  :name 'test
                  :request-type var
                  :response-type var))
         (result (tc:substitute-tyvar-sub effect (list (cons var tc:*integer-type*)))))
    (is (tc:ty-effect-op-p result))
    (is (tc:ty= (tc:ty-effect-op-request-type result) tc:*integer-type*))
    (is (tc:ty= (tc:ty-effect-op-response-type result) tc:*integer-type*))))

;;; Entry point
(format t "~&Loaded effects standalone tests. Run with (coalton-effects-standalone-tests::run-all-tests)~%")
