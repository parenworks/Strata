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
  "Return top-level channel data-models visible to USER-ID, or NIL."
  (handler-case
      (let ((member-ids (load-member-channel-ids user-id)))
        (strata.models.channel:list-channels-for-user 1 user-id member-ids))
    (error () nil)))

(defun load-subchannels (channel-id)
  "Return sub-channel data-models for CHANNEL-ID, or NIL."
  (handler-case
      (strata.models.channel:list-subchannels channel-id)
    (error () nil)))

(defun load-posts (channel-slug)
  "Return open post data-models for CHANNEL-SLUG, or NIL if DB is unavailable."
  (handler-case
      (let ((ch (strata.models.channel:find-channel-by-slug 1 channel-slug)))
        (when ch
          (strata.models.post:list-posts-for-channel
           (fxdm:model-id ch) :limit 50)))
    (error () nil)))

(defun load-resolved-posts (channel-slug)
  "Return resolved/decided/done post data-models for CHANNEL-SLUG."
  (handler-case
      (let ((ch (strata.models.channel:find-channel-by-slug 1 channel-slug)))
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
  :slots ((active-channel :initform "general" :accessor shell-active-channel)
          (thread-post-id :initform nil       :accessor shell-thread-post-id))

  :render
  (let* ((session        (fluxion.components:component-session self))
         (username       (if session (session-display-name session) "Guest"))
         (user-id        (if session (session-author-id session) 0))
         (workspace-name (load-workspace-name))
         (db-channels    (load-channels user-id))
         (db-posts       (load-posts (shell-active-channel self)))
         (channels       db-channels)
         (posts          db-posts)
         (thread-id      (shell-thread-post-id self))
         (bookmarked-ids (load-bookmarked-ids user-id)))
    (spinneret:with-html-string
      (:div :id (fluxion.components:component-id self)
            :class "strata-shell"

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
                  username)))

          (:div :class "channel-list-scroll"
            (:div :class "channel-section-label"
              (:span "Channels")
              (:button :class "channel-section-add"
                       :title "New channel"
                       :type "button"
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
                          :data-on-click (format nil "/action/strata-shell/switch-channel?slug=~A" slug)
                      (:span :class "channel-sigil" (if (string= kind "private") "🔒" "#"))
                      (:span :class "channel-name" name))
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
        (:main :class "main-panel"

          ;; Channel header
          (:header :class "channel-header"
            (:span :class "channel-header-hash" "#")
            (:span :class "channel-header-name" (shell-active-channel self))
            (:div :class "header-actions"
              (:button :class "header-btn" :title "Search" :type "button" "🔍")
              (:button :class "header-btn" :title "Members" :type "button" "👥")
              (:button :class "header-btn" :title "Pinned" :type "button" "📌")))

          ;; Post feed
          (:section :id "post-feed" :class (if thread-id "post-feed thread-open" "post-feed")
            (:div :class "feed-date-divider"
              (:span :class "feed-date-label" "Today"))
            (if posts
                (dolist (post posts)
                  (let* ((post-id  (fxdm:model-id post))
                         (author   (or (post-field post "author_id") "?"))
                         (kind     (or (post-field post "kind") "message"))
                         (status   (or (post-field post "status") "open"))
                         (body     (or (post-field post "body") ""))
                         (pinned   (eql 1 (post-field post "pinned")))
                         (reacts   (load-reactions post-id))
                         (replies  (load-reply-count post-id)))
                    (:article :class (if pinned "post-card pinned" "post-card")
                      (:div :class "post-avatar" (initial (princ-to-string author)))
                      (:div :class "post-content"
                        (:div :class "post-meta"
                          (:span :class "post-author" (princ-to-string author))
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
                                     :title "Reply in thread"
                                     :type "button"
                                     :data-on-click (format nil "/action/strata-shell/open-thread?id=~A" post-id)
                                     "↩")
                            (:button :class (if (member post-id bookmarked-ids :test #'eql)
                                                 "post-action-btn active"
                                                 "post-action-btn")
                                     :title "Bookmark"
                                     :type "button"
                                     :data-on-click (format nil "/action/strata-shell/bookmark?post_id=~A" post-id)
                                     "🔖")))
                        (:p :class "post-body" body)
                        (:div :class "post-footer"
                          (dolist (r reacts)
                            (:button :class "reaction-pill" :type "button"
                              (:span (car r))
                              (:span (princ-to-string (cdr r)))))
                          (when (plusp replies)
                            (:button :class "reply-count-btn"
                                     :type "button"
                                     :data-on-click (format nil "/action/strata-shell/open-thread?id=~A" post-id)
                              (:span "↩")
                              (:span (format nil "~A repl~:@P" replies)))))))))))

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
                          (:p :class "post-body" body))))))))))

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
              (:div :class "composer-footer"
                (:button :type "button" :class "composer-tool-btn" :title "Attach" "📎")
                (:button :type "button" :class "composer-tool-btn" :title "Emoji" "☺")
                (:span :class "composer-hint"
                  (:kbd "Enter") " to send, " (:kbd "Shift+Enter") " for newline")
                (:button :type "submit" :class "composer-send-btn"
                         :data-disable-during-request t
                  "Send"))))))))

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
         (session (fluxion.components:component-session self))
         (user-id (if session (session-author-id session) 0)))
    (when (and body (plusp (length (string-trim '(#\Space #\Tab #\Newline) body))))
      (handler-case
          (let ((ch (strata.models.channel:find-channel-by-slug 1 slug)))
            (when ch
              (let ((channel-id (fxdm:model-id ch)))
                (strata.models.post:create-post
                 :channel-id channel-id
                 :author-id  user-id
                 :kind       kind
                 :body       (string-trim '(#\Space #\Tab #\Newline) body))
                (strata.models.channel:touch-channel channel-id))))
        (error (e)
          (format t "~&[strata] post action error: ~A~%" e))))
    (fluxion.components:patch-component self)))

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

(fluxion.components:defaction shell-component :reply (self params)
  "Create a reply to the open thread post."
  (let* ((post-id-str (cdr (assoc "post_id"   params :test #'string=)))
         (body        (cdr (assoc "body"       params :test #'string=)))
         (session     (fluxion.components:component-session self))
         (author-id   (if session (session-author-id session) 0))
         (post-id     (when post-id-str (ignore-errors (parse-integer post-id-str)))))
    (when (and post-id body (plusp (length (string-trim '(#\Space #\Tab #\Newline) body))))
      (handler-case
          (strata.models.reply:create-reply
           :post-id   post-id
           :author-id author-id
           :body      (string-trim '(#\Space #\Tab #\Newline) body))
        (error (e)
          (format t "~&[strata] reply action error: ~A~%" e))))
    (fluxion.components:patch-component self)))

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

(fluxion.components:defaction shell-component :logout (self params)
  "Log the current user out of the session and redirect to /login."
  (let ((session (fluxion.components:component-session self)))
    (when session
      (fluxion.auth:logout session)))
  (list (events:make-redirect-event "/login")))

;;; -------------------------------------------------------
;;; Page renderer
;;; -------------------------------------------------------

(defun head-html ()
  "Return extra <head> content for the Strata page."
  (format nil
    "<script src=\"/static/js/theme.js\"></script>~
     <link rel=\"stylesheet\" href=\"/static/css/strata.css\">~
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
