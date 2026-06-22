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
          (error-msg   :initform nil :accessor profile-error-msg))

  :render
  (let* ((session      (fluxion.components:component-session self))
         (u            (when session (fx:session-user session)))
         (username     (if u (user:user-username u) ""))
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
