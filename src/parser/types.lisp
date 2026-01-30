(defpackage #:coalton-impl/parser/types
  (:use
   #:cl
   #:coalton-impl/parser/base)
  (:shadowing-import-from
   #:coalton-impl/parser/base
   #:parse-error)
  (:local-nicknames
   (#:cst #:concrete-syntax-tree)
   (#:source #:coalton-impl/source)
   (#:util #:coalton-impl/util))
  (:export
   #:ty                                 ; STRUCT
   #:ty-list                            ; TYPE
   #:tyvar                              ; STRUCT
   #:make-tyvar                         ; CONSTRUCTOR
   #:tyvar-p                            ; FUNCTION
   #:tyvar-name                         ; ACCESSOR
   #:tyvar-list                         ; TYPE
   #:tycon                              ; STRUCT
   #:make-tycon                         ; CONSTRUCTOR
   #:tycon-p                            ; FUNCTION
   #:tycon-name                         ; ACCESSOR
   #:tycon-list                         ; TYPE
   #:tapp                               ; STRUCT
   #:make-tapp                          ; CONSTRUCTOR
   #:tapp-p                             ; FUNCTION
   #:tapp-from                          ; ACCESSOR
   #:tapp-to                            ; ACCESSOR
   #:ty-predicate                       ; STRUCT
   #:make-ty-predicate                  ; CONSTRUCTOR
   #:ty-predicate-class                 ; ACCESSOR
   #:ty-predicate-types                 ; ACCESSOR
   #:ty-predicate-list                  ; TYPE
   #:qualified-ty                       ; STRUCT
   #:make-qualified-ty                  ; CONSTRUCTOR
   #:qualified-ty-predicates            ; ACCESSOR
   #:qualified-ty-type                  ; ACCESSOR
   #:qualified-ty-list                  ; TYPE
   ;; Effecting function type
   #:ty-effecting                       ; STRUCT
   #:make-ty-effecting                  ; CONSTRUCTOR
   #:ty-effecting-p                     ; FUNCTION
   #:ty-effecting-domain                ; ACCESSOR
   #:ty-effecting-codomain              ; ACCESSOR
   #:ty-effecting-effects               ; ACCESSOR
   ;; Effect row types
   #:ty-effect-union                    ; STRUCT
   #:make-ty-effect-union               ; CONSTRUCTOR
   #:ty-effect-union-p                  ; FUNCTION
   #:ty-effect-union-members            ; ACCESSOR
   ;; Effect operation reference
   #:ty-effect-ref                      ; STRUCT
   #:make-ty-effect-ref                 ; CONSTRUCTOR
   #:ty-effect-ref-p                    ; FUNCTION
   #:ty-effect-ref-name                 ; ACCESSOR
   #:flatten-type                       ; FUNCTION
   #:parse-qualified-type               ; FUNCTION
   #:parse-type                         ; FUNCTION
   #:parse-predicate                    ; FUNCTION
   #:parse-effect-row                   ; FUNCTION
   ))

(in-package #:coalton-impl/parser/types)

;;;; # Type Parsing
;;;;
;;;; tyvar := <a keyword symbol>
;;;;
;;;; tycon := <a lisp symbol>
;;;;
;;;; class := <a lisp symbol>
;;;;
;;;; type-list := ty ty+
;;;;            | ty+ "->" type-list
;;;;
;;;; ty := tyvar
;;;;     | tycon
;;;;     | "(" type-list ")"
;;;;
;;;; ty-predicate := class ty+
;;;;
;;;; qualified-ty := ty
;;;;               | "(" ty-predicate "=>" type-list ")"
;;;;               | "(" ( "(" ty-predicate ")" )+ "=>" type-list ")"

(defstruct (ty (:constructor nil)
               (:copier nil))
  (location (util:required 'location) :type source:location :read-only t))

(defmethod source:location ((self ty))
  (ty-location self))

(defun ty-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'ty-p x)))

(deftype ty-list ()
  '(satisfies ty-list-p))

(defstruct (tyvar (:include ty)
                  (:copier nil))
  (name (util:required 'name) :type keyword :read-only t))

(defun tyvar-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'tyvar-p x)))

(deftype tyvar-list ()
  '(satisfies tyvar-list-p))

(defstruct (tycon (:include ty)
                  (:copier nil))
  (name (util:required 'name) :type identifier :read-only t))

(defun tycon-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'tycon-p x)))

(deftype tycon-list ()
  '(satisfies tycon-list-p))

(defstruct (tapp (:include ty)
                 (:copier nil))
  ;; The type being applied to
  (from (util:required 'from) :type ty :read-only t)
  ;; The type argument
  (to   (util:required 'to)   :type ty :read-only t))

;;;
;;; Effecting function types (for algebraic effects)
;;;
;;; Syntax: (A -> B ! E)
;;; Where E is an effect row: Pure | EffectName | (E1 | E2 | ...)
;;;

(defstruct (ty-effecting (:include ty)
                         (:copier nil))
  "A function type with effect tracking.

Represents (A -> B ! E) where:
- DOMAIN is the input type A
- CODOMAIN is the output type B
- EFFECTS is the effect row E"
  (domain   (util:required 'domain)   :type ty :read-only t)
  (codomain (util:required 'codomain) :type ty :read-only t)
  (effects  (util:required 'effects)  :type ty :read-only t))

(defstruct (ty-effect-union (:include ty)
                            (:copier nil))
  "A union of effects in an effect row.

Represents (E1 | E2 | ...) where MEMBERS is a list of effect types."
  (members (util:required 'members) :type ty-list :read-only t))

(defstruct (ty-effect-ref (:include ty)
                          (:copier nil))
  "A reference to a named effect.

NAME is a symbol identifying the effect (e.g., 'STATE, 'CONSOLE)."
  (name (util:required 'name) :type symbol :read-only t))

(defstruct (ty-predicate
            (:copier nil))
  (class    (util:required 'class)    :type identifier-src  :read-only t)
  (types    (util:required 'types)    :type ty-list         :read-only t)
  (location (util:required 'location) :type source:location :read-only t))

(defmethod source:location ((self ty-predicate))
  (ty-predicate-location self))

(defun ty-predicate-list-p (x)
  (and (alexandria:proper-list-p x)
       (every #'ty-predicate-p x)))

(deftype ty-predicate-list ()
  '(satisfies ty-predicate-list-p))

(defstruct (qualified-ty
            (:predicate nil)
            (:copier nil))
  (predicates (util:required 'predicates) :type ty-predicate-list :read-only t)
  (type       (util:required 'type)       :type ty                :read-only t)
  (location   (util:required 'location)   :type source:location   :read-only t))

(defmethod source:location ((self qualified-ty))
  (qualified-ty-location self))

(defun flatten-type (type)
  "If TYPE is a TAPP of the form ((((T1 T2) T3) T4) ...), then return
the list (T1 T2 T3 T4 ...). Otherwise, return (LIST TYPE)."
  (declare (type ty type)
           (values ty-list &optional))
  (let ((flattened-type nil))
    (loop :for from := type :then (tapp-from from)
          :while (typep from 'tapp)
          :do (push (tapp-to from) flattened-type)
          :finally (push from flattened-type))
    flattened-type))

(defun parse-qualified-type (form source)
  (declare (type cst:cst form))

  (if (cst:atom form)

      (make-qualified-ty
       :predicates nil
       :type (parse-type form source)
       :location (form-location source form))

      (multiple-value-bind (left right)
          (util:take-until (lambda (cst)
                             (and (cst:atom cst)
                                  (eq (cst:raw cst) 'coalton:=>)))
                           (cst:listify form))
        (cond
          ;; no predicates
          ((null right)
           (make-qualified-ty
            :predicates nil
            :type (parse-type-list left (form-location source form))
            :location (form-location source form)))

          ;; (=> T -> T)
          ((and (null left) right)
           (apply #'parse-error "Malformed type"
                  (cons (note source (cst:first form) "unnecessary `=>`")
                        (cond
                          ;; If this is the only thing in the list then don't suggest anything
                          ((cst:atom (cst:rest form))
                           nil)
                          ;; If there is nothing to the right of C then emit without list
                          ((cst:atom (cst:rest (cst:rest form)))
                           (list (help source form
                                       (lambda (existing)
                                         (subseq existing 4 (1- (length existing))))
                                       "remove `=>`")))
                          (t
                           (list (help source form
                                       (lambda (existing)
                                         (concatenate 'string
                                                      (subseq existing 0 1)
                                                      (subseq existing 4)))
                                       "remove `=>`")))))))

          ;; (... =>)
          ((null (rest right))
           (parse-error "Malformed type"
                        (note source (cst:source (cst:second form))
                              "missing type after `=>`")))

          (t
           (let (predicates)
             (if (cst:atom (first left))
                 (setf predicates (list (parse-predicate
                                         left
                                         (source:make-location source
                                                               (cons (car (cst:source (first left)))
                                                                     (cdr (cst:source (car (last left)))))))))

                 (loop :for pred :in left
                       :unless (cst:consp pred)
                         :do (parse-error "Malformed type predicate"
                                          (note source (cst:second form)
                                                "expected predicate"))
                       :do (push (parse-predicate (cst:listify pred)
                                                  (form-location source form))
                                 predicates)))

             (make-qualified-ty
              :predicates (reverse predicates)
              :type (parse-type-list
                     (cdr right)
                     (source:make-location source
                                           (cons (car (cst:source (second right)))
                                                 (cdr (cst:source (car (last right)))))))
              :location (form-location source form))))))))

(defun parse-predicate (forms location)
  (declare (type util:cst-list forms)
           (type source:location location)
           (values ty-predicate))

  (assert forms)
  (let ((source (source:location-source location)))
    (cond
      ;; (T) ... => ....
      ((not (cst:atom (first forms)))
       (parse-error "Malformed type predicate"
                    (note source (first forms)
                          "expected class name")
                    (help source (first forms)
                          (lambda (existing)
                            (subseq existing 1 (1- (length existing))))
                          "remove parentheses")))

      ;; "T" ... => ...
      ((not (identifierp (cst:raw (first forms))))
       (parse-error "Malformed type predicate"
                    (note source (first forms) "expected identifier")))

      (t
       (let ((name (cst:raw (first forms))))
         (when (= 1 (length forms))
           (parse-error "Malformed type predicate"
                        (note source (first forms)
                              "expected predicate")))

         (make-ty-predicate
          :class (make-identifier-src
                  :name name
                  :source-name (source:extract-source-text source (cst:source (first forms)))
                  :location (form-location source (first forms)))
          :types (loop :for form :in (cdr forms)
                       :collect (parse-type form source))
          :location location))))))

(defun parse-type (form source)
  (declare (type cst:cst form)
           (values ty &optional))

  (cond
    ((and (cst:atom form)
          (symbolp (cst:raw form))
          (cst:raw form))

     (if (equalp (symbol-package (cst:raw form)) util:+keyword-package+)
         (make-tyvar :name (cst:raw form) :location (form-location source form))
         (make-tycon :name (cst:raw form) :location (form-location source form))))

    ((cst:atom form)
     (parse-error "Malformed type"
                  (note source form "expected identifier")))

    ;; (T)
    ((cst:atom (cst:rest form))
     (parse-error "Malformed type"
                  (note source form "unexpected nullary type")))

    (t
     (parse-type-list (cst:listify form) (form-location source form)))))

(defun parse-type-list (forms location)
  (declare (type util:cst-list forms)
           (type source:location location)
           (values ty &optional))

  (assert forms)

  (if (= 1 (length forms))
      (parse-type (first forms) (source:location-source location))
      (multiple-value-bind (left right)
          (util:take-until (lambda (cst)
                             (and (cst:atom cst)
                                  (eq (cst:raw cst) 'coalton:->)))
                           forms)

        ;; (T ... ->)
        (cond
          ((and right (null (rest right)))
           (parse-error "Malformed function type"
                        (note (source:location-source location) (car right)
                              "missing return type")))

          ;; (-> ...)
          ((and (null left) right)
           (parse-error "Malformed function type"
                        (note (source:location-source location) (car right)
                              "invalid function syntax")))

          (t
           (let ((ty (parse-type (car left) (source:location-source location))))
             (loop :for form_ :in (cdr left)
                   :for ty_ := (parse-type form_ (source:location-source location))
                   :do (setf ty (make-tapp :from ty
                                           :to ty_
                                           :location location)))

             (if (null right)
                 ty

                 (make-tapp
                  :from (make-tapp
                         :from (make-tycon
                                :name 'coalton:Arrow
                                :location (form-location (source:location-source location)
                                                                (first right)))
                         :to ty
                         :location (source:make-location (source:location-source location)
                                                         (cons (car (source:location-span (ty-location ty)))
                                                               (cdr (cst:source (first right))))))
                  :to (parse-type-list
                       (cdr right)
                       (source:make-location (source:location-source location)
                                             (cons (car (cst:source (first right)))
                                                   (cdr (cst:source (car (last right)))))))
                  :location location))))))))

;;;
;;; Effect Row Parsing
;;;

(defun parse-effect-row (forms location)
  "Parse an effect row.

Effect rows can be:
- Pure (special identifier for no effects)
- A single effect name: State, Console, etc.
- A type variable: :e
- A union of effects: (E1 | E2 | ...)
- A parameterized effect: (State Integer)

FORMS: List of CST forms representing the effect row
LOCATION: Source location for error reporting"
  (declare (type list forms)
           (type source:location location)
           (values ty &optional))

  (let ((source (source:location-source location)))
    (cond
      ;; Single form
      ((= 1 (length forms))
       (let ((form (first forms)))
         (cond
           ;; Atom: effect name or type variable
           ((cst:atom form)
            (let ((raw (cst:raw form)))
              (cond
                ;; Pure - no effects (user writes "Pure", internal symbol is %pure-effect)
                ((string-equal (symbol-name raw) "PURE")
                 (make-tycon :name 'coalton::%pure-effect
                             :location (form-location source form)))
                ;; Type variable (keyword)
                ((and (symbolp raw)
                      (eq (symbol-package raw) util:+keyword-package+))
                 (make-tyvar :name raw
                             :location (form-location source form)))
                ;; Effect name
                ((symbolp raw)
                 (make-ty-effect-ref :name raw
                                     :location (form-location source form)))
                (t
                 (parse-error "Malformed effect row"
                              (note source form "expected effect name or type variable"))))))
           ;; List: union or parameterized effect
           (t
            (parse-effect-row-list (cst:listify form) location)))))

      ;; Multiple forms: should be a union written inline
      (t
       (parse-effect-row-list forms location)))))

(defun parse-effect-row-list (forms location)
  "Parse an effect row from a list of forms.

Handles:
- Effect union: (E1 | E2 | ...)
- Parameterized effect: (State Integer)"
  (declare (type util:cst-list forms)
           (type source:location location)
           (values ty &optional))

  (let ((source (source:location-source location)))
    ;; Check if it's a union (contains |)
    (multiple-value-bind (left right)
        (util:take-until (lambda (cst)
                           (and (cst:atom cst)
                                (let ((raw (cst:raw cst)))
                                  (and (symbolp raw)
                                       (string= (symbol-name raw) "|")))))
                         forms)
      (if right
          ;; It's a union
          (let ((members nil))
            ;; Parse left side
            (when left
              (push (parse-effect-row left location) members))
            ;; Parse right side (may have more |)
            (when (rest right)
              (let ((rest-effect (parse-effect-row (rest right) location)))
                (if (ty-effect-union-p rest-effect)
                    ;; Flatten nested unions
                    (setf members (append (reverse (ty-effect-union-members rest-effect)) members))
                    (push rest-effect members))))
            (make-ty-effect-union :members (nreverse members)
                                  :location location))
          ;; Not a union - parameterized effect or single effect in parens
          (if (= 1 (length forms))
              ;; Single item in parens: (Effect) -> Effect
              (parse-effect-row forms location)
              ;; Parameterized effect: (State :s)
              (let ((effect-name (first forms)))
                (unless (and (cst:atom effect-name)
                             (symbolp (cst:raw effect-name)))
                  (parse-error "Malformed parameterized effect"
                               (note source effect-name "expected effect name")))
                ;; Parse as type application
                (let ((base (make-ty-effect-ref :name (cst:raw effect-name)
                                                :location (form-location source effect-name))))
                  (loop :for form :in (rest forms)
                        :for ty := (parse-type form source)
                        :do (setf base (make-tapp :from base
                                                  :to ty
                                                  :location location)))
                  base)))))))
