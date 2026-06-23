;;;; -*- encoding:utf-8 -*-
;;;; Strata - Profile component
;;;;
;;;; Renders a /profile page where authenticated users can update their
;;;; display name, job title, bio, and password.

(in-package #:strata.components.profile)

;;; -------------------------------------------------------
;;; Component
;;; -------------------------------------------------------

(fluxion.components:defcomponent profile-component
  :id "strata-profile"
  :slots ((success-msg :initform nil :accessor profile-success-msg)
          (error-msg   :initform nil :accessor profile-error-msg)
          (new-token   :initform nil :accessor profile-new-token)
          (key-error   :initform nil :accessor profile-key-error))

  :render
  (let* ((session      (fluxion.components:component-session self))
         (u            (when session (fx:session-user session)))
         (username     (if u (user:user-username u) ""))
         (uid          (if u (user:user-id u) nil))
         (api-keys     (if uid
                           (handler-case (apikey:list-api-keys-for-user uid)
                             (error () nil))
                           nil))
         (display-name (if u
                           (handler-case (user:field (user:user-id u) "display_name")
                             (error () ""))
                           ""))
         (title-field  (if u
                           (handler-case (user:field (user:user-id u) "title")
                             (error () ""))
                           ""))
         (bio-field    (if u
                           (handler-case (user:field (user:user-id u) "bio")
                             (error () ""))
                           "")))
    (spinneret:with-html-string
      (:div :id (fluxion.components:component-id self)
            :class "auth-shell"
        (:div :class "auth-card" :style "max-width:520px;"

          (:div :class "auth-logo" "Strata")
          (:p :class "auth-tagline"
              (format nil "Signed in as @~A" username))

          (when (profile-success-msg self)
            (:p :class "auth-error"
                :style "color:var(--status-open);background:var(--status-open-bg);border-color:var(--status-open);"
                (profile-success-msg self)))
          (when (profile-error-msg self)
            (:p :class "auth-error" (profile-error-msg self)))

          (:h3 :style "font-size:.85rem;font-weight:600;color:var(--text-secondary);
                       letter-spacing:.04em;text-transform:uppercase;margin-bottom:16px;"
               "Profile")

          (:form :class "auth-form"
                 :data-on-submit "/action/strata-profile/save-profile"
            (:div :class "auth-field"
              (:label :for "dp-display-name" "Display name")
              (:input :type "text" :id "dp-display-name" :name "display_name"
                      :value (or display-name "") :placeholder "Your name"))
            (:div :class "auth-field"
              (:label :for "dp-title" "Job title")
              (:input :type "text" :id "dp-title" :name "title"
                      :value (or title-field "") :placeholder "e.g. Site Manager"))
            (:div :class "auth-field"
              (:label :for "dp-bio" "Bio")
              (:input :type "text" :id "dp-bio" :name "bio"
                      :value (or bio-field "") :placeholder "One-liner about you"))
            (:button :type "submit" :class "auth-submit-btn" "Save profile"))

          (:hr :style "border:none;border-top:1px solid var(--border);margin:24px 0;")

          (:h3 :style "font-size:.85rem;font-weight:600;color:var(--text-secondary);
                       letter-spacing:.04em;text-transform:uppercase;margin-bottom:16px;"
               "Change password")

          (:form :class "auth-form"
                 :data-on-submit "/action/strata-profile/change-password"
            (:div :class "auth-field"
              (:label :for "dp-cur-pw" "Current password")
              (:input :type "password" :id "dp-cur-pw" :name "current_password"
                      :autocomplete "current-password"))
            (:div :class "auth-field"
              (:label :for "dp-new-pw" "New password")
              (:input :type "password" :id "dp-new-pw" :name "new_password"
                      :autocomplete "new-password"))
            (:button :type "submit" :class "auth-submit-btn" "Update password"))

          (:hr :style "border:none;border-top:1px solid var(--border);margin:24px 0;")

          (:h3 :style "font-size:.85rem;font-weight:600;color:var(--text-secondary);
                       letter-spacing:.04em;text-transform:uppercase;margin-bottom:16px;"
               "Notifications")
          (:p :id "push-status"
              :style "font-size:.85rem;color:var(--text-secondary);margin-bottom:12px;"
              "Enable browser notifications to be alerted when someone mentions you.")
          (:button :id "push-btn"
                   :type "button"
                   :class "auth-submit-btn"
                   :style "width:auto;padding:8px 20px;"
                   :onclick "strataEnablePush()"
                   "Enable notifications")

          (:hr :style "border:none;border-top:1px solid var(--border);margin:24px 0;")

          (:h3 :style "font-size:.85rem;font-weight:600;color:var(--text-secondary);
                       letter-spacing:.04em;text-transform:uppercase;margin-bottom:16px;"
               "API Keys")
          (:p :style "font-size:.82rem;color:var(--text-muted);margin-bottom:16px;"
            "API keys let agents and scripts access your account via the REST API and "
            "MCP server. A key is shown once on creation - store it safely.")

          (when (profile-key-error self)
            (:p :class "auth-error" (profile-key-error self)))

          (when (profile-new-token self)
            (:div :style "background:var(--bg-elevated);border:1px solid var(--status-open);
                          border-radius:8px;padding:14px 16px;margin-bottom:16px;"
              (:p :style "font-size:.8rem;font-weight:600;color:var(--status-open);margin:0 0 8px;"
                "New key created - copy it now, it will not be shown again:")
              (:code :style "display:block;font-family:monospace;font-size:.82rem;
                             word-break:break-all;color:var(--text-primary);"
                (profile-new-token self))))

          (when api-keys
            (:table :style "width:100%;border-collapse:collapse;font-size:.82rem;margin-bottom:16px;"
              (:thead
                (:tr
                  (:th :style "text-align:left;padding:6px 8px;color:var(--text-muted);font-weight:500;" "Label")
                  (:th :style "text-align:left;padding:6px 8px;color:var(--text-muted);font-weight:500;" "Created")
                  (:th :style "text-align:left;padding:6px 8px;color:var(--text-muted);font-weight:500;" "Last used")
                  (:th)))
              (:tbody
                (dolist (k api-keys)
                  (let ((kid   (fxdm:model-id k))
                        (label (or (apikey:api-key-field k "label") ""))
                        (cat   (or (apikey:api-key-field k "created_at") ""))
                        (lused (apikey:api-key-field k "last_used")))
                    (:tr :style "border-top:1px solid var(--border);"
                      (:td :style "padding:8px;" label)
                      (:td :style "padding:8px;color:var(--text-muted);" cat)
                      (:td :style "padding:8px;color:var(--text-muted);"
                           (if lused (princ-to-string lused) "Never"))
                      (:td :style "padding:8px;text-align:right;"
                        (:button :type "button"
                                 :class "auth-submit-btn"
                                 :style "padding:4px 12px;font-size:.78rem;background:var(--danger-bg);
                                         color:var(--danger);border-color:var(--danger);width:auto;"
                                 :data-on-click (format nil
                                   "/action/strata-profile/revoke-key?key_id=~A" kid)
                                 "Revoke"))))))))

          (:form :class "auth-form"
                 :data-on-submit "/action/strata-profile/create-key"
            (:div :class "auth-field"
              (:label :for "dp-key-label" "New key label")
              (:input :type "text" :id "dp-key-label" :name "label"
                      :placeholder "e.g. opencode, my-script"
                      :autocomplete "off"))
            (:button :type "submit" :class "auth-submit-btn"
                     :style "width:auto;padding:8px 20px;"
                     "Create API key"))

          (:hr :style "border:none;border-top:1px solid var(--border);margin:24px 0;")

          (:a :href "/"
              :style "font-size:.85rem;color:var(--accent);"
              "Back to workspace"))

        (:script
         "(function() {
  function urlBase64ToUint8Array(b) {
    var pad = '='.repeat((4 - b.length % 4) % 4);
    var b64 = (b + pad).replace(/-/g, '+').replace(/_/g, '/');
    var raw = atob(b64);
    var arr = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
    return arr;
  }
  function strataEnablePush() {
    var btn    = document.getElementById('push-btn');
    var status = document.getElementById('push-status');
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      status.textContent = 'Push notifications are not supported in this browser.';
      return;
    }
    Notification.requestPermission().then(function(perm) {
      if (perm !== 'granted') { status.textContent = 'Permission denied.'; return; }
      fetch('/vapid-public-key').then(function(r) { return r.json(); }).then(function(d) {
        navigator.serviceWorker.ready.then(function(reg) {
          reg.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: urlBase64ToUint8Array(d.publicKey)
          }).then(function(sub) {
            fetch('/push/register', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify(sub.toJSON())
            }).then(function() {
              status.textContent = 'Notifications enabled.';
              btn.textContent    = 'Notifications enabled';
              btn.disabled       = true;
            });
          }).catch(function(e) {
            status.textContent = 'Subscription failed: ' + e.message;
          });
        });
      });
    });
  }
  window.strataEnablePush = strataEnablePush;
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js').catch(function(e) {
      console.warn('[strata] SW registration failed:', e);
    });
  }
})();")))))

