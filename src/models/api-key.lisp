;;;; -*- encoding:utf-8 -*-
;;;; Strata - API key model
;;;;
;;;; API keys are Bearer tokens used for stateless REST API access.
;;;; Only the SHA-256 hex digest of the token is stored; the raw token
;;;; is returned once at creation time and never stored.

(in-package #:strata.models.api-key)

(defparameter +collection+ "api_keys")

(defun api-key-field (key field)
  "Return the value of FIELD in the api-key data-model KEY."
  (fxdm:model-field key field))

(defun %hash-token (token)
  "Return the SHA-256 hex digest of TOKEN string."
  (ironclad:byte-array-to-hex-string
   (ironclad:digest-sequence
    :sha256
    (ironclad:ascii-string-to-byte-array token))))

(defun generate-token ()
  "Return a cryptographically random 32-byte hex string (64 chars)."
  (ironclad:byte-array-to-hex-string (ironclad:random-data 32)))

(defun create-api-key (user-id &key (label "default"))
  "Create a new API key for USER-ID with optional LABEL.
Returns (values raw-token api-key-model).
The raw-token is only available at creation time."
  (let* ((token (generate-token))
         (hash  (%hash-token token))
         (k     (fxdm:hull +collection+)))
    (setf (fxdm:model-field k "user_id")    user-id
          (fxdm:model-field k "token_hash") hash
          (fxdm:model-field k "label")      (or label "default")
          (fxdm:model-field k "created_at") (get-universal-time)
          (fxdm:model-field k "last_used")  0)
    (fxdm:insert-model k)
    (values token k)))

(defun find-api-key-by-token (raw-token)
  "Look up an api-key record by RAW-TOKEN. Returns the model or NIL.
Also updates last_used timestamp on a hit."
  (let* ((hash (handler-case (%hash-token raw-token) (error () nil))))
    (when hash
      (let ((k (fxdm:get-one +collection+
                              (db:compile-query `(:= token_hash ,hash)))))
        (when k
          (setf (fxdm:model-field k "last_used") (get-universal-time))
          (handler-case (fxdm:save k) (error () nil))
          k)))))

(defun list-api-keys-for-user (user-id)
  "Return all api-key models for USER-ID, newest first."
  (fxdm:get-all +collection+
                (db:compile-query `(:= user_id ,user-id))
                :sort '(("created_at" . :desc))))

(defun find-api-key-by-id (key-id)
  "Return the api-key model with _id KEY-ID, or NIL."
  (fxdm:get-one +collection+
                (db:compile-query `(:= _id ,key-id))))

(defun revoke-api-key (key-id)
  "Delete the api-key record with _id KEY-ID."
  (db:delete-by-id +collection+ key-id))
