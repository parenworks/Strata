;;;; -*- encoding:utf-8 -*-
;;;; Strata - Push subscription model

(in-package #:strata.models.push-subscription)

(defparameter +collection+ "push_subscriptions")

(defun subscription-field (sub field)
  "Return the value of FIELD from a PUSH-SUBSCRIPTIONS data-model object."
  (fxdm:model-field sub field))

(defun save-subscription (user-id endpoint p256dh auth-key)
  "Persist a Web Push subscription for USER-ID.
ENDPOINT is the push service URL from the browser PushSubscription object.
P256DH is the base64url-encoded client public key.
AUTH-KEY is the base64url-encoded auth secret.
Replaces any existing subscription with the same endpoint."
  (let ((existing (find-by-endpoint endpoint)))
    (if existing
        (progn
          (setf (fxdm:model-field existing "user_id")    user-id
                (fxdm:model-field existing "p256dh")     p256dh
                (fxdm:model-field existing "auth_key")   auth-key)
          (fxdm:save existing)
          existing)
        (let ((s (fxdm:hull +collection+)))
          (setf (fxdm:model-field s "user_id")    user-id
                (fxdm:model-field s "endpoint")   endpoint
                (fxdm:model-field s "p256dh")     p256dh
                (fxdm:model-field s "auth_key")   auth-key
                (fxdm:model-field s "created_at") (get-universal-time))
          (fxdm:insert-model s)
          s))))

(defun find-by-endpoint (endpoint)
  "Return the subscription record matching ENDPOINT, or NIL."
  (fxdm:get-one +collection+
                (db:compile-query `(:= endpoint ,endpoint))))

(defun list-for-user (user-id)
  "Return all push subscription records for USER-ID."
  (fxdm:get-all +collection+
                (db:compile-query `(:= user_id ,user-id))))

(defun delete-subscription (endpoint)
  "Remove the push subscription with ENDPOINT."
  (db:remove +collection+
             (db:compile-query `(:= endpoint ,endpoint))))