;;; -------------------------------------------------------
;;; Actions
;;; (defcomponent body ends above at line ~156 -- 5 parens close:
;;;  script, div.auth-shell, with-html-string, let*, defcomponent)
;;; -------------------------------------------------------

(fluxion.components:defaction profile-component :save-profile (self params)
  "Persist display_name, title, and bio for the session user."
  (let* ((session      (fluxion.components:component-session self))
         (u            (when session (fx:session-user session)))
         (uid          (when u (user:user-id u)))
         (display-name (cdr (assoc "display_name" params :test #'string=)))
         (title-val    (cdr (assoc "title"        params :test #'string=)))
         (bio-val      (cdr (assoc "bio"          params :test #'string=))))
    (if (null uid)
        (progn
          (setf (profile-error-msg self) "Not signed in.")
          (fluxion.components:patch-component self))
        (handler-case
            (progn
              (when display-name (user:set-field uid "display_name" display-name))
              (when title-val    (user:set-field uid "title"        title-val))
              (when bio-val      (user:set-field uid "bio"          bio-val))
              (setf (profile-success-msg self) "Profile saved."
                    (profile-error-msg   self) nil)
              (fluxion.components:patch-component self))
          (error (e)
            (setf (profile-error-msg   self) (format nil "Error: ~A" e)
                  (profile-success-msg self) nil)
            (fluxion.components:patch-component self))))))

(fluxion.components:defaction profile-component :change-password (self params)
  "Verify current password and update to new password for the session user."
  (let* ((session  (fluxion.components:component-session self))
         (u        (when session (fx:session-user session)))
         (username (when u (user:user-username u)))
         (cur-pw   (cdr (assoc "current_password" params :test #'string=)))
         (new-pw   (cdr (assoc "new_password"     params :test #'string=))))
    (cond
      ((null username)
       (setf (profile-error-msg self) "Not signed in.")
       (fluxion.components:patch-component self))
      ((or (null new-pw) (< (length new-pw) 8))
       (setf (profile-error-msg self) "New password must be at least 8 characters.")
       (fluxion.components:patch-component self))
      (t
       (handler-case
           (progn
             (auth:login username cur-pw)
             (strata.auth:update-password username new-pw)
             (setf (profile-success-msg self) "Password updated."
                   (profile-error-msg   self) nil)
             (fluxion.components:patch-component self))
         (fluxion.auth:authentication-failed ()
           (setf (profile-error-msg   self) "Current password is incorrect."
                 (profile-success-msg self) nil)
           (fluxion.components:patch-component self))
         (error (e)
           (setf (profile-error-msg   self) (format nil "Error: ~A" e)
                 (profile-success-msg self) nil)
           (fluxion.components:patch-component self)))))))

(fluxion.components:defaction profile-component :create-key (self params)
  "Create a new API key for the current user.
The raw token is stored in the new-token slot for one render cycle."
  (let* ((session (fluxion.components:component-session self))
         (u       (when session (fx:session-user session)))
         (uid     (when u (user:user-id u)))
         (label   (string-trim '(#\Space #\Tab)
                               (or (cdr (assoc "label" params :test #'string=)) ""))))
    (setf (profile-new-token self) nil
          (profile-key-error  self) nil)
    (cond
      ((not uid)
       (setf (profile-key-error self) "Not signed in."))
      ((zerop (length label))
       (setf (profile-key-error self) "Label is required."))
      (t
       (handler-case
           (multiple-value-bind (raw-token _key)
               (apikey:create-api-key uid :label label)
             (declare (ignore _key))
             (setf (profile-new-token self) raw-token))
         (error (e)
           (setf (profile-key-error self)
                 (format nil "Could not create key: ~A" e))))))
    (fluxion.components:patch-component self)))

(fluxion.components:defaction profile-component :revoke-key (self params)
  "Revoke an API key by ID, if it belongs to the current user."
  (let* ((session (fluxion.components:component-session self))
         (u       (when session (fx:session-user session)))
         (uid     (when u (user:user-id u)))
         (kid-str (cdr (assoc "key_id" params :test #'string=)))
         (kid     (when kid-str (handler-case (parse-integer kid-str) (error () nil)))))
    (setf (profile-new-token self) nil
          (profile-key-error  self) nil)
    (cond
      ((not uid)
       (setf (profile-key-error self) "Not signed in."))
      ((not kid)
       (setf (profile-key-error self) "Invalid key ID."))
      (t
       (handler-case
           (let ((key (apikey:find-api-key-by-id kid)))
             (cond
               ((null key)
                (setf (profile-key-error self) "Key not found."))
               ((/= uid (apikey:api-key-field key "user_id"))
                (setf (profile-key-error self) "That key does not belong to your account."))
               (t
                (apikey:revoke-api-key kid))))
         (error (e)
           (setf (profile-key-error self)
                 (format nil "Could not revoke key: ~A" e))))))
    (fluxion.components:patch-component self)))

;;; -------------------------------------------------------
;;; Factory and page renderer
;;; -------------------------------------------------------

(defun make-profile ()
  "Create a fresh profile-component instance for use as a per-session factory."
  (make-instance 'profile-component))

(defun render-profile-page (session)
  "Render the full profile HTML page for SESSION."
  (let ((component (fx:session-component session "strata-profile"))
        (csrf      (fx:session-csrf-token session)))
    (unless component
      (error "[strata] profile component missing from session"))
    (render:render-page
     :title "Strata - Profile"
     :head-html "<link rel=\"stylesheet\" href=\"/static/css/strata.css\">
<script src=\"/static/js/theme.js\"></script>"
     :csrf-token csrf
     :body-html (fluxion.components:render component)
     :script-path "/static/fluxion.js")))
