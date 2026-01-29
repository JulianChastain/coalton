;;;; Tangled from algorithm.clw
;;;; DO NOT EDIT - edit the .clw file instead


(defpackage #:coalton-impl/algorithm/tarjan-scc
  (:use #:cl)
  (:export
   #:tarjan-scc))

(in-package #:coalton-impl/algorithm/tarjan-scc)



(defstruct tarjan-node
  (index    nil :type (or null integer))
  (low-link nil :type integer)
  (on-stack nil :type boolean))



(declaim (ftype (function (list) list) tarjan-scc))
(defun tarjan-scc (graph)
  "Find strongly connected components in a directed graph using Tarjan's algorithm.

GRAPH is a list of vertices and their dependencies in the format:
  ((vertex-name dependency-1 dependency-2 ...)
   (vertex-name-2 dependency-a dependency-b ...)
   ...)

Where all vertex names and dependencies are symbols.

Returns a list of SCCs, where each SCC is a list of mutually dependent vertices.
The SCCs are returned in reverse topological order, meaning that if SCC-A depends
on vertices in SCC-B, then SCC-B will appear before SCC-A in the result list.

Example:
  (tarjan-scc '((a b c) (b c) (c)))
  => ((C) (B) (A))  ; C has no deps, B depends on C, A depends on B and C

With mutually recursive definitions:
  (tarjan-scc '((f g) (g f) (h)))
  => ((H) (F G))    ; H is independent, F and G are mutually recursive"
  (let ((symbol-to-index (make-hash-table))
        (edge-vector (make-array (length graph))))
    ;; Populate table mapping graph vertices to indices
    (loop :for (vertex . edges) :in graph
          :for i :from 0
          :do (setf (gethash vertex symbol-to-index) i
                    (aref edge-vector i) edges))
    (let ((index 0)
          (stack nil)
          (node-data (make-array (length graph)))
          (sccs nil))

      ;; Initialize our node-data vector
      (dotimes (i (length graph))
        (setf (aref node-data i)
              (make-tarjan-node :index nil
                                :low-link 0
                                :on-stack nil)))

      (labels ((visit (vertex)
                 (let ((vertex-index (gethash vertex symbol-to-index)))
                   ;; If we have already visited the node then there
                   ;; is nothing to do.
                   (when (not (null (tarjan-node-index (aref node-data vertex-index))))
                     (return-from visit))

                   ;; Set the index and lowlink of the current vertex
                   ;; to the current index and increment index
                   (setf (tarjan-node-index (aref node-data vertex-index)) index
                         (tarjan-node-low-link (aref node-data vertex-index)) index)
                   (incf index)

                   ;; Add the current vertex to the stack
                   (setf (tarjan-node-on-stack (aref node-data vertex-index)) t)
                   (push vertex stack)

                   ;; Check all neighbors
                   (let ((edges (aref edge-vector vertex-index)))
                     (dolist (edge edges)
                       (let ((edge-index (gethash edge symbol-to-index)))
                         (cond
                           ;; EDGE has been visited
                           ((not (null (tarjan-node-index (aref node-data edge-index))))
                            (when (tarjan-node-on-stack (aref node-data edge-index))
                              (setf (tarjan-node-low-link (aref node-data vertex-index))
                                    (min (tarjan-node-low-link (aref node-data vertex-index))
                                         (tarjan-node-index (aref node-data edge-index))))))
                           ;; EDGE has not been visited
                           (t
                            ;; If we haven't seen this edge yet then visit it
                            (visit edge)
                            ;; And update our lowlink if theirs is smaller
                            (setf (tarjan-node-low-link (aref node-data vertex-index))
                                  (min (tarjan-node-low-link (aref node-data vertex-index))
                                       (tarjan-node-low-link (aref node-data edge-index)))))))))

                   ;; If we are a root node then pop the stack and add
                   ;; ourself to the sccs
                   (when (= (tarjan-node-low-link (aref node-data vertex-index))
                            (tarjan-node-index (aref node-data vertex-index)))
                     (let ((new-scc nil))
                       (loop :for item = (pop stack)
                             :do (let ((item-index (gethash item symbol-to-index)))
                                   (setf (tarjan-node-on-stack (aref node-data item-index)) nil)
                                   (push item new-scc))
                             :while (not (eql vertex item)))
                       (push new-scc sccs))))))
        (dolist (vertex graph)
          (visit (car vertex)))
        (nreverse sccs)))))



(defpackage #:coalton-impl/algorithm/immutable-map
  (:use #:cl)
  (:export
   #:immutable-map                      ; STRUCT
   #:make-immutable-map                 ; CONSTRUCTOR
   #:immutable-map-data                 ; ACCESSOR
   #:immutable-map-lookup               ; FUNCTION
   #:immutable-map-set                  ; FUNCTION
   #:immutable-map-set-multiple         ; FUNCTION
   #:immutable-map-keys                 ; FUNCTION
   #:immutable-map-diff                 ; FUNCTION
   #:immutable-map-remove               ; FUNCTION
   ))

(in-package #:coalton-impl/algorithm/immutable-map)



(defstruct immutable-map
  (data (fset:empty-map) :type fset:map :read-only t))

(defmethod make-load-form ((self immutable-map) &optional env)
  (make-load-form-saving-slots self :environment env))



(defun immutable-map-lookup (m key)
  "Lookup KEY in M"
  (declare (type immutable-map m)
           (values t boolean &optional))
  (fset:lookup (immutable-map-data m) key))



(defun immutable-map-set (m key value &optional (constructor #'make-immutable-map))
  "Set KEY to VALUE in M"
  (declare (type immutable-map m))
  (funcall constructor :data (fset:with (immutable-map-data m) key value)))



(defun immutable-map-set-multiple (m items &optional (constructor #'make-immutable-map))
  "Create an IMMUTABLE-MAP from M with ITEMS set as bindings"
  (declare (type immutable-map m)
           (type list items)
           (values immutable-map &optional))
  (let ((map (immutable-map-data m)))
    (loop :for (key . value) :in items
          :do (setf map (fset:with map key value)))
    (funcall constructor :data map)))



(defun immutable-map-keys (m)
  (declare (type immutable-map m))
  "Return a unique list containing the keys in M and its parents"
  (declare (type immutable-map m))
  (fset:convert 'list (fset:domain (immutable-map-data m))))



(defun immutable-map-diff (m1 m2 &optional (constructor #'make-immutable-map))
  "Returns the elements that appear in M1 but not M2"
  (declare (type immutable-map m1 m2)
           (values immutable-map &optional))
  (funcall constructor :data (fset:map-difference-2 (immutable-map-data m1)
                                                    (immutable-map-data m2))))



(defun immutable-map-remove (m key &optional (constructor #'make-immutable-map))
  (declare (type immutable-map m)
           (values immutable-map &optional))
  (funcall constructor :data (fset:less (immutable-map-data m) key)))



(defpackage #:coalton-impl/algorithm/immutable-listmap
  (:use #:cl)
  (:export
   #:immutable-listmap                  ; STRUCT
   #:make-immutable-listmap             ; CONSTRUCTOR
   #:immutable-listmap-data             ; ACCESSOR
   #:immutable-listmap-lookup           ; FUNCTION
   #:immutable-listmap-push             ; FUNCTION
   #:immutable-listmap-replace          ; FUNCTION
   #:immutable-listmap-diff             ; FUNCTION
   ))

(in-package #:coalton-impl/algorithm/immutable-listmap)



(defstruct immutable-listmap
  (data (fset:empty-map (fset:empty-seq)) :type fset:map :read-only t))



(defun immutable-listmap-lookup (m key &key no-error)
  "Lookup key in M"
  (declare (type immutable-listmap m)
           (type (or fixnum symbol) key)
           (type boolean no-error)
           (values fset:seq))
  (multiple-value-bind (value present-p)
      (fset:lookup (immutable-listmap-data m) key)
    (unless (or present-p no-error)
      (error "Undefined key ~a" key))
    value))



(defun immutable-listmap-push (m key value &optional (constructor #'make-immutable-listmap))
  "Push value to the list at KEY in M"
  (declare (type immutable-listmap m)
           (type (or fixnum symbol) key)
           (values immutable-listmap &optional))

  (let ((map (immutable-listmap-data m)))
    (funcall constructor :data (fset:with map key (fset:with-first (fset:lookup map key) value)))))



(defun immutable-listmap-replace (m key index value &optional (constructor #'make-immutable-listmap))
  "Replace value at INDEX with VALUE in the map at KEY in M."
  (declare (type immutable-listmap m)
           (type (or fixnum symbol) key)
           (type fixnum index)
           (values immutable-listmap &optional))
  (let ((map (immutable-listmap-data m)))
    (funcall constructor :data (fset:with map key (fset:with (fset:lookup map key) index value)))))



(defun immutable-listmap-diff (m1 m2 &optional (constructor #'make-immutable-listmap))
  "Return a new SHADOW-LIST with elements in M1 but not M2."
  (let ((diff-map (fset:empty-map)))
    (fset:do-map (k v1 (immutable-listmap-data m1))
      (multiple-value-bind (v2 found)
          (fset:lookup (immutable-listmap-data m2) k)
        (if found
            ;; If both have this key then diff the seq
            (let ((seq-diff (fset:convert 'fset:seq
                                     (fset:set-difference (fset:range v1)
                                                          (fset:range v2)))))
              (setf diff-map (fset:with diff-map k seq-diff)))
            ;; Otherwise save the whole seq
            (setf diff-map (fset:with diff-map k v1)))))
    (funcall constructor :data diff-map)))



(uiop:define-package #:coalton-impl/algorithm
  (:documentation "Implementation of generic algorithms used by COALTON. This is a package private to the COALTON system and is not intended for public use.")
  (:use)
  (:mix-reexport
   #:coalton-impl/algorithm/tarjan-scc
   #:coalton-impl/algorithm/immutable-map
   #:coalton-impl/algorithm/immutable-listmap))


