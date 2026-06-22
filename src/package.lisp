;;;; -*- encoding:utf-8 -*-
;;;; Strata - Package definitions

(defpackage #:strata.models.workspace
  (:use #:cl)
  (:local-nicknames (#:db    #:fluxion.db)
                    (#:fxdm  #:fluxion.db.model)
                    (#:mig   #:fluxion.migrate))
  (:export
   #:create-workspace
   #:find-workspace-by-id
   #:find-workspace-by-slug
   #:list-workspaces
   #:workspace-field))

(defpackage #:strata.models.channel
  (:use #:cl)
  (:local-nicknames (#:db    #:fluxion.db)
                    (#:fxdm  #:fluxion.db.model)
                    (#:mig   #:fluxion.migrate))
  (:export
   #:create-channel
   #:find-channel-by-id
   #:find-channel-by-slug
   #:list-channels-for-workspace
   #:list-channels-for-user
   #:list-subchannels
   #:touch-channel
   #:channel-field))

(defpackage #:strata.models.channel-member
  (:use #:cl)
  (:local-nicknames (#:db   #:fluxion.db)
                    (#:fxdm #:fluxion.db.model))
  (:export
   #:add-member
   #:remove-member
   #:member-p
   #:list-members
   #:list-channels-for-user
   #:member-field))

(defpackage #:strata.models.push-subscription
  (:use #:cl)
  (:local-nicknames (#:db   #:fluxion.db)
                    (#:fxdm #:fluxion.db.model))
  (:export
   #:save-subscription
   #:find-by-endpoint
   #:list-for-user
   #:delete-subscription
   #:subscription-field))

(defpackage #:strata.models.post
  (:use #:cl)
  (:local-nicknames (#:db    #:fluxion.db)
                    (#:fxdm  #:fluxion.db.model)
                    (#:hooks #:fluxion.hooks)
                    (#:mig   #:fluxion.migrate))
  (:export
   #:create-post
   #:find-post-by-id
   #:list-posts-for-channel
   #:set-post-status
   #:touch-post
   #:post-field
   #:+post-kinds+
   #:+post-statuses+))

(defpackage #:strata.models.reply
  (:use #:cl)
  (:local-nicknames (#:db    #:fluxion.db)
                    (#:fxdm  #:fluxion.db.model)
                    (#:mig   #:fluxion.migrate))
  (:export
   #:create-reply
   #:find-reply-by-id
   #:list-replies-for-post
   #:reply-field))

(defpackage #:strata.models.reaction
  (:use #:cl)
  (:local-nicknames (#:db    #:fluxion.db)
                    (#:fxdm  #:fluxion.db.model)
                    (#:mig   #:fluxion.migrate))
  (:export
   #:add-reaction
   #:remove-reaction
   #:list-reactions-for-target
   #:reaction-field))

(defpackage #:strata.models.mention
  (:use #:cl)
  (:local-nicknames (#:db    #:fluxion.db)
                    (#:fxdm  #:fluxion.db.model)
                    (#:mig   #:fluxion.migrate))
  (:export
   #:record-mention
   #:parse-and-record-mentions
   #:list-mentions-for-user
   #:mention-field))

(defpackage #:strata.models.bookmark
  (:use #:cl)
  (:local-nicknames (#:db    #:fluxion.db)
                    (#:fxdm  #:fluxion.db.model)
                    (#:mig   #:fluxion.migrate))
  (:export
   #:add-bookmark
   #:remove-bookmark
   #:bookmark-p
   #:list-bookmarks-for-user
   #:bookmark-field))

(defpackage #:strata.models.channel-read
  (:use #:cl)
  (:local-nicknames (#:db    #:fluxion.db)
                    (#:fxdm  #:fluxion.db.model)
                    (#:mig   #:fluxion.migrate))
  (:export
   #:mark-channel-read
   #:get-channel-read
   #:channel-read-field))

(defpackage #:strata.auth
  (:use #:cl)
  (:local-nicknames (#:fx   #:fluxion.server)
                    (#:auth #:fluxion.auth)
                    (#:user #:fluxion.user))
  (:export
   #:setup-user-tables
   #:any-users-p
   #:user-display-name
   #:user-id-from-session
   #:update-password))

(defpackage #:strata.components.login
  (:use #:cl)
  (:local-nicknames (#:fx     #:fluxion.server)
                    (#:comp   #:fluxion.components)
                    (#:auth   #:fluxion.auth)
                    (#:user   #:fluxion.user)
                    (#:events #:fluxion.events)
                    (#:render #:fluxion.render)
                    (#:ws     #:strata.models.workspace)
                    (#:chan   #:strata.models.channel))
  (:export
   #:login-component
   #:setup-component
   #:make-login
   #:make-setup
   #:render-login-page
   #:render-setup-page))

(defpackage #:strata.components.shell
  (:use #:cl)
  (:local-nicknames (#:fx     #:fluxion.server)
                    (#:comp   #:fluxion.components)
                    (#:fxdm   #:fluxion.db.model)
                    (#:user   #:fluxion.user)
                    (#:events #:fluxion.events)
                    (#:render #:fluxion.render))
  (:export
   #:shell-component
   #:make-shell
   #:render-page-for-session))

(defpackage #:strata.components.inbox
  (:use #:cl)
  (:local-nicknames (#:fx     #:fluxion.server)
                    (#:comp   #:fluxion.components)
                    (#:user   #:fluxion.user)
                    (#:render #:fluxion.render))
  (:export
   #:inbox-component
   #:make-inbox
   #:render-inbox-page))

(defpackage #:strata.components.thread
  (:use #:cl)
  (:local-nicknames (#:fx   #:fluxion.server)
                    (#:user #:fluxion.user))
  (:export #:render-thread-pane))

(defpackage #:strata.components.profile
  (:use #:cl)
  (:local-nicknames (#:fx     #:fluxion.server)
                    (#:comp   #:fluxion.components)
                    (#:auth   #:fluxion.auth)
                    (#:user   #:fluxion.user)
                    (#:events #:fluxion.events)
                    (#:render #:fluxion.render))
  (:export
   #:profile-component
   #:make-profile
   #:render-profile-page))

(defpackage #:strata.push
  (:use #:cl)
  (:local-nicknames (#:dex    #:dexador)
                    (#:quri   #:quri))
  (:export
   #:ensure-vapid-keypair
   #:vapid-public-key-b64
   #:*vapid-public-key-b64*
   #:send-push
   #:notify-user
   #:notify-mentioned-users))

(defpackage #:strata.jobs.notifications
  (:use #:cl)
  (:local-nicknames (#:hooks #:fluxion.hooks)
                    (#:fx   #:fluxion.server)
                    (#:bt   #:bordeaux-threads))
  (:export #:start-notification-hooks))

(defpackage #:strata.migrations
  (:use #:cl)
  (:local-nicknames (#:db #:fluxion.db))
  (:export
   #:ensure-schema))

(defpackage #:strata.app
  (:use #:cl)
  (:local-nicknames (#:db   #:fluxion.db)
                    (#:fxdb #:fluxion.db.postgresql))
  (:export
   #:*app*
   #:*db-backend*
   #:make-app
   #:connect-db))

(defpackage #:strata.server
  (:use #:cl)
  (:local-nicknames (#:db    #:fluxion.db)
                    (#:fxdb  #:fluxion.db.postgresql)
                    (#:mig   #:fluxion.migrate)
                    (#:fx    #:fluxion.server)
                    (#:app   #:strata.app)
                    (#:json  #:cl-json))
  (:export
   #:start
   #:stop
   #:run
   #:main
   #:*port*))

(defpackage #:strata
  (:use #:cl)
  (:export #:main))
