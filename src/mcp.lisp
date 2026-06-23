;;;; -*- encoding:utf-8 -*-
;;;; Strata - Model Context Protocol (MCP) server
;;;;
;;;; Implements MCP 2024-11-05 over HTTP POST /mcp.
;;;; Transport: HTTP+JSON (Streamable HTTP, single request/response).
;;;; Auth: same Bearer token as the REST API (strata.models.api-key).
;;;;
;;;; Supported methods:
;;;;   initialize
;;;;   tools/list
;;;;   tools/call
;;;;   resources/list
;;;;   resources/read
;;;;
;;;; Tools:
;;;;   list-channels     - list visible channels
;;;;   read-channel      - recent posts in a channel
;;;;   post-message      - create a post
;;;;   resolve-post      - mark a post resolved/done
;;;;
;;;; Resources:
;;;;   channel://<slug>  - channel feed as text

(in-package #:strata.mcp)

;;; -------------------------------------------------------
;;; Server info constants
;;; -------------------------------------------------------

(defparameter +server-name+    "strata")
(defparameter +server-version+ "0.1.0")
(defparameter +protocol-version+ "2024-11-05")

;;; -------------------------------------------------------
;;; JSON-RPC helpers
;;; -------------------------------------------------------

(defun jsonrpc-ok (id result)
  "Build a successful JSON-RPC response plist."
  (list :jsonrpc "2.0" :id id :result result))

(defun jsonrpc-error (id code message &optional data)
  "Build an error JSON-RPC response plist."
  (let ((err (list :code code :message message)))
    (when data (setf err (append err (list :data data))))
    (list :jsonrpc "2.0" :id id :error err)))

(defun json-response (plist &optional (status 200))
  "Return a Clack response with JSON body."
  (list status
        '(:content-type "application/json; charset=utf-8")
        (list (fxapi:encode-json plist))))

;;; -------------------------------------------------------
;;; Auth
;;; -------------------------------------------------------

(defun bearer-token (env)
  "Extract raw token from Authorization: Bearer <token>, or NIL."
  (let ((auth (gethash "authorization" (getf env :headers))))
    (when (and auth (> (length auth) 7)
               (string-equal "bearer " (subseq auth 0 7)))
      (string-trim '(#\Space #\Tab) (subseq auth 7)))))

(defun authenticate (env)
  "Return user alist for a valid Bearer token in ENV, or NIL."
  (let ((token (bearer-token env)))
    (when token
      (let ((key (strata.models.api-key:find-api-key-by-token token)))
        (when key
          (let ((uid (strata.models.api-key:api-key-field key "user_id")))
            (when uid (strata.auth:get-user-by-id uid))))))))

;;; -------------------------------------------------------
;;; Model serialization
;;; -------------------------------------------------------

(defun serialize-channel (ch)
  (list :slug        (strata.models.channel:channel-field ch "slug")
        :name        (strata.models.channel:channel-field ch "name")
        :description (or (strata.models.channel:channel-field ch "description") "")
        :kind        (or (strata.models.channel:channel-field ch "kind") "open")))

(defun serialize-post (post)
  (list :id         (fluxion.db.model:model-id post)
        :author_id  (strata.models.post:post-field post "author_id")
        :body       (strata.models.post:post-field post "body")
        :kind       (or (strata.models.post:post-field post "kind") "message")
        :status     (or (strata.models.post:post-field post "status") "open")
        :created_at (strata.models.post:post-field post "created_at")))

;;; -------------------------------------------------------
;;; MCP method handlers
;;; -------------------------------------------------------

(defun handle-initialize (id _params)
  "Respond to initialize with server capabilities."
  (declare (ignore _params))
  (jsonrpc-ok id
    (list :protocolVersion +protocol-version+
          :serverInfo (list :name +server-name+ :version +server-version+)
          :capabilities
          (list :tools     (list :listChanged nil)
                :resources (list :listChanged nil :subscribe nil)))))

(defun handle-tools-list (id _params)
  "Return the list of available tools."
  (declare (ignore _params))
  (jsonrpc-ok id
    (list :tools
      (list
        (list :name "list-channels"
              :description "List all channels visible to the caller."
              :inputSchema
              (list :type "object" :properties (list) :required (list)))
        (list :name "read-channel"
              :description "Return recent posts from a channel."
              :inputSchema
              (list :type "object"
                    :properties
                    (list :slug  (list :type "string"
                                       :description "Channel slug")
                          :limit (list :type "integer"
                                       :description "Max posts to return (default 20, max 100)"))
                    :required (list "slug")))
        (list :name "post-message"
              :description "Post a message to a channel."
              :inputSchema
              (list :type "object"
                    :properties
                    (list :channel (list :type "string"
                                         :description "Channel slug")
                          :body    (list :type "string"
                                         :description "Message body text")
                          :kind    (list :type "string"
                                         :description "Post kind: message, question, decision, announcement (default: message)"))
                    :required (list "channel" "body")))
        (list :name "resolve-post"
              :description "Mark a post as resolved."
              :inputSchema
              (list :type "object"
                    :properties
                    (list :id (list :type "integer"
                                    :description "Post ID to resolve"))
                    :required (list "id")))))))

(defun handle-resources-list (id _params)
  "Return the list of available resources."
  (declare (ignore _params))
  (let* ((channels (handler-case
                       (strata.models.channel:list-channels-for-workspace 1)
                     (error () nil))))
    (jsonrpc-ok id
      (list :resources
        (mapcar (lambda (ch)
                  (let ((slug (strata.models.channel:channel-field ch "slug"))
                        (name (strata.models.channel:channel-field ch "name")))
                    (list :uri         (format nil "channel://~A" slug)
                          :name        (format nil "#~A" name)
                          :description (format nil "Recent posts in #~A" name)
                          :mimeType    "text/plain")))
                channels)))))

(defun handle-resources-read (id params)
  "Read a channel feed resource by URI."
  (let* ((uri (cdr (assoc :uri params))))
    (unless (and uri (> (length uri) 10)
                 (string= "channel://" (subseq uri 0 10)))
      (return-from handle-resources-read
        (jsonrpc-error id -32602 "Invalid params" "uri must be channel://<slug>")))
    (let* ((slug (subseq uri 10))
           (ch   (handler-case
                     (strata.models.channel:find-channel-by-slug 1 slug)
                   (error () nil))))
      (unless ch
        (return-from handle-resources-read
          (jsonrpc-error id -32602 "Invalid params"
                         (format nil "Channel not found: ~A" slug))))
      (let* ((ch-id (fluxion.db.model:model-id ch))
             (posts (handler-case
                        (strata.models.post:list-posts-for-channel ch-id :limit 20)
                      (error () nil)))
             (text  (with-output-to-string (s)
                      (format s "# ~A~%~%"
                              (strata.models.channel:channel-field ch "name"))
                      (dolist (p posts)
                        (format s "[~A] ~A~%~%"
                                (strata.models.post:post-field p "created_at")
                                (strata.models.post:post-field p "body"))))))
        (jsonrpc-ok id
          (list :contents
            (list (list :uri      (format nil "channel://~A" slug)
                        :mimeType "text/plain"
                        :text     text))))))))

;;; -------------------------------------------------------
;;; Tool call dispatch
;;; -------------------------------------------------------

(defun call-list-channels (_args user)
  "Tool: list-channels."
  (declare (ignore _args))
  (let* ((uid (fluxion.user:user-id user))
         (member-ids (handler-case
                         (strata.models.channel-member:list-channels-for-user uid)
                       (error () nil)))
         (channels (strata.models.channel:list-channels-for-user 1 uid member-ids)))
    (list :content
      (list (list :type "text"
                  :text (fxapi:encode-json
                          (list :channels (mapcar #'serialize-channel channels))))))))

(defun call-read-channel (args _user)
  "Tool: read-channel."
  (declare (ignore _user))
  (let* ((slug  (cdr (assoc :slug args)))
         (limit (or (cdr (assoc :limit args)) 20)))
    (unless slug
      (return-from call-read-channel
        (list :isError t :content (list (list :type "text" :text "slug is required")))))
    (let ((ch (handler-case
                   (strata.models.channel:find-channel-by-slug 1 slug)
                 (error () nil))))
      (unless ch
        (return-from call-read-channel
          (list :isError t :content
                (list (list :type "text"
                            :text (format nil "Channel not found: ~A" slug))))))
      (let* ((ch-id (fluxion.db.model:model-id ch))
             (posts (handler-case
                        (strata.models.post:list-posts-for-channel
                         ch-id :limit (min (or limit 20) 100))
                      (error () nil))))
        (list :content
          (list (list :type "text"
                      :text (fxapi:encode-json
                              (list :channel (serialize-channel ch)
                                    :posts   (mapcar #'serialize-post posts))))))))))

(defun call-post-message (args user)
  "Tool: post-message."
  (let* ((slug      (cdr (assoc :channel args)))
         (body-text (cdr (assoc :body args)))
         (kind      (or (cdr (assoc :kind args)) "message")))
    (unless (and slug body-text)
      (return-from call-post-message
        (list :isError t :content
              (list (list :type "text" :text "channel and body are required")))))
    (let ((ch (handler-case
                   (strata.models.channel:find-channel-by-slug 1 slug)
                 (error () nil))))
      (unless ch
        (return-from call-post-message
          (list :isError t :content
                (list (list :type "text"
                            :text (format nil "Channel not found: ~A" slug))))))
      (let* ((uid   (fluxion.user:user-id user))
             (ch-id (fluxion.db.model:model-id ch))
             (post  (handler-bind
                        ((fluxion.hooks:hook-not-found #'continue))
                      (strata.models.post:create-post
                       :channel-id ch-id
                       :author-id  uid
                       :kind       kind
                       :body       body-text))))
        (strata.models.channel:touch-channel ch-id)
        (list :content
          (list (list :type "text"
                      :text (fxapi:encode-json (serialize-post post)))))))))

(defun call-resolve-post (args _user)
  "Tool: resolve-post."
  (declare (ignore _user))
  (let* ((pid (cdr (assoc :id args))))
    (unless pid
      (return-from call-resolve-post
        (list :isError t :content
              (list (list :type "text" :text "id is required")))))
    (let ((post (handler-case (strata.models.post:find-post-by-id pid)
                  (error () nil))))
      (unless post
        (return-from call-resolve-post
          (list :isError t :content
                (list (list :type "text"
                            :text (format nil "Post not found: ~A" pid))))))
      (strata.models.post:set-post-status pid "resolved")
      (list :content
        (list (list :type "text"
                    :text (format nil "Post ~A marked resolved." pid)))))))

(defun handle-tools-call (id params user)
  "Dispatch a tools/call request."
  (let* ((name (cdr (assoc :name params)))
         (args (or (cdr (assoc :arguments params)) nil))
         (result
          (handler-case
              (cond
                ((string= name "list-channels") (call-list-channels args user))
                ((string= name "read-channel")  (call-read-channel  args user))
                ((string= name "post-message")  (call-post-message  args user))
                ((string= name "resolve-post")  (call-resolve-post  args user))
                (t (return-from handle-tools-call
                     (jsonrpc-error id -32601 "Method not found"
                                    (format nil "Unknown tool: ~A" name)))))
            (error (e)
              (list :isError t
                    :content (list (list :type "text"
                                         :text (format nil "Error: ~A" e))))))))
    (jsonrpc-ok id result)))

;;; -------------------------------------------------------
;;; Main dispatcher
;;; -------------------------------------------------------

(defun handle-mcp-request (env)
  "Handle a POST /mcp request. Returns a Clack response."
  (let* ((user  (authenticate env))
         (body  (fxapi:request-json-body env))
         (id    (cdr (assoc :id     body)))
         (method (cdr (assoc :method body)))
         (params (or (cdr (assoc :params body)) nil)))
    (unless body
      (return-from handle-mcp-request
        (json-response (jsonrpc-error nil -32700 "Parse error") 400)))
    (unless method
      (return-from handle-mcp-request
        (json-response (jsonrpc-error id -32600 "Invalid Request") 400)))
    (let ((response
           (cond
             ((string= method "initialize")
              (handle-initialize id params))

             ((string= method "notifications/initialized")
              nil)

             ((string= method "tools/list")
              (unless user
                (return-from handle-mcp-request
                  (json-response (jsonrpc-error id -32000 "Unauthorized") 401)))
              (handle-tools-list id params))

             ((string= method "tools/call")
              (unless user
                (return-from handle-mcp-request
                  (json-response (jsonrpc-error id -32000 "Unauthorized") 401)))
              (handle-tools-call id params user))

             ((string= method "resources/list")
              (unless user
                (return-from handle-mcp-request
                  (json-response (jsonrpc-error id -32000 "Unauthorized") 401)))
              (handle-resources-list id params))

             ((string= method "resources/read")
              (unless user
                (return-from handle-mcp-request
                  (json-response (jsonrpc-error id -32000 "Unauthorized") 401)))
              (handle-resources-read id params))

             (t
              (jsonrpc-error id -32601 "Method not found")))))
      (if response
          (json-response response)
          (list 204 '(:content-type "application/json") '(""))))))
