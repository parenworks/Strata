;;;; -*- encoding:utf-8 -*-
;;;; Strata - Shell component (full app UI)
;;;;
;;;; Renders the three-column layout: workspace rail, channel sidebar,
;;;; main panel (channel header + post feed + composer).

(in-package #:strata.components.shell)

;;; -------------------------------------------------------
;;; Helpers
;;; -------------------------------------------------------

(defun initial (name)
  "Return the first character of NAME uppercased, for avatar display."
  (if (and name (plusp (length name)))
      (string (char-upcase (char name 0)))
      "?"))

(defun post-author-name (author-id)
  "Return a display name string for AUTHOR-ID (integer), or \"?\" on failure."
  (handler-case
      (let ((u (strata.auth:get-user-by-id author-id)))
        (if u
            (or (strata.auth:user-display-name u)
                (user:user-username u)
                "?")
            "?"))
    (error () "?")))

(defun format-post-time (universal-time)
  "Format a universal-time integer as a short human-readable time."
  (when universal-time
    (multiple-value-bind (sec min hour day mon year)
        (decode-universal-time universal-time)
      (declare (ignore sec))
      (format nil "~2,'0d ~a ~d at ~2,'0d:~2,'0d"
              day
              (nth (1- mon) '("Jan" "Feb" "Mar" "Apr" "May" "Jun"
                              "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))
              year hour min))))

;;; -------------------------------------------------------
;;; DB helpers
;;; -------------------------------------------------------

(defun channel-field (ch f)
  "Return field F from channel data-model CH."
  (strata.models.channel:channel-field ch f))

(defun post-field (p f)
  "Return field F from post data-model P."
  (strata.models.post:post-field p f))

(defun load-member-channel-ids (user-id)
  "Return the list of channel-id integers USER-ID is explicitly a member of."
  (handler-case
      (strata.models.channel-member:list-channels-for-user user-id)
    (error () nil)))

(defun load-channels (user-id)
  "Return top-level channel data-models visible to USER-ID, excluding archived."
  (handler-case
      (let* ((member-ids (load-member-channel-ids user-id))
             (all (strata.models.channel:list-channels-for-user (load-workspace-id) user-id member-ids)))
        (remove-if (lambda (ch)
                     (string= (strata.models.channel:channel-field ch "visibility")
                               "archived"))
                   all))
    (error () nil)))

(defun load-subchannels (channel-id)
  "Return sub-channel data-models for CHANNEL-ID, or NIL."
  (handler-case
      (strata.models.channel:list-subchannels channel-id)
    (error () nil)))

(defun load-posts (channel-slug)
  "Return open post data-models for CHANNEL-SLUG, or NIL if DB is unavailable."
  (handler-case
      (let ((ch (strata.models.channel:find-channel-by-slug (load-workspace-id) channel-slug)))
        (when ch
          (strata.models.post:list-posts-for-channel
           (fxdm:model-id ch) :limit 50)))
    (error () nil)))

(defun load-resolved-posts (channel-slug)
  "Return resolved/decided/done post data-models for CHANNEL-SLUG."
  (handler-case
      (let ((ch (strata.models.channel:find-channel-by-slug (load-workspace-id) channel-slug)))
        (when ch
          (strata.models.post:list-posts-for-channel
           (fxdm:model-id ch) :include-resolved t :limit 20)))
    (error () nil)))

(defun load-reactions (post-id)
  "Return an alist of (emoji . count) for POST-ID."
  (handler-case
      (let* ((recs (strata.models.reaction:list-reactions-for-target "post" post-id))
             (tbl (make-hash-table :test 'equal)))
        (dolist (r recs)
          (let ((e (strata.models.reaction:reaction-field r "emoji")))
            (incf (gethash e tbl 0))))
        (let ((pairs nil))
          (maphash (lambda (k v) (push (cons k v) pairs)) tbl)
          (sort pairs #'string< :key #'car)))
    (error () nil)))

(defun load-reply-count (post-id)
  "Return the number of replies for POST-ID."
  (handler-case
      (length (strata.models.reply:list-replies-for-post post-id))
    (error () 0)))

(defun load-post-edits (post-id)
  "Return edit history rows for POST-ID, newest first."
  (handler-case
      (strata.models.post-edit:list-edits-for-post post-id)
    (error () nil)))

(defun load-attachments (target-type target-id)
  "Return attachments for TARGET-TYPE (:post or :reply) and TARGET-ID."
  (handler-case
      (if (eq target-type :post)
          (strata.models.attachment:list-attachments-for-post target-id)
          (strata.models.attachment:list-attachments-for-reply target-id))
    (error () nil)))

(defun render-attachment-list (attachments)
  "Emit HTML for a list of attachment data-models.
Wrapped in SPINNERET:WITH-HTML so the tag forms emit into the caller's
current *HTML* stream rather than being read as undefined functions."
  (when attachments
    (spinneret:with-html
      (:div :class "attachment-list"
        (dolist (att attachments)
          (let* ((uuid  (strata.models.attachment:attachment-field att "uuid"))
                 (fname (strata.models.attachment:attachment-field att "filename"))
                 (ctype (or (strata.models.attachment:attachment-field att "content_type")
                            "application/octet-stream"))
                 (url   (format nil "/uploads/~A/~A" uuid fname))
                 (image-p (and (stringp ctype)
                               (search "image/" (string-downcase ctype)))))
            (:div :class "attachment-item"
              (if image-p
                  (:a :href url :target "_blank" :class "attachment-image-link"
                    (:img :src url :alt fname :class "attachment-thumbnail"
                          :loading "lazy"))
                  (:a :href url :target "_blank" :class "attachment-file-link"
                    (:span :class "attachment-icon" "📎")
                    (:span :class "attachment-filename" fname))))))))))

(defun load-bookmarked-ids (user-id)
  "Return a list of post-id integers bookmarked by USER-ID."
  (handler-case
      (mapcar (lambda (b) (strata.models.bookmark:bookmark-field b "post_id"))
              (strata.models.bookmark:list-bookmarks-for-user user-id))
    (error () nil)))

(defun session-display-name (session)
  "Return a display name string for the current session user, or \"Guest\"."
  (let ((u (fx:session-user session)))
    (if u
        (or (strata.auth:user-display-name u)
            (user:user-username u)
            "User")
        "Guest")))

(defun session-author-id (session)
  "Return the integer user ID from SESSION, or 0 for unauthenticated."
  (strata.auth:user-id-from-session session))

(defun load-workspace-id ()
  "Return the integer _id of the default workspace, or 1 as fallback."
  (handler-case
      (let ((ws (strata.models.workspace:find-workspace-by-slug "default")))
        (if ws (fxdm:model-id ws) 1))
    (error () 1)))

(defun load-workspace-name ()
  "Return the display name of the default workspace, or \"Strata\" as fallback."
  (handler-case
      (let ((ws (strata.models.workspace:find-workspace-by-slug "default")))
        (if ws (strata.models.workspace:workspace-field ws "display_name") "Strata"))
    (error () "Strata")))

;;; Fallback stub channels used when DB has no data yet
(defparameter *stub-channels*
  '(("general" . "general") ("dev" . "dev") ("design" . "design")))

;;; -------------------------------------------------------
;;; Component
;;; -------------------------------------------------------

(fluxion.components:defcomponent shell-component
  :id "strata-shell"
  :slots ((active-channel     :initform "general" :accessor shell-active-channel)
          (thread-post-id     :initform nil       :accessor shell-thread-post-id)
          (expanded-thread-id :initform nil       :accessor shell-expanded-thread-id)
          (editing-post-id    :initform nil       :accessor shell-editing-post-id)
          (managing-channel-id       :initform nil      :accessor shell-managing-channel-id)
          (creating-channel-p        :initform nil      :accessor shell-creating-channel-p)
          (creating-channel-under-id :initform nil      :accessor shell-creating-channel-under-id))

  :render
  (let* ((session        (fluxion.components:component-session self))
         (raw-username   (let ((u (when session (fx:session-user session))))
                           (when u (user:user-username u))))
         (username       (if session (session-display-name session) "Guest"))
         (user-id        (if session (session-author-id session) 0))
         (adminp         (when raw-username
                           (handler-case (strata.auth:is-admin-p raw-username)
                             (error () nil))))
         (workspace-name (load-workspace-name))
         (db-channels    (load-channels user-id))
         (db-posts       (load-posts (shell-active-channel self)))
         (channels       db-channels)
         (posts          db-posts)
         (active-ch      (find (shell-active-channel self) channels
                                :test #'string=
                                :key (lambda (ch) (strata.models.channel:channel-field ch "slug"))))
         (active-channel-id (when active-ch (fxdm:model-id active-ch)))
         (thread-id      (shell-thread-post-id self))
         (bookmarked-ids (load-bookmarked-ids user-id)))
    (spinneret:with-html-string
      (:div :id (fluxion.components:component-id self)
            :class "strata-shell"

        (when (shell-creating-channel-p self)
          (:div :class "modal-overlay"
            (:div :class "modal-dialog"
              (:div :class "modal-header"
                (:h2 :class "modal-title" "New Channel")
                (:button :class "modal-close" :type "button"
                         :data-on-click "/action/strata-shell/hide-new-channel"
                         "✕"))
              (:form :class "modal-form"
                     :data-on-submit "/action/strata-shell/create-channel"
                (:div :class "modal-field"
                  (:label :for "new-ch-name" "Channel name")
                  (:input :class "modal-input" :id "new-ch-name" :name "name"
                          :placeholder "e.g. general" :required t :autofocus t))
                (:div :class "modal-field"
                  (:label :for "new-ch-slug" "Slug")
                  (:input :class "modal-input" :id "new-ch-slug" :name "slug"
                          :placeholder "e.g. general (no spaces)")
                  (:p :class "modal-hint" "Lowercase letters, numbers, and hyphens only."))
                (:div :class "modal-field"
                  (:label :for "new-ch-kind" "Type")
                  (:select :class "modal-select" :id "new-ch-kind" :name "kind"
                    (:option :value "open" "Public - anyone can join")
                    (:option :value "private" "Private - invite only")))
                (let ((under-id (shell-creating-channel-under-id self)))
                  (if under-id
                      (:input :type "hidden" :name "parent_channel_id" :value (princ-to-string under-id))
                      (:div :class "modal-field"
                        (:label :for "new-ch-parent" "Parent channel (optional)")
                        (:select :class "modal-select" :id "new-ch-parent" :name "parent_channel_id"
                          (:option :value "" "None (top-level channel)")
                          (dolist (ch channels)
                            (let ((ch-id (fxdm:model-id ch))
                                  (ch-name (strata.models.channel:channel-field ch "name")))
                              (:option :value (princ-to-string ch-id) ch-name)))))))
                (:div :class "modal-actions"
                  (:button :type "button" :class "modal-btn-ghost"
                           :data-on-click "/action/strata-shell/hide-new-channel"
                           "Cancel")
                  (:button :type "submit" :class "modal-btn-primary"
                           "Create channel"))))))


        ;; --- Workspace rail ---
        (:nav :class "workspace-rail" :aria-label "Workspaces"
          (:div :class "workspace-avatar active" :title "Strata"
            (initial username))
          (:div :class "workspace-rail-divider")
          (:button :class "workspace-add-btn" :title "Add workspace" "+ "))

        ;; --- Channel sidebar ---
        (:aside :class "channel-sidebar"
          (:div :class "channel-sidebar-header"
            (:div :class "workspace-name" workspace-name)
            (:div :class "user-status-row"
              (:div :class "user-avatar-sm" (initial username))
              (:a :href "/profile"
                  :class "user-name-sm"
                  :style "text-decoration:none;color:inherit;"
                  :title "Edit profile"
                  username))
            (when adminp
              (:a :href "/admin"
                  :class "sidebar-admin-link"
                  :title "Admin panel"
                  "Admin")))

          (:div :class "channel-list-scroll"
            (:div :class "channel-section-label"
              (:span "Channels")
              (:button :class "channel-section-add"
                       :title "New channel"
                       :type "button"
                       :data-on-click "/action/strata-shell/show-new-channel"
                       "+ "))

            (if channels
                (dolist (ch channels)
                  (let* ((slug     (channel-field ch "slug"))
                         (name     (channel-field ch "name"))
                         (ch-id   (fxdm:model-id ch))
                         (kind    (channel-field ch "kind"))
                         (subs    (load-subchannels ch-id))
                         (active-p (string= slug (shell-active-channel self))))
                    (:div :class (if active-p "channel-item active" "channel-item")
                      (:span :class "channel-sigil"
                             :data-on-click (format nil "/action/strata-shell/switch-channel?slug=~A" slug)
                             (if (string= kind "private") "🔒" "#"))
                      (:span :class "channel-name"
                             :data-on-click (format nil "/action/strata-shell/switch-channel?slug=~A" slug)
                             name)
                      (when active-p
                        (:button :class "channel-settings-btn"
                                 :title "Channel settings"
                                 :type "button"
                                 :data-on-click (format nil "/action/strata-shell/manage-channel?id=~A" ch-id)
                                 "⚙")))
                    (when subs
                      (dolist (sub subs)
                        (let* ((sub-slug (channel-field sub "slug"))
                               (sub-name (channel-field sub "name"))
                               (sub-active-p (string= sub-slug (shell-active-channel self))))
                          (:div :class (if sub-active-p "channel-item active" "channel-item")
                                :style "padding-left:28px;"
                                :data-on-click (format nil "/action/strata-shell/switch-channel?slug=~A" sub-slug)
                            (:span :class "channel-sigil" "#")
                            (:span :class "channel-name" sub-name)))))))
                (dolist (pair *stub-channels*)
                  (let* ((slug     (car pair))
                         (name     (cdr pair))
                         (active-p (string= slug (shell-active-channel self))))
                    (:div :class (if active-p "channel-item active" "channel-item")
                          :data-on-click (format nil "/action/strata-shell/switch-channel?slug=~A" slug)
                      (:span :class "channel-sigil" "#")
                      (:span :class "channel-name" name))))))

          (:div :class "channel-sidebar-footer"
            (:button :id "theme-toggle-btn"
                     :class "theme-toggle"
                     :onclick "strataToggleTheme()"
                     :type "button"
                     "◑ Dark mode")
            (:a :href "/inbox"
                :class "theme-toggle"
                :style "display:block;margin-top:6px;text-decoration:none;text-align:left;"
                "✉ Inbox")
            (:a :href "/search"
                :class "theme-toggle"
                :style "display:block;margin-top:6px;text-decoration:none;text-align:left;"
                "⌕ Search")
            (:button :class "theme-toggle"
                     :type "button"
                     :style "margin-top:6px;"
                     :data-on-click "/action/strata-shell/logout"
                     "⎋ Sign out")))

        ;; --- Main panel ---
        (:div :class "main-panel"

          ;; Mobile toolbar (hamburger + title, hidden on desktop)
          (:div :class "mobile-toolbar"
            (:button :class "mobile-toolbar-btn" :type "button"
                     :title "Open channels"
                     :onclick "strataMobileSidebarOpen()"
                     "☰")
            (:span :class "mobile-toolbar-title"
              "#" (shell-active-channel self)))

          ;; Channel header
          (:div :class "channel-header"
            (:span :class "channel-header-hash" "#")
            (:span :class "channel-header-name" (shell-active-channel self))
            (:div :class "header-actions"
              (:button :class "header-btn" :title "Search" :type "button" "🔍")
              (:button :class "header-btn" :title "Members" :type "button" "👥")
              (:button :class "header-btn" :title "Pinned" :type "button" "📌")
              (when active-channel-id
                (:button :class "header-btn" :title "Add sub-channel" :type "button"
                         :data-on-click (format nil "/action/strata-shell/create-sub-channel?id=~A" active-channel-id)
                         "⊕"))
              (:button :id "pwa-install-btn" :type "button"
                       :hidden t
                       :onclick "strataInstallApp()"
                       "⬇ Install")))

          ;; Post feed
          (:div :id "post-feed" :class (if thread-id "post-feed thread-open" "post-feed")
            (:div :class "feed-date-divider"
              (:span :class "feed-date-label" "Today"))
            (if posts
                (dolist (post posts)
                  (let* ((post-id  (fxdm:model-id post))
                         (author   (post-author-name (post-field post "author_id")))
                         (kind     (or (post-field post "kind") "message"))
                         (status   (or (post-field post "status") "open"))
                         (body     (or (post-field post "body") ""))
                         (pinned   (eql 1 (post-field post "pinned")))
                         (reacts       (load-reactions post-id))
                         (replies      (load-reply-count post-id))
                         (attachments  (load-attachments :post post-id)))
                    (:article :class (if pinned "post-card pinned" "post-card")
                      (:div :class "post-avatar" (initial author))
                      (:div :class "post-content"
                        (:div :class "post-meta"
                          (:span :class "post-author" author)
                          (:span :class "post-time"
                                 (format-post-time (post-field post "created_at")))
                          (unless (string= kind "message")
                            (:span :class (format nil "post-kind-badge post-kind-~A" kind) kind))
                          (unless (string= status "open")
                            (:span :class (format nil "post-status-badge post-status-~A" status) status))
                          (when pinned
                            (:span :class "pin-indicator" "📌"))
                          (:div :class "post-action-row"
                            (:button :class "post-action-btn" :title "React" :type "button" "☺")
                            (:button :class "post-action-btn"
                                     :title "Reply"
                                     :type "button"
                                     :data-on-click (format nil "/action/strata-shell/toggle-thread?id=~A" post-id)
                                     "↩")
                            (:button :class (if (member post-id bookmarked-ids :test #'eql)
                                                 "post-action-btn active"
                                                 "post-action-btn")
                                     :title "Bookmark"
                                     :type "button"
                                     :data-on-click (format nil "/action/strata-shell/bookmark?post_id=~A" post-id)
                                     "★")
                            (when (string= status "open")
                              (cond
                                ((string= kind "question")
                                 (:button :class "post-action-btn post-status-action"
                                          :title "Mark as answered"
                                          :type "button"
                                          :data-on-click (format nil "/action/strata-shell/set-status?post_id=~A&status=resolved" post-id)
                                          "✓ Answer"))
                                ((string= kind "task")
                                 (:button :class "post-action-btn post-status-action"
                                          :title "Mark as done"
                                          :type "button"
                                          :data-on-click (format nil "/action/strata-shell/set-status?post_id=~A&status=done" post-id)
                                          "✓ Done"))
                                ((string= kind "decision")
                                 (:button :class "post-action-btn post-status-action"
                                          :title "Mark as decided"
                                          :type "button"
                                          :data-on-click (format nil "/action/strata-shell/set-status?post_id=~A&status=decided" post-id)
                                          "✓ Decided"))
                                ((string= kind "announcement")
                                 (:button :class "post-action-btn post-status-action"
                                          :title "Mark as resolved"
                                          :type "button"
                                          :data-on-click (format nil "/action/strata-shell/set-status?post_id=~A&status=resolved" post-id)
                                          "✓ Resolve"))))
                            (when (eql author user-id)
                              (:button :class "post-action-btn"
                                       :title "Edit"
                                       :type "button"
                                       :data-on-click (format nil "/action/strata-shell/edit-post?post_id=~A" post-id)
                                       "✎")
                              (:button :class "post-action-btn post-action-delete"
                                       :title "Delete"
                                       :type "button"
                                       :data-on-click (format nil "/action/strata-shell/delete-post?post_id=~A" post-id)
                                       "✕"))))
                        (if (eql post-id (shell-editing-post-id self))
                            (:form :class "post-edit-form"
                                   :data-on-submit (format nil "/action/strata-shell/save-edit?post_id=~A" post-id)
                              (:textarea :class "post-edit-textarea"
                                         :name "body"
                                         :rows 4
                                         body)
                              (:div :class "post-edit-actions"
                                (:button :class "post-edit-save"  :type "submit" "Save")
                                (:button :class "post-edit-cancel" :type "button"
                                         :data-on-click (format nil "/action/strata-shell/cancel-edit?post_id=~A" post-id)
                                         "Cancel")))
                            (:p :class "post-body"
                              body
                              (when (post-field post "edited_at")
                                (:span :class "post-edited-badge" " (edited)"))))
                        (let ((edits (when (post-field post "edited_at")
                                       (load-post-edits post-id))))
                          (when edits
                            (:details :class "post-edit-history"
                              (:summary :class "post-edit-history-summary"
                                (format nil "~A earlier version~:P" (length edits)))
                              (dolist (ed edits)
                                (:div :class "post-edit-history-entry"
                                  (:span :class "post-edit-history-time"
                                    (format-post-time
                                     (strata.models.post-edit:post-edit-field ed "edited_at")))
                                  (:p :class "post-edit-history-body"
                                    (strata.models.post-edit:post-edit-field ed "body")))))))
                        (render-attachment-list attachments)
                        (:div :class "post-footer"
                          (dolist (r reacts)
                            (:button :class "reaction-pill" :type "button"
                              (:span (car r))
                              (:span (princ-to-string (cdr r)))))
                          (when (plusp replies)
                            (:button :class (if (eql post-id (shell-expanded-thread-id self))
                                                "reply-count-btn active"
                                                "reply-count-btn")
                                     :type "button"
                                     :data-on-click (format nil "/action/strata-shell/toggle-thread?id=~A" post-id)
                              (:span "↩")
                              (:span (format nil "~A repl~:@P" replies)))))

                      (when (eql post-id (shell-expanded-thread-id self))
                        (let ((post-replies (handler-case
                                                (strata.models.reply:list-replies-for-post post-id)
                                              (error () nil))))
                          (:div :class "inline-thread"
                                :id (format nil "inline-thread-~A" post-id)
                            (if (and post-replies (plusp (length post-replies)))
                                (dolist (r post-replies)
                                  (let* ((rbody   (strata.models.reply:reply-field r "body"))
                                         (rts     (strata.models.reply:reply-field r "created_at"))
                                         (rauthor (post-author-name (strata.models.reply:reply-field r "author_id"))))
                                    (:div :class "inline-reply"
                                      (:div :class "post-avatar inline-reply-avatar" (initial rauthor))
                                      (:div :class "inline-reply-content"
                                        (:div :class "inline-reply-meta"
                                          (:span :class "post-author" rauthor)
                                          (:span :class "post-time" (format-post-time rts)))
                                        (:p :class "post-body" rbody)))))
                                (:p :class "feed-empty" "No replies yet."))
                            (:form :class "inline-reply-composer"
                                   :data-on-submit "/action/strata-shell/reply"
                              (:input :type "hidden" :name "post_id" :value (princ-to-string post-id))
                              (:textarea :class "inline-reply-textarea"
                                         :name "body"
                                         :placeholder "Reply..."
                                         :rows 2
                                         :onkeydown "if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();this.closest('form').requestSubmit();}")
                              (:div :class "inline-reply-actions"
                                (:button :type "submit" :class "composer-send-btn"
                                         :data-disable-during-request t
                                  "Reply"))))))))))

            (:p :class "feed-empty" "No messages yet."))

          ) ; close post-feed

          ;; Resolved drawer
          (let ((resolved (load-resolved-posts (shell-active-channel self))))
            (let ((closed (remove-if-not
                           (lambda (p)
                             (let ((s (or (post-field p "status") "open")))
                               (member s '("resolved" "decided" "done") :test #'string=)))
                           (or resolved nil))))
              (when closed
                (:details :class "resolved-drawer"
                  (:summary :class "resolved-drawer-summary"
                    (format nil "~A resolved" (length closed)))
                  (dolist (post closed)
                    (let* ((body   (or (post-field post "body") ""))
                           (kind   (or (post-field post "kind") "message"))
                           (status (or (post-field post "status") "resolved")))
                      (:article :class "post-card resolved"
                        (:div :class "post-content"
                          (:div :class "post-meta"
                            (:span :class (format nil "post-kind-badge post-kind-~A" kind) kind)
                            (:span :class (format nil "post-status-badge post-status-~A" status) status))
                          (:p :class "post-body" body)))))))))

          ;; Channel settings panel
          (let ((mgmt-id (shell-managing-channel-id self)))
            (when mgmt-id
              (let* ((ch   (strata.models.channel:find-channel-by-id mgmt-id))
                     (members (when ch (strata.models.channel-member:list-members mgmt-id)))
                     (ch-name  (when ch (strata.models.channel:channel-field ch "name")))
                     (ch-desc  (when ch (strata.models.channel:channel-field ch "description")))
                     (ch-kind  (when ch (strata.models.channel:channel-field ch "kind"))))
                (when ch
                  (:div :class "thread-pane-wrap"
                    (:div :class "thread-pane"
                      (:div :class "thread-pane-header"
                        (:span :class "thread-pane-title" "Channel Settings")
                        (:button :class "thread-close-btn" :type "button"
                                 :data-on-click "/action/strata-shell/close-manage-channel"
                                 "✕"))
                      (:form :class "channel-settings-form"
                             :data-on-submit (format nil "/action/strata-shell/update-channel?id=~A" mgmt-id)
                        (:label :class "channel-settings-label" "Name")
                        (:input :class "channel-settings-input" :name "name" :value ch-name)
                        (:label :class "channel-settings-label" "Description")
                        (:input :class "channel-settings-input" :name "description" :value (or ch-desc ""))
                        (:button :type "submit" :class "post-edit-save" "Save changes"))
                      (when (string= ch-kind "private")
                        (:div :class "channel-settings-members"
                          (:h4 :class "channel-settings-section" "Members")
                          (if members
                              (dolist (m members)
                                (:div :class "channel-member-row"
                                  (:span :class "channel-member-name"
                                    (princ-to-string (strata.models.channel-member:member-field m "user_id")))
                                  (:button :class "channel-member-remove" :type "button"
                                           :data-on-click (format nil "/action/strata-shell/remove-member?channel_id=~A&user_id=~A"
                                                                   mgmt-id
                                                                   (strata.models.channel-member:member-field m "user_id"))
                                           "Remove")))
                              (:p :class "feed-empty" "No members yet."))
                          (:form :class "channel-add-member-form"
                                 :data-on-submit (format nil "/action/strata-shell/add-member?channel_id=~A" mgmt-id)
                            (:input :class "channel-settings-input" :name "username"
                                    :placeholder "Username to add")
                            (:button :type "submit" :class "post-edit-save" "Add"))))
                      (:div :class "channel-settings-actions"
                        (:button :class "post-action-btn" :type "button"
                                 :data-on-click (format nil "/action/strata-shell/create-sub-channel?id=~A" mgmt-id)
                                 "⊕ Create sub-channel"))
                      (:div :class "channel-settings-danger"
                        (:button :class "post-action-btn post-action-delete" :type "button"
                                 :data-on-click (format nil "/action/strata-shell/archive-channel?id=~A" mgmt-id)
                                 "Archive channel"))))))))

          ;; Thread pane (shown when a post is open)
          (when thread-id
            (:div :class "thread-pane-wrap"
              (:raw (strata.components.thread:render-thread-pane
                     thread-id
                     (fluxion.components:component-id self)
                     session))))

          ;; Composer
          (:div :class "composer-wrap"
            (:form :class "composer-box"
                   :data-on-submit "/action/strata-shell/post"
              (:div :class "composer-kind-bar"
                (dolist (k '("message" "question" "decision" "task" "announcement"))
                  (:button :type "button"
                           :class (if (string= k "message") "kind-btn active" "kind-btn")
                           :onclick (format nil "strataSetKind(this,'~A')" k)
                           (string-capitalize k))))
              (:textarea :class "composer-textarea"
                         :name "body"
                         :placeholder "Write something… (Shift+Enter for new line)"
                         :rows 3
                         :onkeydown "if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();this.closest('form').requestSubmit();}")
              (:input :type "hidden" :name "kind" :id "composer-kind" :value "message")
              (:input :type "hidden" :name "channel" :value (shell-active-channel self))
              (:input :type "hidden" :name "attachment_uuid" :id "composer-attachment-uuid" :value "")
              (:div :id "composer-attachment-preview" :class "composer-attachment-preview")
              (:input :type "file" :id "composer-file-input" :class "composer-file-input-hidden"
                      :onchange "strataHandleFileSelect(this)")
              (:div :class "composer-footer"
                (:button :type "button" :class "composer-tool-btn composer-attach-btn" :title "Attach"
                         :onclick "document.getElementById('composer-file-input').click()"
                         "Attach")
                (:button :type "button" :class "composer-tool-btn" :title "Emoji" "☺")
                (:span :class "composer-hint"
                  (:kbd "Enter") " to send, " (:kbd "Shift+Enter") " for newline")
                (:button :type "submit" :class "composer-send-btn"
                         :data-disable-during-request t
                  "Send")))

      ;; Mobile overlay (dismisses sidebar when tapped outside)
      (:div :id "mobile-overlay" :hidden t
            :onclick "strataMobileSidebarClose()")))))))

(setf (documentation (find-class 'shell-component) t)
      "Top-level Fluxion component that renders the full Strata application shell.
Manages the active channel selection and the open thread pane state.
The rendered HTML is a three-column grid: workspace rail, channel sidebar,
and main panel (channel header, post feed, composer).
Actions handled: switch-channel, post, open-thread.")

;;; -------------------------------------------------------
;;; Actions
;;; -------------------------------------------------------

(fluxion.components:defaction shell-component :switch-channel (self params)
  "Switch the active channel to the slug in PARAMS and re-render.
The client sends ?slug=<channel-slug> appended to the action URL;
Fluxion's bind-actions merges query-string values into the params alist."
  (let ((slug (cdr (assoc "slug" params :test #'string=))))
    (when (and slug (plusp (length slug)))
      (setf (shell-active-channel self) slug))
    (fluxion.components:patch-component self)))

(fluxion.components:defaction shell-component :post (self params)
  "Create a new post from the composer form data and re-render the feed.
Expects params: body (string), kind (string), channel (slug string).
The author-id is taken from the session user, defaulting to 0 (guest).
Touches the channel so the sidebar ordering stays fresh."
  (let* ((body    (cdr (assoc "body"    params :test #'string=)))
         (kind    (or (cdr (assoc "kind"    params :test #'string=)) "message"))
         (slug    (or (cdr (assoc "channel" params :test #'string=))
                      (shell-active-channel self)))
         (att-uuid (let ((v (cdr (assoc "attachment_uuid" params :test #'string=))))
                     (when (and v (plusp (length v))) v)))
         (session (fluxion.components:component-session self))
         (user-id (if session (session-author-id session) 0)))
    (when (and body (plusp (length (string-trim '(#\Space #\Tab #\Newline) body))))
      (handler-case
          (let ((ch (strata.models.channel:find-channel-by-slug (load-workspace-id) slug)))
            (when ch
              (let* ((channel-id (fxdm:model-id ch))
                     (post       (strata.models.post:create-post
                                  :channel-id channel-id
                                  :author-id  user-id
                                  :kind       kind
                                  :body       (string-trim '(#\Space #\Tab #\Newline) body)))
                     (post-id    (fxdm:model-id post)))
                (when att-uuid
                  (let ((att (strata.models.attachment:find-attachment-by-uuid att-uuid)))
                    (when att
                      (setf (fxdm:model-field att "post_id") post-id)
                      (fxdm:save att))))
                (strata.models.channel:touch-channel channel-id))))
        (error (e)
          (format t "~&[strata] post action error: ~A~%" e))))
    (append (fluxion.components:patch-component self)
            (list (events:make-script-event
                   "var ta=document.querySelector('.composer-textarea');if(ta){ta.value='';}")))))

(fluxion.components:defaction shell-component :open-thread (self params)
  "Open the thread pane for the post identified by the id param."
  (let ((id-str (cdr (assoc "id" params :test #'string=))))
    (when id-str
      (setf (shell-thread-post-id self)
            (ignore-errors (parse-integer id-str))))
    (fluxion.components:patch-component self)))

(fluxion.components:defaction shell-component :close-thread (self params)
  "Close the thread pane."
  (when params nil)
  (setf (shell-thread-post-id self) nil)
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :set-status (self params)
  "Set the status of a post. Expects post_id and status params."
  (let* ((id-str  (cdr (assoc "post_id" params :test #'string=)))
         (status  (cdr (assoc "status"  params :test #'string=)))
         (post-id (when id-str (ignore-errors (parse-integer id-str)))))
    (when (and post-id status)
      (handler-case
          (strata.models.post:set-post-status post-id status)
        (error (e)
          (format t "~&[strata] set-status error: ~A~%" e))))
  (fluxion.components:patch-component self)))

(fluxion.components:defaction shell-component :toggle-thread (self params)
  "Toggle inline replies open/closed for the post identified by id."
  (let* ((id-str (cdr (assoc "id" params :test #'string=)))
         (post-id (when id-str (ignore-errors (parse-integer id-str)))))
    (if (eql post-id (shell-expanded-thread-id self))
        (setf (shell-expanded-thread-id self) nil)
        (setf (shell-expanded-thread-id self) post-id))
    (fluxion.components:patch-component self)))

(fluxion.components:defaction shell-component :reply (self params)
  "Create a reply to the open thread post."
  (let* ((post-id-str (cdr (assoc "post_id" params :test #'string=)))
         (body        (cdr (assoc "body"    params :test #'string=)))
         (session     (fluxion.components:component-session self))
         (author-id   (if session (session-author-id session) 0))
         (post-id     (when post-id-str (ignore-errors (parse-integer post-id-str)))))
    (when (and post-id body (plusp (length (string-trim '(#\Space #\Tab #\Newline) body))))
      (handler-case
          (progn
            (strata.models.reply:create-reply
             :post-id   post-id
             :author-id author-id
             :body      (string-trim '(#\Space #\Tab #\Newline) body))
            (setf (shell-expanded-thread-id self) post-id))
        (error (e)
          (format t "~&[strata] reply action error: ~A~%" e))))
    (append (fluxion.components:patch-component self)
            (list (events:make-script-event
                   "var ta=document.querySelector('.inline-reply-textarea');if(ta){ta.value='';}")))))

(fluxion.components:defaction shell-component :bookmark (self params)
  "Toggle a bookmark on the post identified by the post_id param.
Adds the bookmark if absent, removes it if already present."
  (let* ((post-id-str (cdr (assoc "post_id" params :test #'string=)))
         (session     (fluxion.components:component-session self))
         (user-id     (if session (session-author-id session) 0))
         (post-id     (when post-id-str (ignore-errors (parse-integer post-id-str)))))
    (when (and post-id (plusp user-id))
      (handler-case
          (if (strata.models.bookmark:bookmark-p user-id post-id)
              (strata.models.bookmark:remove-bookmark :user-id user-id :post-id post-id)
              (strata.models.bookmark:add-bookmark    :user-id user-id :post-id post-id))
        (error (e)
          (format t "~&[strata] bookmark action error: ~A~%" e)))))
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :edit-post (self params)
  "Enter inline edit mode for the post identified by post_id."
  (let ((id-str (cdr (assoc "post_id" params :test #'string=))))
    (when id-str
      (setf (shell-editing-post-id self)
            (ignore-errors (parse-integer id-str)))))
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :cancel-edit (self params)
  "Exit inline edit mode without saving."
  (when params nil)
  (setf (shell-editing-post-id self) nil)
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :save-edit (self params)
  "Save an edited post body and exit edit mode."
  (let* ((id-str  (cdr (assoc "post_id" params :test #'string=)))
         (body    (cdr (assoc "body"    params :test #'string=)))
         (session (fluxion.components:component-session self))
         (post-id (when id-str (ignore-errors (parse-integer id-str)))))
    (when (and post-id body
               (plusp (length (string-trim '(#\Space #\Tab #\Newline) body))))
      (handler-case
          (strata.models.post:update-post-body
           post-id
           (string-trim '(#\Space #\Tab #\Newline) body)
           :editor-id (if session (session-author-id session) 0))
        (error (e)
          (format t "~&[strata] save-edit error: ~A~%" e))))
    (setf (shell-editing-post-id self) nil))
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :delete-post (self params)
  "Permanently delete the post identified by post_id (author only)."
  (let* ((id-str  (cdr (assoc "post_id" params :test #'string=)))
         (session (fluxion.components:component-session self))
         (user-id (if session (session-author-id session) 0))
         (post-id (when id-str (ignore-errors (parse-integer id-str)))))
    (when post-id
      (let ((post (strata.models.post:find-post-by-id post-id)))
        (when (and post (eql (strata.models.post:post-field post "author_id") user-id))
          (handler-case
              (strata.models.post:delete-post post-id)
            (error (e)
              (format t "~&[strata] delete-post error: ~A~%" e)))))))
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :show-new-channel (self params)
  "Show the inline new-channel creation form in the sidebar."
  (when params nil)
  (setf (shell-creating-channel-p self) t)
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :hide-new-channel (self params)
  "Hide the new-channel creation form without creating anything."
  (when params nil)
  (setf (shell-creating-channel-p self) nil)
  (setf (shell-creating-channel-under-id self) nil)
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :create-sub-channel (self params)
  "Open the new-channel modal pre-filled to create a channel under the current channel."
  (let* ((id-str (cdr (assoc "id" params :test #'string=)))
         (parent-id (when id-str (ignore-errors (parse-integer id-str)))))
    (when parent-id
      (setf (shell-creating-channel-under-id self) parent-id))
    (setf (shell-creating-channel-p self) t)
    (fluxion.components:patch-component self)))

(fluxion.components:defaction shell-component :create-channel (self params)
  "Create a new channel from the modal and switch to it."
  (let* ((session (fluxion.components:component-session self))
         (name-raw (or (cdr (assoc "name" params :test #'string=)) ""))
         (slug-raw (or (cdr (assoc "slug" params :test #'string=)) ""))
         (name (string-trim '(#\Space) name-raw))
         (slug (let ((s (string-trim '(#\Space) slug-raw)))
                 (if (plusp (length s))
                     s
                     (string-downcase
                      (with-output-to-string (out)
                        (loop for c across name
                              if (alphanumericp c) do (write-char (char-downcase c) out)
                              else if (char= c #\Space) do (write-char #\- out)))))))
         (kind (or (cdr (assoc "kind" params :test #'string=)) "open"))
         (parent-id-str (cdr (assoc "parent_channel_id" params :test #'string=)))
         (parent-id (when parent-id-str (ignore-errors (parse-integer parent-id-str))))
         (ws   (handler-case
                   (strata.models.workspace:find-workspace-by-slug "default")
                 (error () nil)))
         (ws-id (when ws (fxdm:model-id ws)))
         (user-id (when session (session-author-id session))))
    (when (and (plusp (length name)) (plusp (length slug)) ws-id)
      (handler-case
          (let* ((ch    (strata.models.channel:create-channel
                         :workspace-id ws-id
                         :slug  slug
                         :name  name
                         :kind  kind
                         :parent-channel-id parent-id))
                 (ch-id (fxdm:model-id ch)))
            (when user-id
              (handler-case
                  (strata.models.channel-member:add-member ch-id user-id)
                (error () nil)))
            (setf (shell-active-channel self)
                  (strata.models.channel:channel-field ch "slug")))
        (error (e)
          (format t "~&[strata] create-channel error: ~A~%" e)))))
  (setf (shell-creating-channel-p self) nil)
  (setf (shell-creating-channel-under-id self) nil)
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :manage-channel (self params)
  "Open the channel settings panel for the channel identified by id."
  (let ((id-str (cdr (assoc "id" params :test #'string=))))
    (when id-str
      (setf (shell-managing-channel-id self)
            (ignore-errors (parse-integer id-str)))))
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :close-manage-channel (self params)
  "Close the channel settings panel."
  (when params nil)
  (setf (shell-managing-channel-id self) nil)
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :update-channel (self params)
  "Save channel name and description changes from the settings panel."
  (let* ((id-str (cdr (assoc "id" params :test #'string=)))
         (name   (cdr (assoc "name"        params :test #'string=)))
         (desc   (cdr (assoc "description" params :test #'string=)))
         (ch-id  (when id-str (ignore-errors (parse-integer id-str)))))
    (when ch-id
      (handler-case
          (strata.models.channel:update-channel
           ch-id
           :name        (when (and name (plusp (length (string-trim '(#\Space) name))))
                          (string-trim '(#\Space) name))
           :description desc)
        (error (e)
          (format t "~&[strata] update-channel error: ~A~%" e)))))
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :add-member (self params)
  "Add a user by username to the private channel identified by channel_id."
  (let* ((ch-id-str (cdr (assoc "channel_id" params :test #'string=)))
         (username  (cdr (assoc "username"   params :test #'string=)))
         (ch-id     (when ch-id-str (ignore-errors (parse-integer ch-id-str)))))
    (when (and ch-id username (plusp (length (string-trim '(#\Space) username))))
      (handler-case
          (let* ((uname (string-trim '(#\Space) username))
                 (u     (user:get uname))
                 (uid   (when u (user:user-id u))))
            (when (and uid (not (strata.models.channel-member:member-p ch-id uid)))
              (strata.models.channel-member:add-member ch-id uid)))
        (error (e)
          (format t "~&[strata] add-member error: ~A~%" e)))))
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :remove-member (self params)
  "Remove a user from the private channel identified by channel_id and user_id."
  (let* ((ch-id-str  (cdr (assoc "channel_id" params :test #'string=)))
         (uid-str    (cdr (assoc "user_id"    params :test #'string=)))
         (ch-id      (when ch-id-str (ignore-errors (parse-integer ch-id-str))))
         (uid        (when uid-str   (ignore-errors (parse-integer uid-str)))))
    (when (and ch-id uid)
      (handler-case
          (strata.models.channel-member:remove-member ch-id uid)
        (error (e)
          (format t "~&[strata] remove-member error: ~A~%" e)))))
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :archive-channel (self params)
  "Archive the channel identified by id and switch to general."
  (let* ((id-str (cdr (assoc "id" params :test #'string=)))
         (ch-id  (when id-str (ignore-errors (parse-integer id-str)))))
    (when ch-id
      (handler-case
          (strata.models.channel:archive-channel ch-id)
        (error (e)
          (format t "~&[strata] archive-channel error: ~A~%" e)))))
  (setf (shell-managing-channel-id self) nil
        (shell-active-channel self) "general")
  (fluxion.components:patch-component self))

(fluxion.components:defaction shell-component :logout (self params)
  "Log the current user out of the session and redirect to /login."
  (when params nil)
  (fluxion.auth:logout)
  (list (events:make-redirect-event "/login")))

;;; -------------------------------------------------------
;;; Page renderer
;;; -------------------------------------------------------

(defun head-html ()
  "Return extra <head> content for the Strata page."
  (format nil
    "<meta name=\"theme-color\" content=\"#5865f2\">~
     <meta name=\"apple-mobile-web-app-capable\" content=\"yes\">~
     <meta name=\"apple-mobile-web-app-status-bar-style\" content=\"black-translucent\">~
     <meta name=\"apple-mobile-web-app-title\" content=\"Strata\">~
     <link rel=\"manifest\" href=\"/static/manifest.json\">~
     <link rel=\"apple-touch-icon\" href=\"/static/icons/icon-192.png\">~
     <script src=\"/static/js/theme.js?v=2\"></script>~
     <script src=\"/static/js/attachments.js?v=2\"></script>~
     <script src=\"/static/js/pwa.js?v=2\"></script>~
     <link rel=\"stylesheet\" href=\"/static/css/strata.css?v=2\">~
     <script>~
       function strataSetKind(btn,k){~
         btn.closest('.composer-kind-bar').querySelectorAll('.kind-btn').forEach(function(b){b.classList.remove('active')});~
         btn.classList.add('active');~
         document.getElementById('composer-kind').value=k;~
       }~
     </script>"))

(defun make-shell ()
  "Create a fresh shell-component instance for use as a per-session factory.
Called by the factory registered in strata.app:make-app via
fluxion.server:register-component-factory."
  (make-instance 'shell-component))

(defun render-page-for-session (session)
  "Render the full Strata HTML page for SESSION.
Retrieve the shell component from the session registry (put there by the
factory registered at startup) and render the full page via Fluxion."
  (let* ((shell (fluxion.server:session-component session "strata-shell"))
         (csrf  (fluxion.server:session-csrf-token session)))
    (unless shell
      (error "[strata] shell component not found in session -- factory not registered?"))
    (fluxion.render:render-page
     :title "Strata"
     :head-html (head-html)
     :csrf-token csrf
     :body-html (fluxion.components:render shell)
     :script-path "/static/fluxion.js")))
