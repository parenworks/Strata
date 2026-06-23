;;;; -*- encoding:utf-8 -*-
;;;; Strata - Admin panel component
;;;;
;;;; Tabbed admin interface at /admin. Requires the "admin" permission.
;;;; Tabs: Users, Channels, Workspace, Storage, Audit Log.

(in-package #:strata.components.admin)

;;; -------------------------------------------------------
;;; Component definition
;;; -------------------------------------------------------

(fluxion.components:defcomponent admin-component
  :id "strata-admin"
  :slots ((active-tab :initform "users" :accessor admin-active-tab)
          (flash-msg  :initform nil     :accessor admin-flash-msg))
  :render
  (let* ((session (fluxion.components:component-session self))
         (tab     (admin-active-tab self))
         (msg     (admin-flash-msg self)))
    (spinneret:with-html-string
      (:div :id (fluxion.components:component-id self)
            :class "admin-shell"
        (:header :class "admin-header"
          (:h1 :class "admin-title" "Strata Admin")
          (:a :href "/" :class "admin-back-link" "Back to workspace"))
        (when msg
          (:div :class "admin-flash" msg))
        (:nav :class "admin-tabs"
          (dolist (pair '(("users"     . "Users")
                          ("channels"  . "Channels")
                          ("workspace" . "Workspace")
                          ("storage"   . "Storage")
                          ("audit"     . "Audit Log")))
            (:button :type "button"
                     :class (if (string= tab (car pair))
                                "admin-tab-btn active"
                                "admin-tab-btn")
                     :data-on-click (format nil "/action/strata-admin/switch-tab?tab=~A" (car pair))
                     (cdr pair))))
        (:div :class "admin-tab-panel"
          (cond
            ((string= tab "users")     (render-users-tab self session))
            ((string= tab "channels")  (render-channels-tab))
            ((string= tab "workspace") (render-workspace-tab))
            ((string= tab "storage")   (render-storage-tab))
            ((string= tab "audit")     (render-audit-tab))
            (t                         (render-users-tab self session))))))))

;;; -------------------------------------------------------
;;; Helpers
;;; -------------------------------------------------------

