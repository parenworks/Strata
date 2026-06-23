;;;; -*- encoding:utf-8 -*-
;;;; Strata tests - Package definitions

(defpackage #:strata.tests.fixtures
  (:use #:cl)
  (:export
   #:with-test-db
   #:make-workspace
   #:make-channel
   #:make-user
   #:make-post
   #:make-reply))

(defpackage #:strata.tests
  (:use #:cl #:fiveam #:strata.tests.fixtures))
