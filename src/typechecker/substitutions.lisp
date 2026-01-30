(defpackage #:coalton-impl/typechecker/substitutions
  (:use
   #:cl
   #:coalton-impl/typechecker/base
   #:coalton-impl/typechecker/types)
  (:local-nicknames
   (#:util #:coalton-impl/util))
  (:export
   #:substitution                       ; STRUCT
   #:make-substitution                  ; CONSTRUCTOR
   #:substitution-from                  ; ACCESSOR
   #:substitution-to                    ; ACCESSOR
   #:substitution-p                     ; FUNCTION
   #:substitution-list                  ; TYPE
   #:merge-substitution-lists           ; FUNCTION
   #:compose-substitution-lists         ; FUNCTION
   #:apply-substitution                 ; FUNCTION
   ))

(in-package #:coalton-impl/typechecker/substitutions)

;;;
;;; Type substitutions
;;;

(defstruct substitution
  (from (util:required 'from) :type tyvar :read-only t)
  (to   (util:required 'to)   :type ty    :read-only t))

(defun substitution-list-p (thing)
  (and (alexandria:proper-list-p thing)
       (every (lambda (x) (typep x 'substitution)) thing)))

(deftype substitution-list ()
  '(satisfies substitution-list-p))

(define-condition substitution-list-merge-error (coalton-internal-type-error)
  ())

(defun merge-substitution-lists (s1 s2)
  "Merge substitution lists S1 and S2 together, erroring on disagreeing entries."
  (declare (type substitution-list s1)
           (type substitution-list s2)
           (values substitution-list)
           (optimize (speed 3) (safety 1)))
  ;; Fast path: if either list is empty, return the other
  (cond
    ((null s1) s2)
    ((null s2) s1)
    (t
     ;; Check for conflicts using fast integer comparison on tyvar-id
     (loop :for subst1 :of-type substitution :in s1
           :for id1 :of-type fixnum := (tyvar-id (substitution-from subst1))
           :do (let ((subst2 (find-substitution id1 s2)))
                 (when (and subst2
                            (not (ty= (substitution-to subst1)
                                      (substitution-to subst2))))
                   (error 'substitution-list-merge-error))))
     ;; No conflicts, concatenate the lists
     (nconc (copy-list s1) s2))))

(defun compose-substitution-lists (s1 s2)
  "Compose substitution lists S1 and S2 together, applying S1 to S2."
  (declare (type substitution-list s1)
           (type substitution-list s2)
           (values substitution-list))
  (append
   (mapcar
    (lambda (s)
      (make-substitution
       :from (substitution-from s)
       :to (apply-substitution s1 (substitution-to s))))
    s2)
   s1))

(declaim (inline find-substitution))
(defun find-substitution (tyvar-id subst-list)
  "Find a substitution by tyvar-id using fast integer comparison."
  (declare (type fixnum tyvar-id)
           (type list subst-list)
           (optimize (speed 3) (safety 0)))
  (loop :for subst :of-type substitution :in subst-list
        :when (eql tyvar-id (tyvar-id (substitution-from subst)))
          :return subst))

(defgeneric apply-substitution (subst-list type)
  (:documentation "Apply the substitutions defined in SUBST-LIST on TYPE.")
  ;; For a type variable, substitute if it is in SUBST-LIST, otherwise return the original type
  (:method (subst-list (type tyvar))
    (let ((subst (find-substitution (tyvar-id type) subst-list)))
      (if subst
          (substitution-to subst)
          type)))
  ;; For a type application, recurse down into all the types
  (:method (subst-list (type tapp))
    (if (null subst-list)
        type  ; Fast path: no substitutions to apply
        (make-tapp
         :alias (mapcar (lambda (alias) (apply-substitution subst-list alias)) (ty-alias type))
         :from (apply-substitution subst-list (tapp-from type))
         :to (apply-substitution subst-list (tapp-to type)))))
  ;; Otherwise, do nothing
  (:method (subst-list (type ty))
    type)
  ;; Allow for calling on lists
  (:method (subst-list (type-list list))
    (if (null subst-list)
        type-list  ; Fast path: no substitutions to apply
        (mapcar (lambda (x) (apply-substitution subst-list x)) type-list))))



(defun pprint-substitution (stream sub &optional colon-p at-sign-p)
  (declare (ignore colon-p)
           (ignore at-sign-p))
  (write-string "#T" stream)
  (write (tyvar-id (substitution-from sub)) :stream stream)
  (write-string " +-> " stream)
  (write (substitution-to sub) :stream stream)
  nil)

(set-pprint-dispatch 'substitution 'pprint-substitution)
