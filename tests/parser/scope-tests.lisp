;;;; Tests for scope tokens and scope sets
;;;;
;;;; These tests verify the basic building blocks of the hygienic macro system:
;;;; scope tokens for unique identification and scope sets for tracking lexical context.

(fiasco:define-test-package #:coalton-impl/parser/scope-tests
  (:use #:cl)
  (:local-nicknames
   (#:scope #:coalton-impl/parser/scope)))

(in-package #:coalton-impl/parser/scope-tests)

;;;
;;; Scope Token Tests
;;;

(deftest scope-token-creation ()
  "make-scope-token creates tokens with unique IDs"
  (let ((token (scope:make-scope-token)))
    (is (typep token 'scope:scope-token))
    (is (integerp (scope:scope-token-id token)))
    (is (>= (scope:scope-token-id token) 0))))

(deftest scope-token-uniqueness ()
  "Multiple tokens have different IDs"
  (let ((t1 (scope:make-scope-token))
        (t2 (scope:make-scope-token))
        (t3 (scope:make-scope-token)))
    (is (/= (scope:scope-token-id t1)
            (scope:scope-token-id t2)))
    (is (/= (scope:scope-token-id t2)
            (scope:scope-token-id t3)))
    (is (/= (scope:scope-token-id t1)
            (scope:scope-token-id t3)))))

;;;
;;; Scope Set Tests - Basic Operations
;;;

(deftest empty-scope-set-creation ()
  "empty-scope-set creates an empty set"
  (let ((set (scope:empty-scope-set)))
    (is (typep set 'scope:scope-set))
    (is (scope:scope-set-empty-p set))
    (is (= 0 (scope:scope-set-size set)))))

(deftest scope-set-add ()
  "scope-set-add adds tokens to sets"
  (let* ((token (scope:make-scope-token))
         (empty (scope:empty-scope-set))
         (with-token (scope:scope-set-add empty token)))
    ;; Original set unchanged (immutability)
    (is (scope:scope-set-empty-p empty))
    ;; New set contains token
    (is (not (scope:scope-set-empty-p with-token)))
    (is (= 1 (scope:scope-set-size with-token)))
    (is (scope:scope-set-member-p with-token token))))

(deftest scope-set-add-multiple ()
  "scope-set-add can add multiple tokens"
  (let* ((t1 (scope:make-scope-token))
         (t2 (scope:make-scope-token))
         (set (scope:scope-set-add
               (scope:scope-set-add (scope:empty-scope-set) t1)
               t2)))
    (is (= 2 (scope:scope-set-size set)))
    (is (scope:scope-set-member-p set t1))
    (is (scope:scope-set-member-p set t2))))

(deftest scope-set-add-idempotent ()
  "Adding the same token twice doesn't change the set"
  (let* ((token (scope:make-scope-token))
         (set1 (scope:scope-set-add (scope:empty-scope-set) token))
         (set2 (scope:scope-set-add set1 token)))
    (is (= 1 (scope:scope-set-size set2)))
    (is (scope:scope-set-equal set1 set2))))

(deftest scope-set-remove ()
  "scope-set-remove removes tokens from sets"
  (let* ((token (scope:make-scope-token))
         (with-token (scope:scope-set-add (scope:empty-scope-set) token))
         (without-token (scope:scope-set-remove with-token token)))
    ;; Original set unchanged
    (is (scope:scope-set-member-p with-token token))
    ;; Token removed from new set
    (is (not (scope:scope-set-member-p without-token token)))
    (is (scope:scope-set-empty-p without-token))))

(deftest scope-set-remove-nonexistent ()
  "Removing a non-existent token is a no-op"
  (let* ((t1 (scope:make-scope-token))
         (t2 (scope:make-scope-token))
         (set (scope:scope-set-add (scope:empty-scope-set) t1))
         (result (scope:scope-set-remove set t2)))
    (is (= 1 (scope:scope-set-size result)))
    (is (scope:scope-set-member-p result t1))))

;;;
;;; Flip Operation Tests - Critical for Hygiene
;;;

(deftest scope-set-flip-adds-when-absent ()
  "Flip adds a token when it's not present"
  (let* ((token (scope:make-scope-token))
         (empty (scope:empty-scope-set))
         (with-token (scope:scope-set-flip empty token)))
    (is (scope:scope-set-member-p with-token token))
    (is (= 1 (scope:scope-set-size with-token)))))

(deftest scope-set-flip-removes-when-present ()
  "Flip removes a token when it's present"
  (let* ((token (scope:make-scope-token))
         (with-token (scope:scope-set-add (scope:empty-scope-set) token))
         (without-token (scope:scope-set-flip with-token token)))
    (is (not (scope:scope-set-member-p without-token token)))
    (is (scope:scope-set-empty-p without-token))))

(deftest scope-set-flip-roundtrip ()
  "Flipping twice returns to original state"
  (let* ((token (scope:make-scope-token))
         (empty (scope:empty-scope-set))
         (flipped-once (scope:scope-set-flip empty token))
         (flipped-twice (scope:scope-set-flip flipped-once token)))
    (is (scope:scope-set-equal empty flipped-twice))))

(deftest scope-set-flip-preserves-other-tokens ()
  "Flip only affects the specified token"
  (let* ((t1 (scope:make-scope-token))
         (t2 (scope:make-scope-token))
         (set (scope:scope-set-add (scope:empty-scope-set) t1))
         (result (scope:scope-set-flip set t2)))
    ;; t1 still present
    (is (scope:scope-set-member-p result t1))
    ;; t2 now added
    (is (scope:scope-set-member-p result t2))
    (is (= 2 (scope:scope-set-size result)))))

(deftest scope-set-flip-hygiene-scenario ()
  "Simulates the hygiene algorithm: add then flip removes"
  ;; This simulates what happens to input syntax during macro expansion:
  ;; 1. Use-site scope is added to input
  ;; 2. Use-site scope is flipped on output (removing it from input-derived syntax)
  (let* ((use-scope (scope:make-scope-token))
         (original (scope:empty-scope-set))
         ;; Add use-scope (simulating pre-expansion)
         (with-use (scope:scope-set-add original use-scope))
         ;; Flip use-scope (simulating post-expansion)
         (after-flip (scope:scope-set-flip with-use use-scope)))
    ;; Input syntax returns to original state
    (is (scope:scope-set-equal original after-flip))))

(deftest scope-set-flip-only-s2-remains ()
  "Setup: empty -> add s1 -> add s2 -> flip s1 => Result: only s2"
  (let* ((s1 (scope:make-scope-token))
         (s2 (scope:make-scope-token))
         (set (scope:scope-set-flip
               (scope:scope-set-add
                (scope:scope-set-add (scope:empty-scope-set) s1)
                s2)
               s1)))
    (is (= 1 (scope:scope-set-size set)))
    (is (not (scope:scope-set-member-p set s1)))
    (is (scope:scope-set-member-p set s2))))

;;;
;;; Subset Tests
;;;

(deftest scope-set-empty-subset-of-any ()
  "Empty set is a subset of any set"
  (let* ((token (scope:make-scope-token))
         (empty (scope:empty-scope-set))
         (nonempty (scope:scope-set-add empty token)))
    (is (scope:scope-set-subset-p empty empty))
    (is (scope:scope-set-subset-p empty nonempty))))

(deftest scope-set-subset-proper ()
  "Proper subset detection"
  (let* ((t1 (scope:make-scope-token))
         (t2 (scope:make-scope-token))
         (small (scope:scope-set-add (scope:empty-scope-set) t1))
         (large (scope:scope-set-add small t2)))
    ;; {t1} is a proper subset of {t1, t2}
    (is (scope:scope-set-subset-p small large))
    ;; {t1, t2} is NOT a subset of {t1}
    (is (not (scope:scope-set-subset-p large small)))))

(deftest scope-set-subset-equality ()
  "Equal sets are subsets of each other"
  (let* ((token (scope:make-scope-token))
         (set1 (scope:scope-set-add (scope:empty-scope-set) token))
         (set2 (scope:scope-set-add (scope:empty-scope-set) token)))
    (is (scope:scope-set-subset-p set1 set2))
    (is (scope:scope-set-subset-p set2 set1))))

(deftest scope-set-subset-disjoint ()
  "Disjoint sets are not subsets of each other"
  (let* ((t1 (scope:make-scope-token))
         (t2 (scope:make-scope-token))
         (set1 (scope:scope-set-add (scope:empty-scope-set) t1))
         (set2 (scope:scope-set-add (scope:empty-scope-set) t2)))
    (is (not (scope:scope-set-subset-p set1 set2)))
    (is (not (scope:scope-set-subset-p set2 set1)))))

;;;
;;; Union and Intersection Tests
;;;

(deftest scope-set-union ()
  "Union combines two sets"
  (let* ((t1 (scope:make-scope-token))
         (t2 (scope:make-scope-token))
         (set1 (scope:scope-set-add (scope:empty-scope-set) t1))
         (set2 (scope:scope-set-add (scope:empty-scope-set) t2))
         (union (scope:scope-set-union set1 set2)))
    (is (= 2 (scope:scope-set-size union)))
    (is (scope:scope-set-member-p union t1))
    (is (scope:scope-set-member-p union t2))))

(deftest scope-set-union-with-empty ()
  "Union with empty set returns the other set"
  (let* ((token (scope:make-scope-token))
         (set (scope:scope-set-add (scope:empty-scope-set) token))
         (union (scope:scope-set-union set (scope:empty-scope-set))))
    (is (scope:scope-set-equal set union))))

(deftest scope-set-intersection ()
  "Intersection finds common elements"
  (let* ((t1 (scope:make-scope-token))
         (t2 (scope:make-scope-token))
         (t3 (scope:make-scope-token))
         (set1 (scope:scope-set-add
                (scope:scope-set-add (scope:empty-scope-set) t1)
                t2))
         (set2 (scope:scope-set-add
                (scope:scope-set-add (scope:empty-scope-set) t2)
                t3))
         (intersection (scope:scope-set-intersection set1 set2)))
    (is (= 1 (scope:scope-set-size intersection)))
    (is (scope:scope-set-member-p intersection t2))
    (is (not (scope:scope-set-member-p intersection t1)))
    (is (not (scope:scope-set-member-p intersection t3)))))

(deftest scope-set-intersection-disjoint ()
  "Intersection of disjoint sets is empty"
  (let* ((t1 (scope:make-scope-token))
         (t2 (scope:make-scope-token))
         (set1 (scope:scope-set-add (scope:empty-scope-set) t1))
         (set2 (scope:scope-set-add (scope:empty-scope-set) t2))
         (intersection (scope:scope-set-intersection set1 set2)))
    (is (scope:scope-set-empty-p intersection))))

;;;
;;; Equality Tests
;;;

(deftest scope-set-equal-empty ()
  "Two empty sets are equal"
  (is (scope:scope-set-equal (scope:empty-scope-set)
                              (scope:empty-scope-set))))

(deftest scope-set-equal-same-elements ()
  "Sets with same elements are equal"
  (let* ((t1 (scope:make-scope-token))
         (t2 (scope:make-scope-token))
         (set1 (scope:scope-set-add
                (scope:scope-set-add (scope:empty-scope-set) t1)
                t2))
         (set2 (scope:scope-set-add
                (scope:scope-set-add (scope:empty-scope-set) t2)
                t1)))
    (is (scope:scope-set-equal set1 set2))))

(deftest scope-set-equal-different-elements ()
  "Sets with different elements are not equal"
  (let* ((t1 (scope:make-scope-token))
         (t2 (scope:make-scope-token))
         (set1 (scope:scope-set-add (scope:empty-scope-set) t1))
         (set2 (scope:scope-set-add (scope:empty-scope-set) t2)))
    (is (not (scope:scope-set-equal set1 set2)))))

;;;
;;; Membership and Size Tests
;;;

(deftest scope-set-member-p ()
  "scope-set-member-p returns boolean"
  (let* ((t1 (scope:make-scope-token))
         (t2 (scope:make-scope-token))
         (set (scope:scope-set-add (scope:empty-scope-set) t1)))
    ;; Returns T or NIL, not arbitrary truthy value
    (is (eq t (scope:scope-set-member-p set t1)))
    (is (eq nil (scope:scope-set-member-p set t2)))))

(deftest scope-set-size ()
  "scope-set-size returns correct count"
  (let* ((t1 (scope:make-scope-token))
         (t2 (scope:make-scope-token))
         (t3 (scope:make-scope-token)))
    (is (= 0 (scope:scope-set-size (scope:empty-scope-set))))
    (is (= 1 (scope:scope-set-size
              (scope:scope-set-add (scope:empty-scope-set) t1))))
    (is (= 2 (scope:scope-set-size
              (scope:scope-set-add
               (scope:scope-set-add (scope:empty-scope-set) t1)
               t2))))
    (is (= 3 (scope:scope-set-size
              (scope:scope-set-add
               (scope:scope-set-add
                (scope:scope-set-add (scope:empty-scope-set) t1)
                t2)
               t3))))))

;;;
;;; Conversion Tests
;;;

(deftest scope-set->list ()
  "scope-set->list returns all tokens"
  (let* ((t1 (scope:make-scope-token))
         (t2 (scope:make-scope-token))
         (set (scope:scope-set-add
               (scope:scope-set-add (scope:empty-scope-set) t1)
               t2))
         (list (scope:scope-set->list set)))
    (is (= 2 (length list)))
    (is (member t1 list))
    (is (member t2 list))))

(deftest scope-set->list-empty ()
  "scope-set->list returns empty list for empty set"
  (is (null (scope:scope-set->list (scope:empty-scope-set)))))
