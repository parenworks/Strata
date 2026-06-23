;;;; -*- encoding:utf-8 -*-
;;;; Strata - REST API v1
;;;;
;;;; Stateless JSON API authenticated via Bearer tokens (API keys).
;;;; All endpoints live under /api/v1/.
;;;;
;;;; Authentication:
;;;;   Authorization: Bearer <token>
;;;;
;;;; Endpoints:
;;;;   GET  /api/v1/me
;;;;   GET  /api/v1/me/keys            - list caller's API keys
;;;;   POST /api/v1/me/keys            - create a new API key
;;;;   DELETE /api/v1/me/keys/:id      - revoke an API key
;;;;   GET  /api/v1/channels           - list visible channels (workspace 1)
;;;;   GET  /api/v1/channels/:slug     - single channel info
;;;;   GET  /api/v1/channels/:slug/posts - paginated posts
;;;;   POST /api/v1/channels/:slug/posts - create a post
;;;;   GET  /api/v1/posts/:id          - single post
;;;;   GET  /api/v1/posts/:id/replies  - replies to a post
;;;;   POST /api/v1/posts/:id/replies  - create a reply

(in-package #:strata.api)

;;; -------------------------------------------------------
;;; Router
;;; -------------------------------------------------------

(defvar *router* nil
  "The API router instance. Initialised by setup-routes.")

;;; -------------------------------------------------------
;;; Helpers
;;; -------------------------------------------------------

(defun api-401 ()
  (list 401
        '(:content-type "application/json; charset=utf-8")
        '("{\"error\":\"Unauthorized\"}")))

(defun api-403 ()
  (list 403
        '(:content-type "application/json; charset=utf-8")
        '("{\"error\":\"Forbidden\"}")))

(defun api-404 (&optional (msg "Not found"))
  (list 404
        '(:content-type "application/json; charset=utf-8")
        (list (fxapi:encode-json (list :error msg)))))

(defun api-400 (msg)
  (list 400
        '(:content-type "application/json; charset=utf-8")
        (list (fxapi:encode-json (list :error msg)))))

(defun api-ok (data)
  (fxapi:json-response data))

(defun bearer-token (env)
  "Extract the raw token from Authorization: Bearer <token>, or NIL."
  (let ((auth (gethash "authorization" (getf env :headers))))
    (when (and auth (> (length auth) 7)
               (string-equal "bearer " (subseq auth 0 7)))
      (string-trim '(#\Space #\Tab) (subseq auth 7)))))

(defun authenticate-request (env)
  "Return the fluxion user alist for the Bearer token in ENV, or NIL."
  (let ((token (bearer-token env)))
    (when token
      (let ((key (strata.models.api-key:find-api-key-by-token token)))
        (when key
          (let ((uid (strata.models.api-key:api-key-field key "user_id")))
            (when uid
              (strata.auth:get-user-by-id uid))))))))

(defun param (params name)
  "Get string value of NAME from PARAMS alist (string or keyword key)."
  (or (cdr (assoc name        params :test #'string=))
      (cdr (assoc (intern (string-upcase name) :keyword) params))))

(defun parse-int-param (params name &optional (default nil))
  "Parse an integer query param NAME from PARAMS, returning DEFAULT on failure."
  (let ((v (param params name)))
    (if v
        (handler-case (parse-integer v :junk-allowed t)
          (error () default))
        default)))

(defun user-id-from-user (u)
  "Return the _id integer from a Fluxion user alist."
  (when u (fluxion.user:user-id u)))

(defun user-username (u)
  "Return the username string from a Fluxion user alist."
  (when u (fluxion.user:user-username u)))

(defun serialize-post (post)
  "Return a plist representation of POST suitable for JSON encoding."
  (list :id         (fxdm:model-id post)
        :channel_id (strata.models.post:post-field post "channel_id")
        :author_id  (strata.models.post:post-field post "author_id")
        :body       (strata.models.post:post-field post "body")
        :kind       (or (strata.models.post:post-field post "kind") "message")
        :status     (or (strata.models.post:post-field post "status") "active")
        :created_at (strata.models.post:post-field post "created_at")))

(defun serialize-reply (reply)
  "Return a plist representation of REPLY suitable for JSON encoding."
  (list :id         (fxdm:model-id reply)
        :post_id    (strata.models.reply:reply-field reply "post_id")
        :author_id  (strata.models.reply:reply-field reply "author_id")
        :body       (strata.models.reply:reply-field reply "body")
        :created_at (strata.models.reply:reply-field reply "created_at")))

(defun serialize-channel (ch)
  "Return a plist representation of channel CH."
  (list :id           (fxdm:model-id ch)
        :slug         (strata.models.channel:channel-field ch "slug")
        :name         (strata.models.channel:channel-field ch "name")
        :description  (or (strata.models.channel:channel-field ch "description") "")
        :kind         (or (strata.models.channel:channel-field ch "kind") "open")
        :visibility   (or (strata.models.channel:channel-field ch "visibility") "private")
        :last_activity (strata.models.channel:channel-field ch "last_activity")))

(defun serialize-api-key (k &optional raw-token)
  "Return a plist for api-key K. Includes raw_token only when provided."
  (let ((base (list :id         (fxdm:model-id k)
                    :label      (strata.models.api-key:api-key-field k "label")
                    :created_at (strata.models.api-key:api-key-field k "created_at")
                    :last_used  (strata.models.api-key:api-key-field k "last_used"))))
    (if raw-token
        (append base (list :token raw-token))
        base)))

;;; -------------------------------------------------------
;;; Route setup
;;; -------------------------------------------------------

(defun setup-routes ()
  "Register all /api/v1/ routes onto *router*."
  (setf *router* (fluxion.server:make-router))

  ;; GET /api/v1/me
  (fluxion.server:add-route
   *router* :get "/api/v1/me"
   (lambda (app session env &key params)
     (declare (ignore app session params))
     (block route
       (let ((user (authenticate-request env)))
         (unless user (return-from route (api-401)))
         (let* ((uid   (user-id-from-user user))
                (uname (user-username user))
                (dname (handler-case (fluxion.user:field uid "display_name")
                         (error () ""))))
           (api-ok (list :id           uid
                         :username     uname
                         :display_name (or dname ""))))))))

  ;; GET /api/v1/me/keys
  (fluxion.server:add-route
   *router* :get "/api/v1/me/keys"
   (lambda (app session env &key params)
     (declare (ignore app session params))
     (block route
       (let ((user (authenticate-request env)))
         (unless user (return-from route (api-401)))
         (let* ((uid  (user-id-from-user user))
                (keys (strata.models.api-key:list-api-keys-for-user uid)))
           (api-ok (list :keys (mapcar #'serialize-api-key keys))))))))

  ;; POST /api/v1/me/keys
  (fluxion.server:add-route
   *router* :post "/api/v1/me/keys"
   (lambda (app session env &key params)
     (declare (ignore app session params))
     (block route
       (let ((user (authenticate-request env)))
         (unless user (return-from route (api-401)))
         (let* ((uid   (user-id-from-user user))
                (body  (fxapi:request-json-body env))
                (label (or (cdr (assoc :label body)) "default")))
           (multiple-value-bind (raw-token key)
               (strata.models.api-key:create-api-key uid :label label)
             (api-ok (serialize-api-key key raw-token))))))))

  ;; DELETE /api/v1/me/keys/:id
  (fluxion.server:add-route
   *router* :delete "/api/v1/me/keys/:id"
   (lambda (app session env &key params)
     (declare (ignore app session))
     (block route
       (let ((user (authenticate-request env)))
         (unless user (return-from route (api-401)))
         (let* ((uid    (user-id-from-user user))
                (key-id (handler-case
                            (parse-integer (or (cdr (assoc :id params)) ""))
                          (error () nil))))
           (unless key-id (return-from route (api-400 "Invalid key id")))
           (let ((key (fxdm:get-one "api_keys"
                                    (fluxion.db:compile-query
                                     `(:and (:= _id ,key-id)
                                            (:= user_id ,uid))))))
             (unless key (return-from route (api-404 "API key not found")))
             (strata.models.api-key:revoke-api-key key-id)
             (api-ok (list :status "ok" :revoked key-id))))))))

  ;; GET /api/v1/channels
  (fluxion.server:add-route
   *router* :get "/api/v1/channels"
   (lambda (app session env &key params)
     (declare (ignore app session params))
     (block route
       (let ((user (authenticate-request env)))
         (unless user (return-from route (api-401)))
         (let* ((uid        (user-id-from-user user))
                (member-ids (handler-case
                                (strata.models.channel-member:list-channels-for-user uid)
                              (error () nil)))
                (channels   (strata.models.channel:list-channels-for-user 1 uid member-ids)))
           (api-ok (list :channels (mapcar #'serialize-channel channels))))))))

  ;; GET /api/v1/channels/:slug
  (fluxion.server:add-route
   *router* :get "/api/v1/channels/:slug"
   (lambda (app session env &key params)
     (declare (ignore app session))
     (block route
       (let ((user (authenticate-request env)))
         (unless user (return-from route (api-401)))
         (let* ((slug (or (cdr (assoc :slug params)) ""))
                (ch   (strata.models.channel:find-channel-by-slug 1 slug)))
           (if ch
               (api-ok (serialize-channel ch))
               (api-404 "Channel not found")))))))

  ;; GET /api/v1/channels/:slug/posts
  (fluxion.server:add-route
   *router* :get "/api/v1/channels/:slug/posts"
   (lambda (app session env &key params)
     (declare (ignore app session))
     (block route
       (let ((user (authenticate-request env)))
         (unless user (return-from route (api-401)))
         (let* ((slug  (or (cdr (assoc :slug params)) ""))
                (ch    (strata.models.channel:find-channel-by-slug 1 slug)))
           (unless ch (return-from route (api-404 "Channel not found")))
           (let* ((ch-id (fxdm:model-id ch))
                  (qs    (fxapi:parse-query-params (getf env :query-string)))
                  (limit (or (parse-int-param qs "limit") 50))
                  (posts (strata.models.post:list-posts-for-channel
                          ch-id :limit (min limit 200))))
             (api-ok (list :posts (mapcar #'serialize-post posts)
                           :channel (serialize-channel ch)))))))))

  ;; POST /api/v1/channels/:slug/posts
  (fluxion.server:add-route
   *router* :post "/api/v1/channels/:slug/posts"
   (lambda (app session env &key params)
     (declare (ignore app session))
     (block route
       (let ((user (authenticate-request env)))
         (unless user (return-from route (api-401)))
         (let* ((slug (or (cdr (assoc :slug params)) ""))
                (ch   (strata.models.channel:find-channel-by-slug 1 slug)))
           (unless ch (return-from route (api-404 "Channel not found")))
           (let* ((body-data (fxapi:request-json-body env))
                  (body-text (or (cdr (assoc :body body-data)) ""))
                  (kind      (or (cdr (assoc :kind body-data)) "message"))
                  (uid       (user-id-from-user user))
                  (ch-id     (fxdm:model-id ch)))
             (when (zerop (length (string-trim '(#\Space #\Tab #\Newline) body-text)))
               (return-from route (api-400 "body is required")))
             (let ((post (strata.models.post:create-post
                          :channel-id ch-id
                          :author-id  uid
                          :kind       kind
                          :body       body-text)))
               (strata.models.channel:touch-channel ch-id)
               (api-ok (serialize-post post)))))))))

  ;; GET /api/v1/posts/:id
  (fluxion.server:add-route
   *router* :get "/api/v1/posts/:id"
   (lambda (app session env &key params)
     (declare (ignore app session))
     (block route
       (let ((user (authenticate-request env)))
         (unless user (return-from route (api-401)))
         (let* ((pid (handler-case (parse-integer (or (cdr (assoc :id params)) ""))
                       (error () nil))))
           (unless pid (return-from route (api-400 "Invalid post id")))
           (let ((post (strata.models.post:find-post-by-id pid)))
             (if post
                 (api-ok (serialize-post post))
                 (api-404 "Post not found"))))))))

  ;; GET /api/v1/posts/:id/replies
  (fluxion.server:add-route
   *router* :get "/api/v1/posts/:id/replies"
   (lambda (app session env &key params)
     (declare (ignore app session))
     (block route
       (let ((user (authenticate-request env)))
         (unless user (return-from route (api-401)))
         (let* ((pid (handler-case (parse-integer (or (cdr (assoc :id params)) ""))
                       (error () nil))))
           (unless pid (return-from route (api-400 "Invalid post id")))
           (let ((replies (strata.models.reply:list-replies-for-post pid)))
             (api-ok (list :replies (mapcar #'serialize-reply replies)))))))))

  ;; POST /api/v1/posts/:id/replies
  (fluxion.server:add-route
   *router* :post "/api/v1/posts/:id/replies"
   (lambda (app session env &key params)
     (declare (ignore app session))
     (block route
       (let ((user (authenticate-request env)))
         (unless user (return-from route (api-401)))
         (let* ((pid (handler-case (parse-integer (or (cdr (assoc :id params)) ""))
                       (error () nil))))
           (unless pid (return-from route (api-400 "Invalid post id")))
           (let* ((post (strata.models.post:find-post-by-id pid)))
             (unless post (return-from route (api-404 "Post not found")))
             (let* ((body-data (fxapi:request-json-body env))
                    (body-text (or (cdr (assoc :body body-data)) ""))
                    (uid       (user-id-from-user user)))
               (when (zerop (length (string-trim '(#\Space #\Tab #\Newline) body-text)))
                 (return-from route (api-400 "body is required")))
               (let ((reply (strata.models.reply:create-reply
                             :post-id   pid
                             :author-id uid
                             :body      body-text)))
                 (api-ok (serialize-reply reply))))))))))

  *router*)

(defun handle-api-request (env)
  "Dispatch ENV to the API router. Called from page-handler for /api/v1/* paths."
  (unless *router* (setup-routes))
  (fluxion.server:dispatch-route *router* nil nil env))
