;;;; effects-tests.lisp
;;;;
;;;; Unit tests for the algebraic effects system infrastructure
;;;;

(in-package #:coalton-tests)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; ty-effecting-fn tests (types-sub.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-ty-effecting-fn-creation ()
  "Test creation of effecting function types."
  (let ((eff-fn (tc:make-ty-effecting-fn
                 :domain tc:*integer-type*
                 :codomain tc:*string-type*
                 :effects tc:+ty-bot+)))
    (is (tc:ty-effecting-fn-p eff-fn))
    (is (tc:ty= (tc:ty-effecting-fn-domain eff-fn) tc:*integer-type*))
    (is (tc:ty= (tc:ty-effecting-fn-codomain eff-fn) tc:*string-type*))
    (is (tc:ty-bot-p (tc:ty-effecting-fn-effects eff-fn)))))

(deftest test-ty-effecting-fn-with-effect ()
  "Test effecting function type with actual effects."
  (let* ((state-effect (tc:make-ty-effect-op
                        :name 'coalton:state.get
                        :request-type tc:*unit-type*
                        :response-type tc:*integer-type*))
         (eff-fn (tc:make-ty-effecting-fn
                  :domain tc:*unit-type*
                  :codomain tc:*integer-type*
                  :effects state-effect)))
    (is (tc:ty-effecting-fn-p eff-fn))
    (is (tc:ty-effect-op-p (tc:ty-effecting-fn-effects eff-fn)))
    (is (eq 'coalton:state.get
            (tc:ty-effect-op-name (tc:ty-effecting-fn-effects eff-fn))))))

(deftest test-ty-effecting-fn-kind ()
  "Test that effecting function types have kind *."
  (let ((eff-fn (tc:make-ty-effecting-fn
                 :domain tc:*integer-type*
                 :codomain tc:*string-type*
                 :effects tc:+ty-bot+)))
    (is (tc:kstar-p (tc:kind-of eff-fn)))))

