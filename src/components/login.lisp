;;;; -*- encoding:utf-8 -*-
;;;; Strata - Login and first-run setup components

(in-package #:strata.components.login)

;;; -------------------------------------------------------
;;; Shared page chrome
;;; -------------------------------------------------------

(defun auth-head-html ()
  "Return <head> extras shared by the login and setup pages."
  "<link rel=\"stylesheet\" href=\"/static/css/strata.css\">
<script src=\"/static/js/theme.js\"></script>")

(defun render-auth-page (title body-html csrf-token)
  "Render a minimal centred auth page with TITLE, BODY-HTML, and CSRF-TOKEN."
  (render:render-page
   :title title
   :head-html (auth-head-html)
   :csrf-token csrf-token
   :body-html body-html
   :script-path "/static/fluxion.js"))

;;; -------------------------------------------------------
;;; Login component
;;; -------------------------------------------------------

(fluxion.components:defcomponent login-component
  :id "strata-login"
  :slots ((error-msg :initform nil :accessor login-error-msg))

  :render
  (spinneret:with-html-string
    (:div :id (fluxion.components:component-id self)
          :class "auth-shell"
      (:div :class "auth-card"
        (:div :class "auth-logo" "Strata")
        (:p :class "auth-tagline" "Sign in to your workspace")
        (when (login-error-msg self)
          (:p :class "auth-error" (login-error-msg self)))
        (:form :class "auth-form"
               :data-on-submit "/action/strata-login/login"
          (:div :class "auth-field"
            (:label :for "username" "Username")
            (:input :type "text" :id "username" :name "username"
                    :autocomplete "username" :required t
                    :placeholder "your-username"))
          (:div :class "auth-field"
            (:label :for "password" "Password")
            (:input :type "password" :id "password" :name "password"
                    :autocomplete "current-password" :required t
                    :placeholder "password"))
          (:button :type "submit" :class "auth-submit-btn"
                   :data-disable-during-request t
            "Sign in"))))))

(fluxion.components:defaction login-component :login (self params)
  "Authenticate with the provided username and password.
On success redirects the browser to / via a script SSE event.
On failure sets the error-msg slot and re-renders."
  (let ((username (cdr (assoc "username" params :test #'string=)))
        (password (cdr (assoc "password" params :test #'string=))))
    (handler-case
        (progn
          (auth:login username password)
          (when (strata.auth:user-disabled-p username)
            (auth:logout)
            (error 'fluxion.auth:authentication-failed :username username))
          (list (events:make-redirect-event "/")))
      (fluxion.auth:authentication-failed ()
        (setf (login-error-msg self) "Invalid username or password.")
        (fluxion.components:patch-component self)))))

(defun make-login ()
  "Create a fresh login-component instance for the per-session factory."
  (make-instance 'login-component))

(defun render-login-page (session)
  "Render the full login page HTML for SESSION."
  (let ((component (fx:session-component session "strata-login"))
        (csrf (fx:session-csrf-token session)))
    (unless component
      (error "[strata] login component missing from session"))
    (render-auth-page "Strata - Sign in"
                      (fluxion.components:render component)
                      csrf)))

;;; -------------------------------------------------------
;;; First-run workspace seed
;;; -------------------------------------------------------

(defun seed-default-workspace (display-name)
  "Create a default workspace and starter channels after first admin signup.
 DISPLAY-NAME is the admin's name, used to personalise the workspace name."
  (let* ((ws-name (if (and display-name (plusp (length (string-trim '(#\Space) display-name))))
                      (format nil "~A's Workspace" (string-trim '(#\Space) display-name))
                      "My Workspace"))
         (workspace (ws:create-workspace
                     :slug "default"
                     :display-name ws-name))
         (ws-id (ws:workspace-field workspace "_id")))
    (chan:create-channel :workspace-id ws-id :slug "general"
                         :name "general"
                         :description "Team-wide announcements and discussion")
    (chan:create-channel :workspace-id ws-id :slug "random"
                         :name "random"
                         :description "Non-work chatter")
    (chan:create-channel :workspace-id ws-id :slug "decisions"
                         :name "decisions"
                         :description "Logged decisions and their reasoning"
                         :kind "open")))

;;; -------------------------------------------------------
;;; First-run setup component
;;; -------------------------------------------------------

(fluxion.components:defcomponent setup-component
  :id "strata-setup"
  :slots ((error-msg :initform nil :accessor setup-error-msg))

  :render
  (spinneret:with-html-string
    (:div :id (fluxion.components:component-id self)
          :class "auth-shell"
      (:div :class "auth-card"
        (:div :class "auth-logo" "Strata")
        (:p :class "auth-tagline" "Create your admin account to get started")
        (when (setup-error-msg self)
          (:p :class "auth-error" (setup-error-msg self)))
        (:form :class "auth-form"
               :data-on-submit "/action/strata-setup/create-admin"
          (:div :class "auth-field"
            (:label :for "display-name" "Display name")
            (:input :type "text" :id "display-name" :name "display_name"
                    :required t :placeholder "e.g. Jane Smith"))
          (:div :class "auth-field"
            (:label :for "setup-username" "Username")
            (:input :type "text" :id "setup-username" :name "username"
                    :autocomplete "username" :required t
                    :placeholder "e.g. jsmith"))
          (:div :class "auth-field"
            (:label :for "setup-password" "Password")
            (:input :type "password" :id "setup-password" :name "password"
                    :autocomplete "new-password" :required t
                    :placeholder "choose a strong password"))
          (:button :type "submit" :class "auth-submit-btn"
                   :data-disable-during-request t
            "Create account & sign in"))
        (:p :class "auth-alt-link"
          "Already have an account? "
          (:a :href "/login" "Sign in"))))))

(fluxion.components:defaction setup-component :create-admin (self params)
  "Create the first admin user and log them in.
Expects params: username, password, display_name.
On success, redirects to /. On failure, shows an error message."
  (let ((username     (cdr (assoc "username"     params :test #'string=)))
        (password     (cdr (assoc "password"     params :test #'string=)))
        (display-name (cdr (assoc "display_name" params :test #'string=))))
    (cond
      ((or (null username) (zerop (length (string-trim '(#\Space) username))))
       (setf (setup-error-msg self) "Username is required.")
       (fluxion.components:patch-component self))
      ((or (null password) (< (length password) 8))
       (setf (setup-error-msg self) "Password must be at least 8 characters.")
       (fluxion.components:patch-component self))
      (t
       (handler-case
           (progn
             (user:create username
                          :password password
                          :fields (when (and display-name
                                             (plusp (length (string-trim '(#\Space) display-name))))
                                    (list (cons "display_name" display-name))))
             (user:grant username "admin")
             (auth:login username password)
             (seed-default-workspace display-name)
             (list (events:make-redirect-event "/")))
         (fluxion.user:user-already-exists ()
           (setf (setup-error-msg self) "That username is already taken.")
           (fluxion.components:patch-component self))
         (error (e)
           (setf (setup-error-msg self)
                 (format nil "Error: ~A" e))
           (fluxion.components:patch-component self)))))))

(defun make-setup ()
  "Create a fresh setup-component instance for the per-session factory."
  (make-instance 'setup-component))

(defun render-setup-page (session)
  "Render the first-run admin setup page HTML for SESSION."
  (let ((component (fx:session-component session "strata-setup"))
        (csrf (fx:session-csrf-token session)))
    (unless component
      (error "[strata] setup component missing from session"))
    (render-auth-page "Strata - Setup"
                      (fluxion.components:render component)
                      csrf)))
