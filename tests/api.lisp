;;;; -*- encoding:utf-8 -*-
;;;; Strata tests - REST API layer tests
;;;;
;;;; Tests cover the api-key model (create, lookup, revoke) and the
;;;; authenticate-request helper that underpins all /api/v1/ endpoints.
;;;; Full HTTP dispatch is not tested here; that would require a running
;;;; server. These unit tests exercise the auth path and model layer.

(in-package #:strata.tests)

(def-suite strata-api-tests
  :description "Tests for the Strata REST API layer.")

(in-suite strata-api-tests)

;;; -------------------------------------------------------
;;; API key model
;;; -------------------------------------------------------

(test api-key-create-and-find
  "create-api-key returns a raw token; find-api-key-by-token resolves it."
  (with-test-db
    (let ((uname (make-user :username "apitest-create")))
      (let ((uid (fluxion.user:user-id uname)))
        (multiple-value-bind (raw-token key)
            (strata.models.api-key:create-api-key uid :label "test-key")
          (is (stringp raw-token))
          (is (= 64 (length raw-token)))
          (is (not (null key)))
          (is (string= "test-key"
                       (strata.models.api-key:api-key-field key "label")))
          (let ((found (strata.models.api-key:find-api-key-by-token raw-token)))
            (is (not (null found)))
            (is (= uid (strata.models.api-key:api-key-field found "user_id")))))))))

(test api-key-wrong-token
  "find-api-key-by-token returns NIL for an unrecognised token."
  (with-test-db
    (is (null (strata.models.api-key:find-api-key-by-token
               "0000000000000000000000000000000000000000000000000000000000000000")))))

(test api-key-revoke
  "revoke-api-key makes the token unresolvable."
  (with-test-db
    (let ((uname (make-user :username "apitest-revoke")))
      (let ((uid (fluxion.user:user-id uname)))
        (multiple-value-bind (raw-token key)
            (strata.models.api-key:create-api-key uid :label "revoke-me")
          (let ((key-id (fluxion.db.model:model-id key)))
            (is (not (null (strata.models.api-key:find-api-key-by-token raw-token))))
            (strata.models.api-key:revoke-api-key key-id)
            (is (null (strata.models.api-key:find-api-key-by-token raw-token)))))))))

(test api-key-list-for-user
  "list-api-keys-for-user returns all keys for a user, none for others."
  (with-test-db
    (let* ((uname (make-user :username "apitest-list"))
           (uid   (fluxion.user:user-id uname)))
      (strata.models.api-key:create-api-key uid :label "key-a")
      (strata.models.api-key:create-api-key uid :label "key-b")
      (let ((keys (strata.models.api-key:list-api-keys-for-user uid)))
        (is (= 2 (length keys)))
        (is (null (strata.models.api-key:list-api-keys-for-user 999999)))))))


;;; -------------------------------------------------------
;;; authenticate-request helper
;;; -------------------------------------------------------

(defun %make-env (&optional token)
  "Build a minimal Clack env plist with an Authorization header."
  (let ((headers (make-hash-table :test #'equal)))
    (when token
      (setf (gethash "authorization" headers)
            (format nil "Bearer ~A" token)))
    (list :headers       headers
          :path-info     "/api/v1/me"
          :request-method "GET"
          :query-string  "")))

(test authenticate-request-no-token
  "authenticate-request returns NIL when no Authorization header is present."
  (with-test-db
    (is (null (strata.api:authenticate-request (%make-env))))))

(test authenticate-request-bad-token
  "authenticate-request returns NIL for an unrecognised token."
  (with-test-db
    (is (null (strata.api:authenticate-request
               (%make-env "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"))))))

(test authenticate-request-valid-token
  "authenticate-request returns a user alist for a valid token."
  (with-test-db
    (let* ((uname (make-user :username "apitest-auth"))
           (uid   (fluxion.user:user-id uname)))
      (multiple-value-bind (raw-token _key)
          (strata.models.api-key:create-api-key uid :label "auth-test")
        (declare (ignore _key))
        (let ((user (strata.api:authenticate-request (%make-env raw-token))))
          (is (not (null user)))
          (is (string= uname (fluxion.user:user-username user))))))))

;;; -------------------------------------------------------
;;; Runner extension
;;; -------------------------------------------------------

(defun run-api-tests ()
  "Run only the API tests."
  (run! 'strata-api-tests))
