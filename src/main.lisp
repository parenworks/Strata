;;;; -*- encoding:utf-8 -*-
;;;; Strata - Top-level entry point package
;;;;
;;;; The strata package exists solely so build.lisp can reference strata:main
;;;; as a clean entry point symbol. The real implementation lives in
;;;; strata.server:main; this just delegates.

(in-package #:strata)

(defun main ()
  "Top-level entry point for the Strata standalone binary.
Delegates to strata.server:main which parses command-line flags and
calls strata.server:run to connect to the database and start the server."
  (strata.server:main))
