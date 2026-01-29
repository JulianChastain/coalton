(defpackage #:coalton-impl/typechecker/effects
  (:use
   #:cl
   #:coalton-impl/typechecker/base
   #:coalton-impl/typechecker/kinds
   #:coalton-impl/typechecker/types
   #:coalton-impl/typechecker/types-sub)
  (:local-nicknames
   (#:util #:coalton-impl/util)
   (#:settings #:coalton-impl/settings))
  (:export
   ;; Effect definition structures
   #:effect-definition                   ; STRUCT
   #:make-effect-definition              ; CONSTRUCTOR
   #:effect-definition-name              ; ACCESSOR
   #:effect-definition-type-vars         ; ACCESSOR
   #:effect-definition-operations        ; ACCESSOR
   #:effect-definition-documentation     ; ACCESSOR
   #:effect-definition-p                 ; FUNCTION
   ;; Effect operation definition
   #:effect-operation                    ; STRUCT
   #:make-effect-operation               ; CONSTRUCTOR
   #:effect-operation-name               ; ACCESSOR
   #:effect-operation-request-type       ; ACCESSOR
   #:effect-operation-response-type      ; ACCESSOR
   #:effect-operation-documentation      ; ACCESSOR
   #:effect-operation-p                  ; FUNCTION
   ;; Exception definition
   #:exception-definition                ; STRUCT
   #:make-exception-definition           ; CONSTRUCTOR
   #:exception-definition-name           ; ACCESSOR
   #:exception-definition-type           ; ACCESSOR
   #:exception-definition-documentation  ; ACCESSOR
   #:exception-definition-p              ; FUNCTION
   ;; Effect registry
   #:*effect-registry*                   ; VARIABLE
   #:register-effect                     ; FUNCTION
   #:lookup-effect                       ; FUNCTION
   #:register-exception                  ; FUNCTION
   #:lookup-exception                    ; FUNCTION
   ;; Type construction helpers
   #:make-effecting-function-type        ; FUNCTION
   #:make-pure-function-type             ; FUNCTION
   #:effect-type-for-operation           ; FUNCTION
   #:combine-effect-rows                 ; FUNCTION
   ))

(in-package #:coalton-impl/typechecker/effects)

;;;;
;;;; Algebraic Effects System
;;;;
;;;; This module defines the infrastructure for algebraic effects in Coalton.
;;;; Effects allow functions to perform operations that can be handled by
;;;; enclosing handlers, enabling features like:
;;;;
;;;; - Resumable exceptions (effect operations that can return values)
;;;; - State effects (get/put operations with handlers providing state)
;;;; - I/O effects (console, file operations)
;;;; - Custom control flow (coroutines, generators)
;;;;
;;;; The effect system integrates with Common Lisp's condition/restart system
;;;; for runtime support:
;;;; - SIGNAL maps to performing an effect operation
;;;; - HANDLER-BIND + RESTART-CASE maps to effect handlers
;;;; - ERROR maps to throwing exceptions (non-resumable effects)
;;;;
;;;; Effects are tracked in the type system using effect rows, which are
;;;; represented as unions of ty-effect-op types.
;;;;

;;;
;;; Effect Definition Structures
;;;

(defstruct effect-definition
  "An algebraic effect definition.

An effect groups related operations that share a semantic context.
For example, a State effect has 'get' and 'put' operations.

NAME: Symbol identifying the effect (e.g., 'STATE, 'CONSOLE)
TYPE-VARS: List of type variable symbols used in the effect
OPERATIONS: List of effect-operation structs
DOCUMENTATION: Optional documentation string"
  (name           (util:required 'name)       :type symbol     :read-only t)
  (type-vars      nil                         :type list       :read-only t)
  (operations     nil                         :type list       :read-only t)
  (documentation  nil                         :type (or null string) :read-only t))

(defstruct effect-operation
  "An operation within an algebraic effect.

Each operation represents a request that can be made to an effect handler.
The handler receives the request and can choose to:
1. Resume the computation with a value
2. Abort with a different value
3. Resume multiple times (for non-determinism)

NAME: Full name including effect (e.g., 'STATE.GET)
REQUEST-TYPE: Type of data sent with the operation
RESPONSE-TYPE: Type of data returned by the handler
DOCUMENTATION: Optional documentation string"
  (name           (util:required 'name)         :type symbol :read-only t)
  (request-type   (util:required 'request-type) :type ty     :read-only t)
  (response-type  (util:required 'response-type) :type ty    :read-only t)
  (documentation  nil                           :type (or null string) :read-only t))

(defstruct exception-definition
  "An exception type definition.

Exceptions are a special case of effects where the operation never
resumes normally. They map to Common Lisp's ERROR function.

NAME: Symbol identifying the exception (e.g., 'PARSE-ERROR)
TYPE: The payload type carried by the exception
DOCUMENTATION: Optional documentation string"
  (name           (util:required 'name) :type symbol :read-only t)
  (type           (util:required 'type) :type ty     :read-only t)
  (documentation  nil                   :type (or null string) :read-only t))

;;;
;;; Effect Registry
;;;

(defvar *effect-registry* (make-hash-table :test #'eq)
  "Global registry of defined effects.
Maps effect names (symbols) to effect-definition structs.")

(defvar *exception-registry* (make-hash-table :test #'eq)
  "Global registry of defined exceptions.
Maps exception names (symbols) to exception-definition structs.")

(defun register-effect (effect-def)
  "Register an effect definition in the global registry."
  (declare (type effect-definition effect-def))
  (setf (gethash (effect-definition-name effect-def) *effect-registry*)
        effect-def)
  ;; Also register each operation
  (dolist (op (effect-definition-operations effect-def))
    (setf (gethash (effect-operation-name op) *effect-registry*)
          op))
  effect-def)

(defun lookup-effect (name)
  "Look up an effect or operation by name.
Returns the effect-definition or effect-operation, or NIL if not found."
  (gethash name *effect-registry*))

(defun register-exception (exception-def)
  "Register an exception definition in the global registry."
  (declare (type exception-definition exception-def))
  (setf (gethash (exception-definition-name exception-def) *exception-registry*)
        exception-def))

(defun lookup-exception (name)
  "Look up an exception by name.
Returns the exception-definition, or NIL if not found."
  (gethash name *exception-registry*))

;;;
;;; Type Construction Helpers
;;;

(defun make-effecting-function-type (domain codomain effects)
  "Create an effecting function type (A -> B ! E).

DOMAIN: Input type
CODOMAIN: Output type
EFFECTS: Effect row (ty-bot for pure, ty-effect-op, or ty-union)"
  (declare (type ty domain codomain effects))
  (make-ty-effecting-fn :domain domain
                        :codomain codomain
                        :effects effects))

(defun make-pure-function-type (domain codomain)
  "Create a pure function type (A -> B) using the effecting function representation.

This is equivalent to (A -> B ! Pure) where Pure = ty-bot."
  (declare (type ty domain codomain))
  (make-ty-effecting-fn :domain domain
                        :codomain codomain
                        :effects +ty-bot+))

(defun effect-type-for-operation (operation)
  "Create a ty-effect-op for the given effect operation definition."
  (declare (type effect-operation operation))
  (make-ty-effect-op :name (effect-operation-name operation)
                     :request-type (effect-operation-request-type operation)
                     :response-type (effect-operation-response-type operation)))

(defun combine-effect-rows (&rest effect-rows)
  "Combine multiple effect rows into a single effect row.

This creates a union of all effects. Pure effects (ty-bot) are identity.
A single effect remains as-is. Multiple effects become a ty-union."
  (let ((non-pure (remove-if #'ty-bot-p effect-rows)))
    (cond
      ;; All pure
      ((null non-pure) +ty-bot+)
      ;; Single effect
      ((null (rest non-pure))
       (let ((single (first non-pure)))
         (if (ty-union-p single)
             single
             single)))
      ;; Multiple effects: create union
      (t
       (let ((all-members
               (loop :for row :in non-pure
                     :if (ty-union-p row)
                       :append (ty-union-members row)
                     :else
                       :collect row)))
         (make-ty-union :members (remove-duplicates all-members :test #'ty=)))))))

;;;
;;; Effect Type Predicates and Accessors
;;;

(defun exception-effect-p (effect)
  "Check if EFFECT represents an exception (non-resumable effect).

Exceptions are effect operations where the response type is ty-bot,
indicating they never return normally."
  (and (ty-effect-op-p effect)
       (ty-bot-p (ty-effect-op-response-type effect))))

(defun get-effect-operations (effect-name)
  "Get all operation types for a named effect.

Returns a list of ty-effect-op types for all operations defined
in the effect."
  (let ((effect (lookup-effect effect-name)))
    (when (effect-definition-p effect)
      (mapcar #'effect-type-for-operation
              (effect-definition-operations effect)))))

(defun effect-row-contains-p (row effect-name)
  "Check if an effect row contains a specific effect.

ROW: An effect row (ty-bot, ty-effect-op, or ty-union)
EFFECT-NAME: Symbol naming the effect to check for"
  (cond
    ((ty-bot-p row) nil)
    ((ty-effect-op-p row)
     (eq (ty-effect-op-name row) effect-name))
    ((ty-union-p row)
     (some (lambda (m) (effect-row-contains-p m effect-name))
           (ty-union-members row)))
    ((tyvar-sub-p row)
     ;; For effect variables, we can't determine statically
     nil)
    (t nil)))

(defun effect-row-remove (row effect-name)
  "Remove an effect from an effect row.

Returns a new effect row with the named effect removed.
This is used by effect handlers to eliminate handled effects."
  (cond
    ((ty-bot-p row) row)
    ((ty-effect-op-p row)
     (if (eq (ty-effect-op-name row) effect-name)
         +ty-bot+
         row))
    ((ty-union-p row)
     (let ((remaining (remove-if (lambda (m)
                                   (and (ty-effect-op-p m)
                                        (eq (ty-effect-op-name m) effect-name)))
                                 (ty-union-members row))))
       (cond
         ((null remaining) +ty-bot+)
         ((null (rest remaining)) (first remaining))
         (t (make-ty-union :members remaining)))))
    (t row)))

;;;
;;; Standard Effects
;;;

(defun define-standard-effects ()
  "Define the standard built-in effects.

This is called during initialization to register commonly used effects."

  ;; Exception effect (the base for all exceptions)
  ;; This is more of a marker - actual exceptions are defined via define-exception

  ;; State effect
  (register-effect
   (make-effect-definition
    :name 'coalton:state
    :type-vars '(:s)
    :documentation "Mutable state effect"
    :operations
    (list
     (make-effect-operation
      :name 'coalton:state.get
      :request-type *unit-type*
      :response-type (make-tyvar :id -100 :kind +kstar+)  ; placeholder for :s
      :documentation "Get the current state")
     (make-effect-operation
      :name 'coalton:state.put
      :request-type (make-tyvar :id -100 :kind +kstar+)  ; placeholder for :s
      :response-type *unit-type*
      :documentation "Set the state"))))

  ;; Reader effect
  (register-effect
   (make-effect-definition
    :name 'coalton:reader
    :type-vars '(:r)
    :documentation "Read-only environment effect"
    :operations
    (list
     (make-effect-operation
      :name 'coalton:reader.ask
      :request-type *unit-type*
      :response-type (make-tyvar :id -101 :kind +kstar+)  ; placeholder for :r
      :documentation "Read the environment"))))

  ;; Writer effect
  (register-effect
   (make-effect-definition
    :name 'coalton:writer
    :type-vars '(:w)
    :documentation "Append-only output effect"
    :operations
    (list
     (make-effect-operation
      :name 'coalton:writer.tell
      :request-type (make-tyvar :id -102 :kind +kstar+)  ; placeholder for :w
      :response-type *unit-type*
      :documentation "Append to the output")))))

;;;
;;; Printing
;;;

(defun format-effect-row (stream effects)
  "Format an effect row for display."
  (cond
    ((ty-bot-p effects)
     (write-string "Pure" stream))
    ((ty-effect-op-p effects)
     (format stream "~A" (ty-effect-op-name effects)))
    ((ty-union-p effects)
     (format stream "(")
     (loop :for (m . rest) :on (ty-union-members effects)
           :do (format-effect-row stream m)
           :when rest :do (write-string " | " stream))
     (format stream ")"))
    ((tyvar-sub-p effects)
     (format stream ":e~A" (tyvar-sub-id effects)))
    (t
     (format stream "~A" effects))))

(defmethod print-object ((def effect-definition) stream)
  (print-unreadable-object (def stream :type t)
    (format stream "~A (~{~A~^, ~})"
            (effect-definition-name def)
            (mapcar #'effect-operation-name
                    (effect-definition-operations def)))))

(defmethod print-object ((op effect-operation) stream)
  (print-unreadable-object (op stream :type t)
    (format stream "~A" (effect-operation-name op))))

(defmethod print-object ((ex exception-definition) stream)
  (print-unreadable-object (ex stream :type t)
    (format stream "~A" (exception-definition-name ex))))
