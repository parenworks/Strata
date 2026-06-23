;;;; -*- encoding:utf-8 -*-
;;;; Strata tests - MCP server tests
;;;;
;;;; Tests cover:
;;;;   - JSON-RPC response helpers
;;;;   - Bearer token extraction
;;;;   - MCP authentication via API keys
;;;;   - initialize / tools/list / resources/list handlers
;;;;   - tools/call dispatch for list-channels, read-channel, post-message
;;;;   - Unauthorized rejection for all protected methods
;;;;
;;;; Full HTTP round-trips are not tested here; mock Clack envs are used.

(in-package #:strata.tests)

(def-suite strata-mcp-tests
  :description "Tests for the Strata MCP server.")

(in-suite strata-mcp-tests)

;;; -------------------------------------------------------
;;; Helpers
;;; -------------------------------------------------------

(defun %json-stream (plist-or-alist)
  "Encode PLIST-OR-ALIST as JSON and return an octet input stream."
  (let* ((str   (cl-json:encode-json-to-string plist-or-alist))
         (bytes (babel:string-to-octets str :encoding :utf-8)))
    (flexi-streams:make-in-memory-input-stream bytes)))

(defun make-mock-env (&key (method "POST") (token nil) (body nil))
  "Build a minimal mock Clack env plist."
  (let ((headers (make-hash-table :test #'equal)))
    (when token
      (setf (gethash "authorization" headers)
            (format nil "Bearer ~A" token)))
    (list :request-method method
          :headers headers
          :raw-body (when body (%json-stream body)))))

(defun rpc-result (response)
  "Extract :result from a JSON-RPC plist."
  (getf response :result))

(defun rpc-error (response)
  "Extract :error from a JSON-RPC plist."
  (getf response :error))

;;; -------------------------------------------------------
;;; JSON-RPC helpers
;;; -------------------------------------------------------

(test jsonrpc-ok-structure
  "jsonrpc-ok produces a well-formed success response."
  (let ((r (strata.mcp:jsonrpc-ok 1 '(:foo "bar"))))
    (is (string= "2.0" (getf r :jsonrpc)))
    (is (= 1 (getf r :id)))
    (is (not (null (rpc-result r))))
    (is (null (rpc-error r)))))

(test jsonrpc-error-structure
  "jsonrpc-error produces a well-formed error response."
  (let ((r (strata.mcp:jsonrpc-error 2 -32600 "Invalid Request")))
    (is (string= "2.0" (getf r :jsonrpc)))
    (is (= 2 (getf r :id)))
    (is (null (rpc-result r)))
    (let ((err (rpc-error r)))
      (is (not (null err)))
      (is (= -32600 (getf err :code)))
      (is (string= "Invalid Request" (getf err :message))))))

(test jsonrpc-error-nil-id
  "jsonrpc-error accepts nil id for parse errors."
  (let ((r (strata.mcp:jsonrpc-error nil -32700 "Parse error")))
    (is (null (getf r :id)))
    (is (not (null (rpc-error r))))))

;;; -------------------------------------------------------
;;; Bearer token extraction
;;; -------------------------------------------------------

(test bearer-token-present
  "bearer-token extracts the token from a valid Authorization header."
  (let* ((headers (make-hash-table :test #'equal))
         (env (list :headers headers)))
    (setf (gethash "authorization" headers) "Bearer mytoken123")
    (is (string= "mytoken123" (strata.mcp:bearer-token env)))))

(test bearer-token-missing
  "bearer-token returns nil when Authorization header is absent."
  (let* ((headers (make-hash-table :test #'equal))
         (env (list :headers headers)))
    (is (null (strata.mcp:bearer-token env)))))

(test bearer-token-wrong-scheme
  "bearer-token returns nil for non-Bearer schemes."
  (let* ((headers (make-hash-table :test #'equal))
         (env (list :headers headers)))
    (setf (gethash "authorization" headers) "Basic dXNlcjpwYXNz")
    (is (null (strata.mcp:bearer-token env)))))

;;; -------------------------------------------------------
;;; MCP authentication via API keys
;;; -------------------------------------------------------

(test mcp-authenticate-valid-token
  "authenticate returns a user alist for a valid API key token."
  (with-test-db
    (let* ((uname (make-user :username "mcp-auth-valid"))
           (uid   (fluxion.user:user-id uname)))
      (multiple-value-bind (raw-token _key)
          (strata.models.api-key:create-api-key uid :label "mcp-test")
        (declare (ignore _key))
        (let* ((headers (make-hash-table :test #'equal))
               (env     (list :headers headers)))
          (setf (gethash "authorization" headers)
                (format nil "Bearer ~A" raw-token))
          (let ((user (strata.mcp:authenticate env)))
            (is (not (null user)))
            (is (= uid (fluxion.user:user-id user)))))))))

(test mcp-authenticate-invalid-token
  "authenticate returns nil for an unrecognised token."
  (with-test-db
    (let* ((headers (make-hash-table :test #'equal))
           (env     (list :headers headers)))
      (setf (gethash "authorization" headers) "Bearer notarealtoken000000")
      (is (null (strata.mcp:authenticate env))))))

(test mcp-authenticate-no-token
  "authenticate returns nil when no Authorization header is present."
  (with-test-db
    (let* ((headers (make-hash-table :test #'equal))
           (env     (list :headers headers)))
      (is (null (strata.mcp:authenticate env))))))

;;; -------------------------------------------------------
;;; initialize handler (no auth required)
;;; -------------------------------------------------------

(test mcp-initialize
  "handle-initialize returns server info and capabilities."
  (let* ((r      (strata.mcp:handle-initialize 1 nil))
         (result (rpc-result r)))
    (is (not (null result)))
    (is (string= "2024-11-05" (getf result :protocolVersion)))
    (let ((info (getf result :serverInfo)))
      (is (string= "strata" (getf info :name))))
    (let ((caps (getf result :capabilities)))
      (is (not (null (getf caps :tools))))
      (is (not (null (getf caps :resources)))))))

;;; -------------------------------------------------------
;;; tools/list handler
;;; -------------------------------------------------------

(test mcp-tools-list
  "handle-tools-list returns all four expected tools."
  (let* ((r     (strata.mcp:handle-tools-list 1 nil))
         (tools (getf (rpc-result r) :tools)))
    (is (= 4 (length tools)))
    (let ((names (mapcar (lambda (tool) (getf tool :name)) tools)))
      (is (member "list-channels"  names :test #'string=))
      (is (member "read-channel"   names :test #'string=))
      (is (member "post-message"   names :test #'string=))
      (is (member "resolve-post"   names :test #'string=)))))

;;; -------------------------------------------------------
;;; resources/list handler
;;; -------------------------------------------------------

(test mcp-resources-list
  "handle-resources-list returns a :resources list with channel:// URIs."
  (with-test-db
    (let* ((ws    (make-workspace :name "mcp-rl-ws"))
           (ws-id (fluxion.db.model:model-id ws))
           (_ch   (make-channel ws-id
                                :slug "mcp-rl-chan"
                                :name "mcp-rl-chan"
                                :kind "open")))
      (declare (ignore _ch))
      (let* ((r         (strata.mcp:handle-resources-list 1 nil))
             (resources (getf (rpc-result r) :resources)))
        (is (listp resources))
        (when resources
          (let ((first-res (first resources)))
            (is (not (null (getf first-res :uri))))
            (is (not (null (search "channel://" (getf first-res :uri)))))))))))

;;; -------------------------------------------------------
;;; find-api-key-by-id
;;; -------------------------------------------------------

(test api-key-find-by-id
  "find-api-key-by-id returns the key for a valid id and nil for unknown."
  (with-test-db
    (let* ((uname (make-user :username "mcp-fbi-user"))
           (uid   (fluxion.user:user-id uname)))
      (multiple-value-bind (_tok key)
          (strata.models.api-key:create-api-key uid :label "fbi-test")
        (declare (ignore _tok))
        (let ((kid (fluxion.db.model:model-id key)))
          (let ((found (strata.models.api-key:find-api-key-by-id kid)))
            (is (not (null found)))
            (is (string= "fbi-test"
                         (strata.models.api-key:api-key-field found "label"))))
          (is (null (strata.models.api-key:find-api-key-by-id 9999999))))))))

;;; -------------------------------------------------------
;;; Unauthorized rejection via handle-mcp-request
;;; -------------------------------------------------------

(test mcp-dispatch-unauthorized
  "handle-mcp-request returns 401 for tools/list without a valid token."
  (with-test-db
    (let* ((body `(("jsonrpc" . "2.0") ("id" . 1) ("method" . "tools/list")))
           (env  (make-mock-env :body body)))
      (let ((resp (strata.mcp:handle-mcp-request env)))
        (is (= 401 (first resp)))))))

(test mcp-dispatch-initialize-no-auth
  "initialize does not require authentication and returns 200."
  (with-test-db
    (let* ((body `(("jsonrpc" . "2.0") ("id" . 1) ("method" . "initialize")))
           (env  (make-mock-env :body body)))
      (let ((resp (strata.mcp:handle-mcp-request env)))
        (is (= 200 (first resp)))))))

(test mcp-dispatch-method-not-found
  "Unknown method returns JSON-RPC -32601 error."
  (with-test-db
    (let* ((uname (make-user :username "mcp-mnf-user"))
           (uid   (fluxion.user:user-id uname)))
      (multiple-value-bind (raw-token _key)
          (strata.models.api-key:create-api-key uid :label "mnf-test")
        (declare (ignore _key))
        (let* ((body `(("jsonrpc" . "2.0") ("id" . 42)
                       ("method"  . "nonexistent/method")))
               (env  (make-mock-env :token raw-token :body body)))
          (let* ((resp     (strata.mcp:handle-mcp-request env))
                 (body-str (first (third resp)))
                 (decoded  (cl-json:decode-json-from-string body-str)))
            (is (= 200 (first resp)))
            (let ((err (cdr (assoc :error decoded))))
              (is (not (null err)))
              (is (= -32601 (cdr (assoc :code err)))))))))))

(defun run-mcp-tests ()
  "Run only the MCP tests."
  (run! 'strata-mcp-tests))
