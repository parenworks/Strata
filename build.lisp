;;;; build.lisp - Build Strata as a standalone executable
;;;; Usage: sbcl --load build.lisp
;;;;
;;;; Produces: bin/strata
;;;;
;;;; The resulting binary accepts the same keyword arguments as
;;;; strata.server:run via command-line flags:
;;;;   --port 4242
;;;;   --db-name strata_dev
;;;;   --db-user strata
;;;;   --db-password secret
;;;;   --db-host localhost
;;;;   --db-port 5432

(require :asdf)

(ql:quickload "strata" :silent t)

(ql:quickload "clack-handler-woo" :silent t)

(ensure-directories-exist #P"bin/")

(format t "[strata] Building standalone executable...~%")

(asdf:clear-source-registry)
(asdf:clear-system "asdf")
(setf asdf:*central-registry* nil)

(sb-ext:save-lisp-and-die
 #P"bin/strata"
 :toplevel #'strata:main
 :executable t
 :purify t
 #+sb-core-compression :compression
 #+sb-core-compression 9)