(defun format-ts (ut)
  "Format a universal-time integer as a short date-time string."
  (when (and ut (plusp ut))
    (multiple-value-bind (sec min hour day mon year)
        (decode-universal-time ut)
      (declare (ignore sec))
      (format nil "~2,'0d ~a ~d ~2,'0d:~2,'0d"
              day
              (nth (1- mon) '("Jan" "Feb" "Mar" "Apr" "May" "Jun"
                              "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))
              year hour min))))

(defun format-bytes (n)
  "Format N bytes as a human-readable size string."
  (cond
    ((null n)           "0 B")
    ((< n 1024)         (format nil "~D B" n))
    ((< n (* 1024 1024))(format nil "~,1F KB" (/ n 1024.0)))
    (t                  (format nil "~,1F MB" (/ n (* 1024.0 1024))))))

(defun session-username (session)
  "Return the username for the current session user, or NIL."
  (let ((u (fx:session-user session)))
    (when u (fluxion.user:user-username u))))

(defun session-actor-id (session)
  "Return the _id of the session user, or 0."
  (let ((u (fx:session-user session)))
    (if u (or (fluxion.user:user-id u) 0) 0)))

(defun admin-p (session)
  "Return T if the session user has the admin permission."
  (let ((uname (session-username session)))
    (when uname
      (strata.auth:is-admin-p uname))))

(defun all-user-rows ()
  "Return all user alists from fluxion_users."
  (handler-case (fluxion.user:list-users) (error () nil)))

(defun user-post-count (uid)
  "Return number of posts authored by UID."
  (handler-case
      (length (fluxion.db:select "posts"
                                 (fluxion.db:compile-query `(:= author_id ,uid))))
    (error () 0)))

(defun total-attachment-bytes ()
  "Return total size_bytes across all attachments."
  (handler-case
      (let ((rows (fluxion.db:select "attachments"
                                     (fluxion.db:compile-query :all))))
        (reduce #'+ rows
                :key (lambda (r) (or (cdr (assoc "size_bytes" r :test #'string=)) 0))
                :initial-value 0))
    (error () 0)))

(defun all-attachment-rows ()
  "Return all attachment data-models, newest first."
  (handler-case
      (fxdm:get-all "attachments"
                    (fluxion.db:compile-query :all)
                    :sort '(("created_at" . :desc)))
    (error () nil)))

;;; -------------------------------------------------------
;;; Tab renderers
;;; -------------------------------------------------------

(defun render-users-tab (self session)
  "Render the Users management tab."
  (declare (ignore self))
  (let* ((users   (all-user-rows))
         (me-name (session-username session)))
    (:div :class "admin-tab-content"
      (:div :class "admin-section-header"
        (:h2 "Users")
        (:form :class "admin-invite-form"
               :data-on-submit "/action/strata-admin/invite-user"
          (:input :type "text" :name "username"
                  :placeholder "Username" :class "admin-input" :required t)
          (:input :type "text" :name "display_name"
                  :placeholder "Display name" :class "admin-input")
          (:input :type "password" :name "password"
                  :placeholder "Initial password" :class "admin-input" :required t)
          (:button :type "submit" :class "admin-btn admin-btn-primary" "Invite")))
      (:table :class "admin-table"
        (:thead
          (:tr
            (:th "Username") (:th "Display name")
            (:th "Posts") (:th "Admin") (:th "Status") (:th "Actions")))
        (:tbody
          (dolist (u users)
            (let* ((uid      (fluxion.user:user-id u))
                   (uname    (fluxion.user:user-username u))
                   (dname    (handler-case (fluxion.user:field uid "display_name")
                               (error () "")))
                   (disabled (handler-case
                                 (string= "1" (fluxion.user:field uid "disabled"))
                               (error () nil)))
                   (is-admin (strata.auth:is-admin-p uname))
                   (posts    (user-post-count uid))
                   (me       (string= uname me-name)))
              (:tr :class (if disabled "admin-row-disabled" "")
                (:td (:strong uname))
                (:td (or dname ""))
                (:td (princ-to-string posts))
                (:td (if is-admin
                         (:span :class "admin-badge admin-badge-admin" "admin")
                         ""))
                (:td (if disabled
                         (:span :class "admin-badge admin-badge-disabled" "Disabled")
                         (:span :class "admin-badge admin-badge-active" "Active")))
                (:td :class "admin-action-cell"
                  (unless me
                    (if disabled
                        (:button :class "admin-btn admin-btn-sm admin-btn-success"
                                 :type "button"
                                 :data-on-click (format nil "/action/strata-admin/enable-user?username=~A" uname)
                                 "Enable")
                        (:button :class "admin-btn admin-btn-sm admin-btn-danger"
                                 :type "button"
                                 :data-on-click (format nil "/action/strata-admin/disable-user?username=~A" uname)
                                 "Disable")))
                  (unless me
                    (if is-admin
                        (:button :class "admin-btn admin-btn-sm"
                                 :type "button"
                                 :data-on-click (format nil "/action/strata-admin/revoke-admin?username=~A" uname)
                                 "Revoke admin")
                        (:button :class "admin-btn admin-btn-sm"
                                 :type "button"
                                 :data-on-click (format nil "/action/strata-admin/grant-admin?username=~A" uname)
                                 "Grant admin")))
                  (:form :class "admin-inline-form"
                         :data-on-submit (format nil "/action/strata-admin/reset-password?username=~A" uname)
                    (:input :type "password" :name "new_password"
                            :placeholder "New password" :class "admin-input admin-input-sm")
                    (:button :type "submit" :class "admin-btn admin-btn-sm"
                             "Reset pw")))))))))))

(defun render-channels-tab ()
  "Render the Channels management tab."
  (let ((workspaces (handler-case (strata.models.workspace:list-workspaces) (error () nil))))
    (:div :class "admin-tab-content"
      (:h2 "Channels")
      (if workspaces
          (dolist (ws workspaces)
            (let* ((ws-id    (fxdm:model-id ws))
                   (ws-name  (strata.models.workspace:workspace-field ws "display_name"))
                   (channels (handler-case
                                 (strata.models.channel:list-channels-for-workspace ws-id)
                               (error () nil))))
              (:div :class "admin-workspace-group"
                (:h3 :class "admin-workspace-label" ws-name)
                (if channels
                    (:table :class "admin-table"
                      (:thead
                        (:tr (:th "Slug") (:th "Name") (:th "Kind")
                             (:th "Visibility") (:th "Last activity") (:th "Actions")))
                      (:tbody
                        (dolist (ch channels)
                          (let* ((ch-id   (fxdm:model-id ch))
                                 (slug    (strata.models.channel:channel-field ch "slug"))
                                 (name    (strata.models.channel:channel-field ch "name"))
                                 (kind    (or (strata.models.channel:channel-field ch "kind") "open"))
                                 (vis     (or (strata.models.channel:channel-field ch "visibility") "private"))
                                 (la      (strata.models.channel:channel-field ch "last_activity"))
                                 (archived (string= vis "archived")))
                            (:tr :class (if archived "admin-row-disabled" "")
                              (:td (:code slug))
                              (:td name)
                              (:td kind)
                              (:td vis)
                              (:td (format-ts la))
                              (:td :class "admin-action-cell"
                                (if archived
                                    (:button :class "admin-btn admin-btn-sm admin-btn-success"
                                             :type "button"
                                             :data-on-click (format nil "/action/strata-admin/unarchive-channel?id=~A" ch-id)
                                             "Unarchive")
                                    (:button :class "admin-btn admin-btn-sm admin-btn-danger"
                                             :type "button"
                                             :data-on-click (format nil "/action/strata-admin/archive-channel?id=~A" ch-id)
                                             "Archive"))))))))
                    (:p :class "admin-empty" "No channels.")))))
          (:p :class "admin-empty" "No workspaces.")))))

(defun render-workspace-tab ()
  "Render the Workspace settings tab."
  (let ((workspaces (handler-case (strata.models.workspace:list-workspaces) (error () nil))))
    (:div :class "admin-tab-content"
      (:h2 "Workspace settings")
      (if workspaces
          (dolist (ws workspaces)
            (let* ((ws-id   (fxdm:model-id ws))
                   (ws-slug (strata.models.workspace:workspace-field ws "slug"))
                   (ws-name (strata.models.workspace:workspace-field ws "display_name")))
              (:div :class "admin-card"
                (:h3 ws-slug)
                (:form :class "admin-settings-form"
                       :data-on-submit (format nil "/action/strata-admin/update-workspace?id=~A" ws-id)
                  (:label "Display name"
                    (:input :type "text" :name "display_name"
                            :value (or ws-name "")
                            :class "admin-input"))
                  (:button :type "submit" :class "admin-btn admin-btn-primary" "Save")))))
          (:p :class "admin-empty" "No workspaces.")))))

(defun render-storage-tab ()
  "Render the Storage tab showing attachment list and disk usage."
  (let* ((atts  (all-attachment-rows))
         (total (total-attachment-bytes)))
    (:div :class "admin-tab-content"
      (:div :class "admin-section-header"
        (:h2 "Storage")
        (:span :class "admin-stat"
          (format nil "Total: ~A across ~A file~:P"
                  (format-bytes total) (length atts))))
      (if atts
          (:table :class "admin-table"
            (:thead
              (:tr (:th "Filename") (:th "Type") (:th "Size")
                   (:th "Uploader") (:th "Uploaded") (:th "Actions")))
            (:tbody
              (dolist (att atts)
                (let* ((uuid  (strata.models.attachment:attachment-field att "uuid"))
                       (fname (strata.models.attachment:attachment-field att "filename"))
                       (ctype (strata.models.attachment:attachment-field att "content_type"))
                       (size  (strata.models.attachment:attachment-field att "size_bytes"))
                       (uid   (strata.models.attachment:attachment-field att "uploader_id"))
                       (cat   (strata.models.attachment:attachment-field att "created_at"))
                       (url   (format nil "/uploads/~A/~A" uuid fname)))
                  (:tr
                    (:td (:a :href url :target "_blank" :class "admin-link" fname))
                    (:td :class "admin-muted" (or ctype ""))
                    (:td (format-bytes size))
                    (:td (princ-to-string (or uid "")))
                    (:td (format-ts cat))
                    (:td
                      (:button :class "admin-btn admin-btn-sm admin-btn-danger"
                               :type "button"
                               :data-on-click (format nil "/action/strata-admin/delete-attachment?uuid=~A" uuid)
                               "Delete")))))))
          (:p :class "admin-empty" "No attachments.")))))

(defun render-audit-tab ()
  "Render the Audit Log tab."
  (let ((entries (handler-case
                     (strata.models.audit-log:list-recent-events :limit 200)
                   (error () nil))))
    (:div :class "admin-tab-content"
      (:h2 "Audit Log")
      (if entries
          (:table :class "admin-table"
            (:thead
              (:tr (:th "Time") (:th "Actor") (:th "Action")
                   (:th "Target") (:th "Detail")))
            (:tbody
              (dolist (e entries)
                (let* ((ts     (strata.models.audit-log:audit-log-field e "created_at"))
                       (actor  (strata.models.audit-log:audit-log-field e "actor_id"))
                       (action (strata.models.audit-log:audit-log-field e "action"))
                       (ttype  (strata.models.audit-log:audit-log-field e "target_type"))
                       (tid    (strata.models.audit-log:audit-log-field e "target_id"))
                       (detail (strata.models.audit-log:audit-log-field e "detail")))
                  (:tr
                    (:td :class "admin-muted" (format-ts ts))
                    (:td (princ-to-string (or actor "")))
                    (:td (:code action))
                    (:td (when (and ttype (plusp (length ttype)))
                           (format nil "~A #~A" ttype (or tid ""))))
                    (:td :class "admin-detail" (or detail "")))))))
          (:p :class "admin-empty" "No audit log entries yet.")))))

;;; -------------------------------------------------------
;;; Actions
;;; -------------------------------------------------------

(defmacro with-admin-guard (session &body body)
  "Execute BODY only if SESSION has the admin permission; otherwise flash an error."
  (let ((gs (gensym "SESSION")))
    `(let ((,gs ,session))
       (if (admin-p ,gs)
           (progn ,@body)
           (progn
             (setf (admin-flash-msg self) "Permission denied.")
             (fluxion.components:patch-component self))))))

(fluxion.components:defaction admin-component :switch-tab (self params)
  "Switch the active admin tab."
  (let ((tab (cdr (assoc "tab" params :test #'string=))))
    (when (member tab '("users" "channels" "workspace" "storage" "audit")
                  :test #'string=)
      (setf (admin-active-tab self) tab)
      (setf (admin-flash-msg self) nil))
    (fluxion.components:patch-component self)))

(fluxion.components:defaction admin-component :invite-user (self params)
  "Create a new user account."
  (let ((session (fluxion.components:component-session self)))
    (with-admin-guard session
      (let* ((username (cdr (assoc "username"     params :test #'string=)))
             (dname    (cdr (assoc "display_name" params :test #'string=)))
             (password (cdr (assoc "password"     params :test #'string=)))
             (actor-id (session-actor-id session)))
        (handler-case
            (progn
              (fluxion.user:create username :password password
                                            :fields (when (and dname (plusp (length dname)))
                                                      (list (cons "display_name" dname))))
              (strata.models.audit-log:record-event actor-id "user.invite"
                                                    :target-type "user"
                                                    :detail (format nil "created user ~A" username))
              (setf (admin-flash-msg self) (format nil "User ~A created." username)))
          (fluxion.user:user-already-exists ()
            (setf (admin-flash-msg self) (format nil "Username ~A is already taken." username)))
          (error (e)
            (setf (admin-flash-msg self) (format nil "Error: ~A" e))))
        (fluxion.components:patch-component self)))))

(fluxion.components:defaction admin-component :disable-user (self params)
  "Disable a user account."
  (let ((session (fluxion.components:component-session self)))
    (with-admin-guard session
      (let* ((username (cdr (assoc "username" params :test #'string=)))
             (actor-id (session-actor-id session)))
        (handler-case
            (progn
              (strata.auth:disable-user username)
              (strata.models.audit-log:record-event actor-id "user.disable"
                                                    :target-type "user"
                                                    :detail username)
              (setf (admin-flash-msg self) (format nil "~A disabled." username)))
          (error (e)
            (setf (admin-flash-msg self) (format nil "Error: ~A" e))))
        (fluxion.components:patch-component self)))))

(fluxion.components:defaction admin-component :enable-user (self params)
  "Re-enable a disabled user account."
  (let ((session (fluxion.components:component-session self)))
    (with-admin-guard session
      (let* ((username (cdr (assoc "username" params :test #'string=)))
             (actor-id (session-actor-id session)))
        (handler-case
            (progn
              (strata.auth:enable-user username)
              (strata.models.audit-log:record-event actor-id "user.enable"
                                                    :target-type "user"
                                                    :detail username)
              (setf (admin-flash-msg self) (format nil "~A enabled." username)))
          (error (e)
            (setf (admin-flash-msg self) (format nil "Error: ~A" e))))
        (fluxion.components:patch-component self)))))

(fluxion.components:defaction admin-component :grant-admin (self params)
  "Grant the admin permission to a user."
  (let ((session (fluxion.components:component-session self)))
    (with-admin-guard session
      (let* ((username (cdr (assoc "username" params :test #'string=)))
             (actor-id (session-actor-id session)))
        (handler-case
            (progn
              (fluxion.user:grant username "admin")
              (strata.models.audit-log:record-event actor-id "user.grant-admin"
                                                    :target-type "user"
                                                    :detail username)
              (setf (admin-flash-msg self) (format nil "Admin granted to ~A." username)))
          (error (e)
            (setf (admin-flash-msg self) (format nil "Error: ~A" e))))
        (fluxion.components:patch-component self)))))

(fluxion.components:defaction admin-component :revoke-admin (self params)
  "Revoke the admin permission from a user."
  (let ((session (fluxion.components:component-session self)))
    (with-admin-guard session
      (let* ((username (cdr (assoc "username" params :test #'string=)))
             (actor-id (session-actor-id session)))
        (handler-case
            (progn
              (fluxion.user:revoke username "admin")
              (strata.models.audit-log:record-event actor-id "user.revoke-admin"
                                                    :target-type "user"
                                                    :detail username)
              (setf (admin-flash-msg self) (format nil "Admin revoked from ~A." username)))
          (error (e)
            (setf (admin-flash-msg self) (format nil "Error: ~A" e))))
        (fluxion.components:patch-component self)))))

(fluxion.components:defaction admin-component :reset-password (self params)
  "Reset a user's password."
  (let ((session (fluxion.components:component-session self)))
    (with-admin-guard session
      (let* ((username (cdr (assoc "username"     params :test #'string=)))
             (newpw    (cdr (assoc "new_password" params :test #'string=)))
             (actor-id (session-actor-id session)))
        (handler-case
            (progn
              (strata.auth:update-password username newpw)
              (strata.models.audit-log:record-event actor-id "user.reset-password"
                                                    :target-type "user"
                                                    :detail username)
              (setf (admin-flash-msg self) (format nil "Password reset for ~A." username)))
          (error (e)
            (setf (admin-flash-msg self) (format nil "Error: ~A" e))))
        (fluxion.components:patch-component self)))))

(fluxion.components:defaction admin-component :archive-channel (self params)
  "Archive a channel."
  (let ((session (fluxion.components:component-session self)))
    (with-admin-guard session
      (let* ((id-str   (cdr (assoc "id" params :test #'string=)))
             (ch-id    (when id-str (parse-integer id-str :junk-allowed t)))
             (actor-id (session-actor-id session)))
        (handler-case
            (progn
              (strata.models.channel:archive-channel ch-id)
              (strata.models.audit-log:record-event actor-id "channel.archive"
                                                    :target-type "channel"
                                                    :target-id (or ch-id 0))
              (setf (admin-flash-msg self) "Channel archived."))
          (error (e)
            (setf (admin-flash-msg self) (format nil "Error: ~A" e))))
        (fluxion.components:patch-component self)))))

(fluxion.components:defaction admin-component :unarchive-channel (self params)
  "Restore an archived channel."
  (let ((session (fluxion.components:component-session self)))
    (with-admin-guard session
      (let* ((id-str   (cdr (assoc "id" params :test #'string=)))
             (ch-id    (when id-str (parse-integer id-str :junk-allowed t)))
             (actor-id (session-actor-id session)))
        (handler-case
            (progn
              (strata.models.channel:unarchive-channel ch-id)
              (strata.models.audit-log:record-event actor-id "channel.unarchive"
                                                    :target-type "channel"
                                                    :target-id (or ch-id 0))
              (setf (admin-flash-msg self) "Channel restored."))
          (error (e)
            (setf (admin-flash-msg self) (format nil "Error: ~A" e))))
        (fluxion.components:patch-component self)))))

(fluxion.components:defaction admin-component :update-workspace (self params)
  "Update workspace display name."
  (let ((session (fluxion.components:component-session self)))
    (with-admin-guard session
      (let* ((id-str   (cdr (assoc "id"           params :test #'string=)))
             (ws-id    (when id-str (parse-integer id-str :junk-allowed t)))
             (dname    (cdr (assoc "display_name" params :test #'string=)))
             (actor-id (session-actor-id session)))
        (handler-case
            (when (and ws-id dname (plusp (length dname)))
              (strata.models.workspace:update-workspace ws-id :display-name dname)
              (strata.models.audit-log:record-event actor-id "workspace.update"
                                                    :target-type "workspace"
                                                    :target-id (or ws-id 0)
                                                    :detail dname)
              (setf (admin-flash-msg self) "Workspace updated."))
          (error (e)
            (setf (admin-flash-msg self) (format nil "Error: ~A" e))))
        (fluxion.components:patch-component self)))))

(fluxion.components:defaction admin-component :delete-attachment (self params)
  "Permanently delete an attachment file and record."
  (let ((session (fluxion.components:component-session self)))
    (with-admin-guard session
      (let* ((uuid     (cdr (assoc "uuid" params :test #'string=)))
             (actor-id (session-actor-id session)))
        (handler-case
            (progn
              (strata.models.attachment:delete-attachment uuid)
              (strata.models.audit-log:record-event actor-id "attachment.delete"
                                                    :target-type "attachment"
                                                    :detail uuid)
              (setf (admin-flash-msg self) "Attachment deleted."))
          (error (e)
            (setf (admin-flash-msg self) (format nil "Error: ~A" e))))
        (fluxion.components:patch-component self)))))

;;; -------------------------------------------------------
;;; Page entrypoint
;;; -------------------------------------------------------

(defun make-admin ()
  "Create a fresh admin-component instance for use as a per-session factory."
  (make-instance 'admin-component))

(defun render-admin-page (session)
  "Render the full admin panel HTML page for SESSION."
  (let* ((comp  (fx:session-component session "strata-admin"))
         (csrf  (fx:session-csrf-token session)))
    (unless comp
      (error "[strata] admin component not found in session"))
    (render:render-page
     :title "Strata Admin"
     :head-html (format nil
                  "<script src=\"/static/js/theme.js\"></script>~
                   <link rel=\"stylesheet\" href=\"/static/css/strata.css\">~
                   <link rel=\"stylesheet\" href=\"/static/css/admin.css\">")
     :csrf-token csrf
     :body-html  (fluxion.components:render comp)
     :script-path "/static/fluxion.js")))
