;;;; -*- encoding:utf-8 -*-
;;;; Strata - A structured team workspace

(defsystem "strata"
  :name "strata"
  :version "0.1.0"
  :author "Glenn Thompson"
  :licence "MIT"
  :description "A structured team workspace where threads resurface and posts are typed objects."
  :depends-on ("fluxion"
               "fluxion/db"
               "fluxion/db-pg"
               "fluxion/migrate"
               "fluxion/user"
               "fluxion/auth"
               "fluxion/hooks"
               "fluxion/rate"
               "fluxion/cache"
               "fluxion/api"
               "fluxion/log"
               "fluxion/config"
               "bordeaux-threads"
               "cl-json"
               "cl-ppcre"
               "local-time"
               "dexador"
               "cl-base64"
               "quri")
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "package")
     (:module "models"
      :serial t
      :components
      ((:file "workspace")
       (:file "channel")
       (:file "channel-member")
       (:file "push-subscription")
       (:file "post")
       (:file "reply")
       (:file "reaction")
       (:file "mention")
       (:file "bookmark")
       (:file "channel-read")))
     (:module "migrations"
      :serial t
      :components
      ((:file "all")))
     (:file "auth")
     (:file "push")
     (:module "jobs"
      :serial t
      :components
      ((:file "notifications")))
     (:module "components"
      :serial t
      :components
      ((:file "inbox")
       (:file "thread")
       (:file "shell")
       (:file "login")
       (:file "profile")))
     (:file "app")
     (:file "server")
     (:file "main")))))
