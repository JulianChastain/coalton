(cl:in-package #:coalton-tests)

;; Simple tests to verify row type infrastructure
;; These check that the new row type constructs exist and can be used

(deftest test-row-empty-can-be-created ()
  (let ((row (tc:make-ty-row-empty)))
    (is (not (null row)))))

(deftest test-row-labeled-can-be-created ()
  (let ((row (tc:make-ty-row-labeled
                :label 'TestLabel
                :type tc:*string-type*
                :rest (tc:make-ty-row-empty))))
    (is (not (null row)))))

(deftest test-row-var-can-be-created ()
  (let ((var (tc:make-ty-row-var :id 1)))
    (is (not (null var)))))

(deftest test-krow-kind-exists ()
  (is (not (null tc:+krow+))))