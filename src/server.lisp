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

(defparameter *max-upload-bytes* (* 25 1024 1024)
  "Maximum permitted upload size in bytes (default 25 MB).")

(defun %mime-type-for (filename)
  "Return a plausible MIME type string based on FILENAME extension."
  (let ((ext (string-downcase
               (or (pathname-type (pathname filename)) ""))))
    (cond
      ((member ext '("jpg" "jpeg") :test #'string=) "image/jpeg")
      ((string= ext "png")  "image/png")
      ((string= ext "gif")  "image/gif")
      ((string= ext "webp") "image/webp")
      ((string= ext "svg")  "image/svg+xml")
      ((string= ext "pdf")  "application/pdf")
      ((string= ext "txt")  "text/plain")
      ((string= ext "md")   "text/markdown")
      (t                    "application/octet-stream"))))

(defun %image-content-type-p (content-type)
  "Return T if CONTENT-TYPE string indicates an image."
  (and (stringp content-type)
       (let ((ct (string-downcase content-type)))
         (or (search "image/" ct) nil))))

(defun upload-handler (session env)
  "Handle POST /upload - store a multipart file upload.
Requires an authenticated session. Returns JSON with the attachment UUID
and download URL, or a JSON error."
  (unless (fluxion.server:session-user session)
    (return-from upload-handler
      (list 401 '(:content-type "application/json")
            '("{\"error\":\"unauthenticated\"}"))))
  (handler-case
      (let* ((content-type (or (getf env :content-type) ""))
             (body-stream  (getf env :raw-body))
             (content-len  (or (getf env :content-length) 0)))
        (unless (search "multipart/form-data" content-type)
          (return-from upload-handler
            (list 400 '(:content-type "application/json")
                  '("{\"error\":\"expected multipart/form-data\"}"))))
        (when (> content-len *max-upload-bytes*)
          (return-from upload-handler
            (list 413 '(:content-type "application/json")
                  '("{\"error\":\"file too large\"}"))))
        (let* ((boundary  (let ((pos (search "boundary=" content-type)))
                            (when pos
                              (string-trim '(#\Space #\Tab #\Return #\Newline)
                                           (subseq content-type (+ pos 9))))))
               (parts     (rfc2388:parse-mime body-stream boundary))
               (file-part (find-if
                           (lambda (p)
                             (let ((cd (rfc2388:find-content-disposition-header
                                        (rfc2388:mime-part-headers p))))
                               (when cd
                                 (string-equal
                                  "file"
                                  (cdr (rfc2388:find-parameter
                                        "name"
                                        (rfc2388:header-parameters cd)))))))
                           parts))
               (post-id-str  (let ((p (find-if
                                       (lambda (pt)
                                         (let ((cd (rfc2388:find-content-disposition-header
                                                    (rfc2388:mime-part-headers pt))))
                                           (when cd
                                             (string-equal
                                              "post_id"
                                              (cdr (rfc2388:find-parameter
                                                    "name"
                                                    (rfc2388:header-parameters cd)))))))
                                       parts)))
                               (when p (rfc2388:mime-part-contents p))))
               (reply-id-str (let ((p (find-if
                                       (lambda (pt)
                                         (let ((cd (rfc2388:find-content-disposition-header
                                                    (rfc2388:mime-part-headers pt))))
                                           (when cd
                                             (string-equal
                                              "reply_id"
                                              (cdr (rfc2388:find-parameter
                                                    "name"
                                                    (rfc2388:header-parameters cd)))))))
                                       parts)))
                               (when p (rfc2388:mime-part-contents p)))))
          (unless file-part
            (return-from upload-handler
              (list 400 '(:content-type "application/json")
                    '("{\"error\":\"no file field\"}"))))
          (let* ((orig-name (or (rfc2388:get-file-name
                                 (rfc2388:mime-part-headers file-part))
                                "upload"))
                 (file-data (let ((b (rfc2388:mime-part-contents file-part)))
                              (if (stringp b)
                                  (sb-ext:string-to-octets b :external-format :latin-1)
                                  b)))
                 (size      (length file-data))
                 (ctype     (%mime-type-for orig-name))
                 (uid       (strata.auth:user-id-from-session session))
                 (post-id   (when (and post-id-str (not (string= post-id-str "")))
                              (parse-integer post-id-str :junk-allowed t)))
                 (reply-id  (when (and reply-id-str (not (string= reply-id-str "")))
                              (parse-integer reply-id-str :junk-allowed t)))
                 (att       (strata.models.attachment:create-attachment
                             :post-id      post-id
                             :reply-id     reply-id
                             :uploader-id  uid
                             :filename     orig-name
                             :content-type ctype
                             :size-bytes   size
                             :file-data    file-data))
                 (uuid      (strata.models.attachment:attachment-field att "uuid"))
                 (safe-name (strata.models.attachment:attachment-field att "filename")))
            (list 200 '(:content-type "application/json")
                  (list (format nil
                                "{\"ok\":true,\"uuid\":\"~A\",\"url\":\"/uploads/~A/~A\",\"filename\":\"~A\",\"size\":~D}"
                                uuid uuid safe-name safe-name size))))))
    (error (e)
      (format t "~&[strata] upload error: ~A~%" e)
      (list 500 '(:content-type "application/json")
            '("{\"error\":\"internal server error\"}")))))

(defun download-handler (session path)
  "Handle GET /uploads/<uuid>/<filename> - serve an uploaded file.
Requires an authenticated session to prevent unauthenticated scraping."
  (unless (fluxion.server:session-user session)
    (return-from download-handler
      (list 401 '(:content-type "application/json")
            '("{\"error\":\"unauthenticated\"}"))))
  (handler-case
      (let* ((parts    (cl-ppcre:split "/" path :sharedp nil))
             (uuid     (find-if (lambda (s) (> (length s) 0))
                                (rest (rest parts))))
             (filename (car (last parts))))
        (unless (and uuid filename (not (string= uuid filename)))
          (return-from download-handler
            (list 404 '(:content-type "text/plain") '("Not found"))))
        (let* ((att     (strata.models.attachment:find-attachment-by-uuid uuid))
               (safe-fn (when att
                          (strata.models.attachment:attachment-field att "filename"))))
          (unless (and att (string= safe-fn filename))
            (return-from download-handler
              (list 404 '(:content-type "text/plain") '("Not found"))))
          (let* ((file-path   (merge-pathnames
                               (format nil "~A/~A" uuid filename)
                               strata.models.attachment:*upload-dir*))
                 (ctype       (or (strata.models.attachment:attachment-field att "content_type")
                                  "application/octet-stream"))
                 (disposition (if (%image-content-type-p ctype)
                                  "inline"
                                  (format nil "attachment; filename=\"~A\"" filename))))
            (with-open-file (in file-path
                                :direction         :input
                                :element-type      '(unsigned-byte 8)
                                :if-does-not-exist nil)
              (if (null in)
                  (list 404 '(:content-type "text/plain") '("Not found"))
                  (let* ((size (file-length in))
                         (buf  (make-array size :element-type '(unsigned-byte 8))))
                    (read-sequence buf in)
                    (list 200
                          (list :content-type          ctype
                                :content-disposition   disposition
                                :content-length        size
                                :x-content-type-options "nosniff")
                          (list buf))))))))
    (error (e)
      (format t "~&[strata] download error: ~A~%" e)
      (list 500 '(:content-type "text/plain") '("Internal server error")))))

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
      ;; REST API - stateless, authenticated via Bearer token
      ((and (>= (length path) 8) (string= "/api/v1/" (subseq path 0 8)))
       (strata.api:handle-api-request env))

      ;; MCP server - JSON-RPC 2.0, authenticated via Bearer token
      ((string= path "/mcp")
       (strata.mcp:handle-mcp-request env))

      ;; First-run setup page
      ((string= path "/setup")
       (html-response (strata.components.login:render-setup-page session)))

      ;; Login page
      ((string= path "/login")
       (html-response (strata.components.login:render-login-page session)))

      ;; Self-signup registration page
      ((string= path "/register")
       (html-response (strata.components.login:render-register-page session)))

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

      ;; File upload endpoint (POST /upload, requires auth)
      ((and (string= (getf env :request-method) "POST")
            (string= path "/upload"))
       (upload-handler session env))

      ;; File download endpoint (GET /uploads/*, requires auth)
      ((and (string= (getf env :request-method) "GET")
            (cl-ppcre:scan "^/uploads/" path))
       (download-handler session path))

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

      ;; Admin panel (requires admin permission)
      ((string= path "/admin")
       (if (strata.auth:is-admin-p
            (let ((u (fx:session-user session)))
              (when u (fluxion.user:user-username u))))
           (html-response (strata.components.admin:render-admin-page session))
           (redirect-response "/")))

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
  (strata.api:setup-routes)
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
