;;;; -*- encoding:utf-8 -*-
;;;; Strata - Test system definition

(defsystem "strata-tests"
  :name "strata-tests"
  :description "FiveAM test suite for Strata model layer."
  :depends-on ("strata" "fiveam")
  :serial t
  :components
  ((:module "tests"
    :serial t
    :components
    ((:file "package")
     (:file "fixtures")
     (:file "models")
     (:file "api")
         (:file "mcp")))))
