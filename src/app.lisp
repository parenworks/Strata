;;;; -*- encoding:utf-8 -*-
;;;; Strata - Application container

(in-package #:strata.app)

(defvar *db-backend* nil
  "The active Fluxion PostgreSQL backend instance.")

(defvar *app* nil
  "The active Fluxion application instance.")

(defparameter *static-dir*
  (asdf:system-relative-pathname :strata "static/")
  "Path to the static file directory.")

(defun make-app (&key (port 4242))
  "Create the Fluxion application instance and register per-session component factories.
The shell-component factory is registered here so that every new browser
session automatically gets its own shell-component instance. Fluxion's
dispatch path looks up the component from the session when routing actions
to /action/strata-shell/<action-name>."
  (setf *app*
        (fluxion.server:make-fluxion-app
         :port port
         :server :woo
         :static-dir *static-dir*
         :session-ttl 3600
         :reaper-interval 60
         :request-log t))
  (fluxion.server:register-component-factory
   *app* "strata-shell" #'strata.components.shell:make-shell)
  (fluxion.server:register-component-factory
   *app* "strata-login" #'strata.components.login:make-login)
  (fluxion.server:register-component-factory
   *app* "strata-setup" #'strata.components.login:make-setup)
  (fluxion.server:register-component-factory
   *app* "strata-profile" #'strata.components.profile:make-profile)
  (fluxion.server:register-component-factory
   *app* "strata-inbox" #'strata.components.inbox:make-inbox)
  (fluxion.server:register-component-factory
   *app* "strata-search" #'strata.components.search:make-search)
  (fluxion.server:register-component-factory
   *app* "strata-admin" #'strata.components.admin:make-admin)
  *app*)

(defun connect-db (&key (database "strata_dev")
                        (user "strata")
                        (password "localtest123")
                        (host "localhost")
                        (port 5432))
  "Connect the PostgreSQL backend and ensure all tables exist."
  (setf *db-backend*
        (fxdb:make-postgresql-backend
         :database database
         :user user
         :password password
         :host host
         :port port))
  (db:connect *db-backend*)
  (strata.auth:setup-user-tables)
  (strata.migrations:ensure-schema)
  (format t "~&[strata] Schema ready.~%")
  (strata.push:ensure-vapid-keypair)
  (strata.jobs.notifications:start-notification-hooks)
  *db-backend*)
