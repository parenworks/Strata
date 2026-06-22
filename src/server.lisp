;;;; -*- encoding:utf-8 -*-
;;;; Strata - Server start / stop

(in-package #:strata.server)

(defvar *port* 4242
  "Default HTTP port for the Strata server.")

(defun html-response (html)
  "Wrap HTML string as a 200 text/html Clack response."
  (list 200 '(:content-type "text/html; charset=utf-8") (list html)))

(defun redirect-response (location)
  "Return a 302 redirect Clack response to LOCATION."
  (list 302 (list :location location) '("")))

(defun json-body (env)
  "Read and parse the JSON request body from ENV. Returns an alist or NIL."
  (handler-case
      (let* ((body   (getf env :raw-body))
             (length (or (getf env :content-length) 0))
             (buf    (make-array length :element-type '(unsigned-byte 8)))
             (n      (read-sequence buf body)))
        (json:decode-json-from-string
         (sb-ext:octets-to-string (subseq buf 0 n) :external-format :utf-8)))
    (error () nil)))

(defun push-handler (session env)
  "Handle POST requests under /push/."
  (let ((path    (getf env :path-info "/"))
        (user    (fluxion.server:session-user session)))
    (unless user
      (return-from push-handler
        (list 401 '(:content-type "application/json") '("{\"error\":\"unauthenticated\"}"))))
    (let ((uid  (strata.auth:user-id-from-session session))
          (body (json-body env)))
      (cond
        ((string= path "/push/register")
         (let ((endpoint (cdr (assoc :endpoint body)))
               (p256dh   (cdr (assoc :p256dh   (cdr (assoc :keys body)))))
               (auth-key (cdr (assoc :auth     (cdr (assoc :keys body))))))
           (when (and endpoint p256dh auth-key)
             (strata.models.push-subscription:save-subscription
              uid endpoint p256dh auth-key))
           (list 200 '(:content-type "application/json") '("{\"ok\":true}"))))
        ((string= path "/push/unregister")
         (let ((endpoint (cdr (assoc :endpoint body))))
           (when endpoint
             (strata.models.push-subscription:delete-subscription endpoint)))
         (list 200 '(:content-type "application/json") '("{\"ok\":true}")))
        (t
         (list 404 '(:content-type "application/json") '("{\"error\":\"not found\"}")))))))

(defun page-handler (application session env)
  "Route an incoming page GET to the correct component.

Guard logic:
  1. No users in DB -> redirect to /setup (first-run).
  2. User not in session -> redirect to /login.
  3. Logged in -> serve the shell.

/login and /setup are served directly without the auth guard."
  (declare (ignore application))
  (let ((path (getf env :path-info "/")))
    (cond
      ;; First-run setup page
      ((string= path "/setup")
       (html-response (strata.components.login:render-setup-page session)))

      ;; Login page
      ((string= path "/login")
       (html-response (strata.components.login:render-login-page session)))

      ;; Guard: no users yet -> first-run setup
      ((not (strata.auth:any-users-p))
       (redirect-response "/setup"))

      ;; Guard: not authenticated -> login
      ((null (fluxion.server:session-user session))
       (redirect-response "/login"))

      ;; Push registration endpoints (POST, require auth)
      ((and (string= (getf env :request-method) "POST")
            (or (string= path "/push/register")
                (string= path "/push/unregister")))
       (push-handler session env))

      ;; VAPID public key (needed by the JS before login, no auth needed)
      ((string= path "/vapid-public-key")
       (list 200 '(:content-type "application/json")
             (list (format nil "{\"publicKey\":\"~A\"}" strata.push:*vapid-public-key-b64*))))

      ;; Profile page (requires auth)
      ((string= path "/profile")
       (html-response (strata.components.profile:render-profile-page session)))

      ;; Inbox page (requires auth)
      ((string= path "/inbox")
       (html-response (strata.components.inbox:render-inbox-page session)))

      ;; Search page (requires auth)
      ((string= path "/search")
       (html-response (strata.components.search:render-search-page session)))

      ;; Authenticated: serve the shell
      (t
       (html-response (strata.components.shell:render-page-for-session session))))))

(defun start (&key (port *port*)
                   (db-name "strata_dev")
                   (db-user "strata")
                   (db-password "localtest123")
                   (db-host "localhost")
                   (db-port 5432))
  "Start Strata: connect to PostgreSQL, run migrations, start the Woo HTTP server."
  (format t "~&[strata] Connecting to database ~A@~A:~D/~A ...~%"
          db-user db-host db-port db-name)
  (strata.app:connect-db :database db-name
                         :user db-user
                         :password db-password
                         :host db-host
                         :port db-port)
  (format t "~&[strata] Database ready.~%")
  (strata.app:make-app :port port)
  (strata.jobs.notifications:start-notification-hooks)
  (strata.jobs.search:start-search-hooks)
  (strata.jobs.search:backfill-search-index)
  (fluxion.server:start strata.app:*app* #'page-handler :address "0.0.0.0")
  (format t "~&[strata] Server started on http://0.0.0.0:~D  (LAN accessible)~%" port)
  strata.app:*app*)

(defun run (&rest args &key (port *port*) &allow-other-keys)
  "Start Strata and block the calling thread until interrupted.
 Use this to run Strata from a terminal or script."
  (declare (ignore port))
  (apply #'start args)
  (format t "~&[strata] Running. Press C-c to stop.~%")
  (handler-case
      (loop (sleep 60))
    (#+sbcl sb-sys:interactive-interrupt
     #-sbcl condition ()
      (format t "~&[strata] Interrupted. Shutting down...~%")
      (stop))))

(defun main ()
  "Binary entry point. Parses command-line arguments and calls RUN.
Recognised flags (all optional, defaults from *port* and strata.app:connect-db):
  --port PORT           HTTP listen port (default 4242)
  --db-name NAME        PostgreSQL database name (default strata_dev)
  --db-user USER        PostgreSQL user (default strata)
  --db-password PASS    PostgreSQL password
  --db-host HOST        PostgreSQL host (default localhost)
  --db-port PORT        PostgreSQL port (default 5432)"
  (let ((args #+sbcl (cdr sb-ext:*posix-argv*) #-sbcl nil)
        (port *port*)
        (db-name "strata_dev")
        (db-user "strata")
        (db-password "localtest123")
        (db-host "localhost")
        (db-port 5432))
    (loop while args do
      (let ((flag (pop args))
            (val  (pop args)))
        (cond
          ((string= flag "--port")        (setf port     (parse-integer val)))
          ((string= flag "--db-name")     (setf db-name  val))
          ((string= flag "--db-user")     (setf db-user  val))
          ((string= flag "--db-password") (setf db-password val))
          ((string= flag "--db-host")     (setf db-host  val))
          ((string= flag "--db-port")     (setf db-port  (parse-integer val)))
          (t (format t "~&[strata] Unknown flag: ~A~%" flag)))))
    (run :port port
         :db-name db-name
         :db-user db-user
         :db-password db-password
         :db-host db-host
         :db-port db-port)))

(defun stop ()
  "Stop the Strata server and disconnect from the database."
  (when strata.app:*app*
    (fluxion.server:stop strata.app:*app*)
    (format t "~&[strata] Server stopped.~%"))
  (when strata.app:*db-backend*
    (fluxion.db:disconnect strata.app:*db-backend*)
    (format t "~&[strata] Database disconnected.~%")))