(deftest test-ty-effecting-fn-equality ()
  "Test equality of effecting function types."
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

(deftest test-ty-effecting-fn-type-variables ()
  "Test extraction of type variables from effecting function types."
  (tc:reset-levels)
  (let* ((var (tc:make-variable-at-level))
         (eff-fn (tc:make-ty-effecting-fn
                  :domain var
                  :codomain tc:*string-type*
                  :effects tc:+ty-bot+)))
    (is (member var (tc:type-variables eff-fn)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; ty-effect-op tests (types-sub.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-ty-effect-op-creation ()
  "Test creation of effect operation types."
  (let ((effect-op (tc:make-ty-effect-op
                    :name 'coalton:state.get
                    :request-type tc:*unit-type*
                    :response-type tc:*integer-type*)))
    (is (tc:ty-effect-op-p effect-op))
    (is (eq 'coalton:state.get (tc:ty-effect-op-name effect-op)))
    (is (tc:ty= (tc:ty-effect-op-request-type effect-op) tc:*unit-type*))
    (is (tc:ty= (tc:ty-effect-op-response-type effect-op) tc:*integer-type*))))

(deftest test-ty-effect-op-kind ()
  "Test that effect operation types have kind *."
  (let ((effect-op (tc:make-ty-effect-op
                    :name 'test-effect
                    :request-type tc:*unit-type*
                    :response-type tc:*integer-type*)))
    (is (tc:kstar-p (tc:kind-of effect-op)))))

(deftest test-ty-effect-op-equality ()
  "Test equality of effect operation types."
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

(deftest test-ty-effect-op-type-variables ()
  "Test extraction of type variables from effect operation types."
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

(deftest test-pure-effect-p ()
  "Test pure-effect-p predicate."
  (is (tc:pure-effect-p tc:+ty-bot+))
  (is (not (tc:pure-effect-p tc:+ty-top+)))
  (is (not (tc:pure-effect-p (tc:make-ty-effect-op
                              :name 'test
                              :request-type tc:*unit-type*
                              :response-type tc:*unit-type*)))))

(deftest test-effect-row-p ()
  "Test effect-row-p predicate."
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

(deftest test-make-exception-effect ()
  "Test creation of exception (non-resumable) effects."
  (let ((exception (tc:make-exception-effect 'parse-error tc:*string-type*)))
    (is (tc:ty-effect-op-p exception))
    (is (eq 'parse-error (tc:ty-effect-op-name exception)))
    (is (tc:ty= (tc:ty-effect-op-request-type exception) tc:*string-type*))
    ;; Response type should be bottom (never returns)
    (is (tc:ty-bot-p (tc:ty-effect-op-response-type exception)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect types kind substitution tests (types-sub.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-apply-ksubstitution-effecting-fn ()
  "Test kind substitution application to effecting function types."
  (let* ((eff-fn (tc:make-ty-effecting-fn
                  :domain tc:*integer-type*
                  :codomain tc:*string-type*
                  :effects tc:+ty-bot+))
         (result (tc:apply-ksubstitution nil eff-fn)))
    ;; With empty substitution, should be structurally equal
    (is (tc:ty-effecting-fn-p result))
    (is (tc:ty= (tc:ty-effecting-fn-domain result) tc:*integer-type*))))

(deftest test-apply-ksubstitution-effect-op ()
  "Test kind substitution application to effect operation types."
  (let* ((effect-op (tc:make-ty-effect-op
                     :name 'test-effect
                     :request-type tc:*unit-type*
                     :response-type tc:*integer-type*))
         (result (tc:apply-ksubstitution nil effect-op)))
    (is (tc:ty-effect-op-p result))
    (is (eq 'test-effect (tc:ty-effect-op-name result)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect types instantiation tests (types-sub.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-instantiate-effecting-fn ()
  "Test instantiation of effecting function types."
  (let* ((eff-fn (tc:make-ty-effecting-fn
                  :domain tc:*integer-type*
                  :codomain tc:*string-type*
                  :effects tc:+ty-bot+))
         (result (tc:instantiate nil eff-fn)))
    (is (tc:ty-effecting-fn-p result))))

(deftest test-instantiate-effect-op ()
  "Test instantiation of effect operation types."
  (let* ((effect-op (tc:make-ty-effect-op
                     :name 'test-effect
                     :request-type tc:*unit-type*
                     :response-type tc:*integer-type*))
         (result (tc:instantiate nil effect-op)))
    (is (tc:ty-effect-op-p result))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect union in effecting function tests
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-effecting-fn-with-effect-union ()
  "Test effecting function type with union of effects."
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
;;; Effect definition structure tests (effects.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-effect-definition-creation ()
  "Test creation of effect definitions."
  (let* ((get-op (tc:make-effect-operation
                  :name 'my-state.get
                  :request-type tc:*unit-type*
                  :response-type tc:*integer-type*
                  :documentation "Get state"))
         (put-op (tc:make-effect-operation
                  :name 'my-state.put
                  :request-type tc:*integer-type*
                  :response-type tc:*unit-type*
                  :documentation "Put state"))
         (effect-def (tc:make-effect-definition
                      :name 'my-state
                      :type-vars '(:s)
                      :operations (list get-op put-op)
                      :documentation "Mutable state effect")))
    (is (tc:effect-definition-p effect-def))
    (is (eq 'my-state (tc:effect-definition-name effect-def)))
    (is (equal '(:s) (tc:effect-definition-type-vars effect-def)))
    (is (= 2 (length (tc:effect-definition-operations effect-def))))
    (is (string= "Mutable state effect" (tc:effect-definition-documentation effect-def)))))

(deftest test-effect-operation-creation ()
  "Test creation of effect operation definitions."
  (let ((op (tc:make-effect-operation
             :name 'state.get
             :request-type tc:*unit-type*
             :response-type tc:*integer-type*
             :documentation "Get the current state")))
    (is (tc:effect-operation-p op))
    (is (eq 'state.get (tc:effect-operation-name op)))
    (is (tc:ty= tc:*unit-type* (tc:effect-operation-request-type op)))
    (is (tc:ty= tc:*integer-type* (tc:effect-operation-response-type op)))))

(deftest test-exception-definition-creation ()
  "Test creation of exception definitions."
  (let ((ex (tc:make-exception-definition
             :name 'parse-error
             :type tc:*string-type*
             :documentation "Parse error exception")))
    (is (tc:exception-definition-p ex))
    (is (eq 'parse-error (tc:exception-definition-name ex)))
    (is (tc:ty= tc:*string-type* (tc:exception-definition-type ex)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect registry tests (effects.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-effect-registry-register-and-lookup ()
  "Test registering and looking up effects."
  (let ((tc:*effect-registry* (make-hash-table :test #'eq)))
    (let* ((get-op (tc:make-effect-operation
                    :name 'test-state.get
                    :request-type tc:*unit-type*
                    :response-type tc:*integer-type*))
           (effect-def (tc:make-effect-definition
                        :name 'test-state
                        :type-vars '(:s)
                        :operations (list get-op))))
      ;; Register the effect
      (tc:register-effect effect-def)
      ;; Lookup by effect name
      (is (tc:effect-definition-p (tc:lookup-effect 'test-state)))
      ;; Lookup by operation name
      (is (tc:effect-operation-p (tc:lookup-effect 'test-state.get))))))

(deftest test-exception-registry ()
  "Test registering and looking up exceptions."
  (let ((tc:*exception-registry* (make-hash-table :test #'eq)))
    (let ((ex (tc:make-exception-definition
               :name 'test-exception
               :type tc:*string-type*)))
      (tc:register-exception ex)
      (let ((found (tc:lookup-exception 'test-exception)))
        (is (tc:exception-definition-p found))
        (is (eq 'test-exception (tc:exception-definition-name found)))))))

(deftest test-lookup-nonexistent ()
  "Test looking up nonexistent effects/exceptions returns nil."
  (let ((tc:*effect-registry* (make-hash-table :test #'eq))
        (tc:*exception-registry* (make-hash-table :test #'eq)))
    (is (null (tc:lookup-effect 'nonexistent)))
    (is (null (tc:lookup-exception 'nonexistent)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Type construction helper tests (effects.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-make-effecting-function-type ()
  "Test make-effecting-function-type helper."
  (let ((eff-fn (tc:make-effecting-function-type
                 tc:*integer-type*
                 tc:*string-type*
                 tc:+ty-bot+)))
    (is (tc:ty-effecting-fn-p eff-fn))
    (is (tc:ty= (tc:ty-effecting-fn-domain eff-fn) tc:*integer-type*))
    (is (tc:ty= (tc:ty-effecting-fn-codomain eff-fn) tc:*string-type*))
    (is (tc:pure-effect-p (tc:ty-effecting-fn-effects eff-fn)))))

(deftest test-make-pure-function-type ()
  "Test make-pure-function-type helper."
  (let ((pure-fn (tc:make-pure-function-type
                  tc:*integer-type*
                  tc:*string-type*)))
    (is (tc:ty-effecting-fn-p pure-fn))
    (is (tc:pure-effect-p (tc:ty-effecting-fn-effects pure-fn)))))

(deftest test-effect-type-for-operation ()
  "Test effect-type-for-operation helper."
  (let* ((op (tc:make-effect-operation
              :name 'state.get
              :request-type tc:*unit-type*
              :response-type tc:*integer-type*))
         (effect-type (tc:effect-type-for-operation op)))
    (is (tc:ty-effect-op-p effect-type))
    (is (eq 'state.get (tc:ty-effect-op-name effect-type)))))

(deftest test-combine-effect-rows-empty ()
  "Test combining empty effect rows."
  (let ((result (tc:combine-effect-rows)))
    (is (tc:pure-effect-p result))))

(deftest test-combine-effect-rows-single ()
  "Test combining a single effect row."
  (let* ((effect (tc:make-ty-effect-op
                  :name 'test
                  :request-type tc:*unit-type*
                  :response-type tc:*unit-type*))
         (result (tc:combine-effect-rows effect)))
    (is (tc:ty-effect-op-p result))
    (is (eq 'test (tc:ty-effect-op-name result)))))

(deftest test-combine-effect-rows-multiple ()
  "Test combining multiple effect rows."
  (let* ((effect1 (tc:make-ty-effect-op
                   :name 'effect1
                   :request-type tc:*unit-type*
                   :response-type tc:*unit-type*))
         (effect2 (tc:make-ty-effect-op
                   :name 'effect2
                   :request-type tc:*unit-type*
                   :response-type tc:*unit-type*))
         (result (tc:combine-effect-rows effect1 effect2)))
    (is (tc:ty-union-p result))
    (is (= 2 (length (tc:ty-union-members result))))))

(deftest test-combine-effect-rows-with-pure ()
  "Test combining effect rows with pure effects (identity element)."
  (let* ((effect (tc:make-ty-effect-op
                  :name 'test
                  :request-type tc:*unit-type*
                  :response-type tc:*unit-type*))
         (result (tc:combine-effect-rows tc:+ty-bot+ effect tc:+ty-bot+)))
    ;; Pure effects should be removed
    (is (tc:ty-effect-op-p result))
    (is (eq 'test (tc:ty-effect-op-name result)))))

(deftest test-combine-effect-rows-dedup ()
  "Test combining effect rows removes duplicates."
  (let* ((effect (tc:make-ty-effect-op
                  :name 'test
                  :request-type tc:*unit-type*
                  :response-type tc:*unit-type*))
         (result (tc:combine-effect-rows effect effect)))
    ;; Should not create a union with duplicates
    (is (tc:ty-effect-op-p result))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect predicates tests (effects.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-exception-effect-p ()
  "Test exception-effect-p predicate."
  (let ((exception (tc:make-exception-effect 'error tc:*string-type*))
        (resumable (tc:make-ty-effect-op
                    :name 'state.get
                    :request-type tc:*unit-type*
                    :response-type tc:*integer-type*)))
    (is (tc:exception-effect-p exception))
    (is (not (tc:exception-effect-p resumable)))))

(deftest test-get-effect-operations ()
  "Test get-effect-operations function."
  (let ((tc:*effect-registry* (make-hash-table :test #'eq)))
    (let* ((get-op (tc:make-effect-operation
                    :name 'test-state.get
                    :request-type tc:*unit-type*
                    :response-type tc:*integer-type*))
           (put-op (tc:make-effect-operation
                    :name 'test-state.put
                    :request-type tc:*integer-type*
                    :response-type tc:*unit-type*))
           (effect-def (tc:make-effect-definition
                        :name 'test-state
                        :type-vars '(:s)
                        :operations (list get-op put-op))))
      (tc:register-effect effect-def)
      (let ((ops (tc:get-effect-operations 'test-state)))
        (is (= 2 (length ops)))
        (is (every #'tc:ty-effect-op-p ops))))))

(deftest test-effect-row-contains-p ()
  "Test effect-row-contains-p predicate."
  (let ((effect (tc:make-ty-effect-op
                 :name 'state.get
                 :request-type tc:*unit-type*
                 :response-type tc:*integer-type*)))
    ;; Pure row doesn't contain any effect
    (is (not (tc:effect-row-contains-p tc:+ty-bot+ 'state.get)))
    ;; Single effect row contains that effect
    (is (tc:effect-row-contains-p effect 'state.get))
    ;; But not other effects
    (is (not (tc:effect-row-contains-p effect 'other.effect)))
    ;; Union of effects
    (let ((union (tc:make-ty-union
                  :members (list effect
                                 (tc:make-ty-effect-op
                                  :name 'reader.ask
                                  :request-type tc:*unit-type*
                                  :response-type tc:*string-type*)))))
      (is (tc:effect-row-contains-p union 'state.get))
      (is (tc:effect-row-contains-p union 'reader.ask))
      (is (not (tc:effect-row-contains-p union 'other.effect))))))

(deftest test-effect-row-remove ()
  "Test effect-row-remove function."
  (let ((effect (tc:make-ty-effect-op
                 :name 'state.get
                 :request-type tc:*unit-type*
                 :response-type tc:*integer-type*)))
    ;; Removing from pure returns pure
    (is (tc:ty-bot-p (tc:effect-row-remove tc:+ty-bot+ 'state.get)))
    ;; Removing the only effect returns pure
    (is (tc:ty-bot-p (tc:effect-row-remove effect 'state.get)))
    ;; Removing non-existent effect returns original
    (is (tc:ty= effect (tc:effect-row-remove effect 'other.effect)))
    ;; Removing from union
    (let* ((effect2 (tc:make-ty-effect-op
                     :name 'reader.ask
                     :request-type tc:*unit-type*
                     :response-type tc:*string-type*))
           (union (tc:make-ty-union :members (list effect effect2)))
           (result (tc:effect-row-remove union 'state.get)))
      ;; Should leave just reader.ask
      (is (tc:ty-effect-op-p result))
      (is (eq 'reader.ask (tc:ty-effect-op-name result))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect simplification tests (simplify.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-simplify-effect-row-pure ()
  "Test simplification of pure effect row."
  (let ((result (tc:simplify-effect-row tc:+ty-bot+)))
    (is (tc:ty-bot-p result))))

(deftest test-simplify-effect-row-single ()
  "Test simplification of single effect."
  (let* ((effect (tc:make-ty-effect-op
                  :name 'state.get
                  :request-type tc:*unit-type*
                  :response-type tc:*integer-type*))
         (result (tc:simplify-effect-row effect)))
    (is (tc:ty-effect-op-p result))
    (is (eq 'state.get (tc:ty-effect-op-name result)))))

(deftest test-simplify-effect-row-union ()
  "Test simplification of effect union."
  (let* ((effect1 (tc:make-ty-effect-op
                   :name 'effect1
                   :request-type tc:*unit-type*
                   :response-type tc:*unit-type*))
         (effect2 (tc:make-ty-effect-op
                   :name 'effect2
                   :request-type tc:*unit-type*
                   :response-type tc:*unit-type*))
         (union (tc:make-ty-union :members (list effect1 effect2)))
         (result (tc:simplify-effect-row union)))
    (is (tc:ty-union-p result))
    (is (= 2 (length (tc:ty-union-members result))))))

(deftest test-simplify-effect-row-with-pure ()
  "Test simplification removes pure from effect union."
  (let* ((effect (tc:make-ty-effect-op
                  :name 'effect
                  :request-type tc:*unit-type*
                  :response-type tc:*unit-type*))
         (union (tc:make-ty-union :members (list tc:+ty-bot+ effect)))
         (result (tc:simplify-effect-row union)))
    ;; Pure should be removed, leaving just the effect
    (is (tc:ty-effect-op-p result))
    (is (eq 'effect (tc:ty-effect-op-name result)))))

(deftest test-simplify-effect-row-dedup ()
  "Test simplification removes duplicate effects."
  (let* ((effect (tc:make-ty-effect-op
                  :name 'effect
                  :request-type tc:*unit-type*
                  :response-type tc:*unit-type*))
         (union (tc:make-ty-union :members (list effect effect)))
         (result (tc:simplify-effect-row union)))
    ;; Duplicates should be removed
    (is (tc:ty-effect-op-p result))))

(deftest test-simplify-type-effecting-fn ()
  "Test simplification of effecting function types."
  (let* ((eff-fn (tc:make-ty-effecting-fn
                  :domain tc:*integer-type*
                  :codomain tc:*string-type*
                  :effects tc:+ty-bot+))
         (result (tc:simplify-type eff-fn)))
    (is (tc:ty-effecting-fn-p result))
    (is (tc:ty= (tc:ty-effecting-fn-domain result) tc:*integer-type*))))

(deftest test-simplify-type-effect-op ()
  "Test simplification of effect operation types."
  (let* ((effect-op (tc:make-ty-effect-op
                     :name 'test
                     :request-type tc:*unit-type*
                     :response-type tc:*integer-type*))
         (result (tc:simplify-type effect-op)))
    (is (tc:ty-effect-op-p result))))

(deftest test-simplify-type-nested-effect-union ()
  "Test simplification flattens nested effect unions."
  (let* ((effect1 (tc:make-ty-effect-op
                   :name 'effect1
                   :request-type tc:*unit-type*
                   :response-type tc:*unit-type*))
         (effect2 (tc:make-ty-effect-op
                   :name 'effect2
                   :request-type tc:*unit-type*
                   :response-type tc:*unit-type*))
         (effect3 (tc:make-ty-effect-op
                   :name 'effect3
                   :request-type tc:*unit-type*
                   :response-type tc:*unit-type*))
         (inner-union (tc:make-ty-union :members (list effect2 effect3)))
         (outer-union (tc:make-ty-union :members (list effect1 inner-union)))
         (result (tc:simplify-effect-row outer-union)))
    ;; Should be flattened to a single union with 3 members
    (is (tc:ty-union-p result))
    (is (= 3 (length (tc:ty-union-members result))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect type printing tests (types-sub.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-print-effecting-fn ()
  "Test printing of effecting function types."
  (let ((eff-fn (tc:make-ty-effecting-fn
                 :domain tc:*integer-type*
                 :codomain tc:*string-type*
                 :effects tc:+ty-bot+)))
    ;; Should print without error
    (is (stringp (princ-to-string eff-fn)))))

(deftest test-print-effect-op ()
  "Test printing of effect operation types."
  (let ((effect-op (tc:make-ty-effect-op
                    :name 'state.get
                    :request-type tc:*unit-type*
                    :response-type tc:*integer-type*)))
    ;; Should print without error
    (is (stringp (princ-to-string effect-op)))))

(deftest test-format-effect-row-pure ()
  "Test formatting of pure effect row."
  (let ((output (with-output-to-string (s)
                  (tc:format-effect-row s tc:+ty-bot+))))
    (is (string= "Pure" output))))

(deftest test-format-effect-row-single ()
  "Test formatting of single effect."
  (let* ((effect (tc:make-ty-effect-op
                  :name 'STATE.GET
                  :request-type tc:*unit-type*
                  :response-type tc:*integer-type*))
         (output (with-output-to-string (s)
                   (tc:format-effect-row s effect))))
    (is (search "STATE.GET" output))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect type polarity tests (simplify.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-collect-type-occurrences-effecting-fn ()
  "Test polarity tracking in effecting function types."
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

(deftest test-collect-type-occurrences-effect-op ()
  "Test polarity tracking in effect operation types."
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
;;; Effect type substitution tests (simplify.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-substitute-tyvar-sub-effecting-fn ()
  "Test substitution in effecting function types."
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

(deftest test-substitute-tyvar-sub-effect-op ()
  "Test substitution in effect operation types."
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Standard effects initialization tests (effects.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-define-standard-effects ()
  "Test that standard effects are defined correctly."
  (let ((tc:*effect-registry* (make-hash-table :test #'eq)))
    (tc:define-standard-effects)
    ;; Check State effect
    (let ((state (tc:lookup-effect 'coalton:state)))
      (is (tc:effect-definition-p state))
      (is (equal '(:s) (tc:effect-definition-type-vars state))))
    ;; Check State operations
    (is (tc:effect-operation-p (tc:lookup-effect 'coalton:state.get)))
    (is (tc:effect-operation-p (tc:lookup-effect 'coalton:state.put)))
    ;; Check Reader effect
    (let ((reader (tc:lookup-effect 'coalton:reader)))
      (is (tc:effect-definition-p reader))
      (is (equal '(:r) (tc:effect-definition-type-vars reader))))
    ;; Check Reader operations
    (is (tc:effect-operation-p (tc:lookup-effect 'coalton:reader.ask)))
    ;; Check Writer effect
    (let ((writer (tc:lookup-effect 'coalton:writer)))
      (is (tc:effect-definition-p writer))
      (is (equal '(:w) (tc:effect-definition-type-vars writer))))
    ;; Check Writer operations
    (is (tc:effect-operation-p (tc:lookup-effect 'coalton:writer.tell)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect compact type tests (simplify.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-compact-type-effecting-fn ()
  "Test compact-type on effecting function types."
  (let* ((eff-fn (tc:make-ty-effecting-fn
                  :domain tc:*integer-type*
                  :codomain tc:*string-type*
                  :effects tc:+ty-bot+))
         (result (tc:compact-type eff-fn)))
    (is (tc:ty-effecting-fn-p result))))

(deftest test-compact-type-effect-with-variable ()
  "Test compact-type with effect variables."
  (tc:reset-levels)
  (let* ((var (tc:make-variable-at-level))
         (eff-fn (tc:make-ty-effecting-fn
                  :domain tc:*integer-type*
                  :codomain tc:*string-type*
                  :effects var))
         (result (tc:compact-type eff-fn)))
    (is (tc:ty-effecting-fn-p result))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Effect variable context collection tests (simplify.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-collect-variable-contexts-effecting-fn ()
  "Test collecting variable contexts from effecting function types."
  (tc:reset-levels)
  (let* ((var (tc:make-variable-at-level))
         (eff-fn (tc:make-ty-effecting-fn
                  :domain var
                  :codomain tc:*string-type*
                  :effects tc:+ty-bot+))
         (contexts (tc:collect-variable-contexts eff-fn)))
    (is (hash-table-p contexts))
    (is (gethash (tc:tyvar-sub-id var) contexts))))

(deftest test-collect-variable-contexts-effect-op ()
  "Test collecting variable contexts from effect operation types."
  (tc:reset-levels)
  (let* ((var (tc:make-variable-at-level))
         (effect (tc:make-ty-effect-op
                  :name 'test
                  :request-type var
                  :response-type tc:*string-type*))
         (contexts (tc:collect-variable-contexts effect)))
    (is (hash-table-p contexts))
    (is (gethash (tc:tyvar-sub-id var) contexts))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Kind variable extraction tests for effect types (types-sub.lisp)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deftest test-kind-variables-effecting-fn ()
  "Test kind variable extraction from effecting function types."
  (let ((eff-fn (tc:make-ty-effecting-fn
                 :domain tc:*integer-type*
                 :codomain tc:*string-type*
                 :effects tc:+ty-bot+)))
    ;; Should not error
    (is (listp (tc:kind-variables-generic% eff-fn)))))

(deftest test-kind-variables-effect-op ()
  "Test kind variable extraction from effect operation types."
  (let ((effect (tc:make-ty-effect-op
                 :name 'test
                 :request-type tc:*unit-type*
                 :response-type tc:*integer-type*)))
    ;; Should not error
    (is (listp (tc:kind-variables-generic% effect)))))
