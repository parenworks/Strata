;;;; -*- encoding:utf-8 -*-
;;;; Strata - Reaction model

(in-package #:strata.models.reaction)

(defparameter +collection+ "reactions")

(defun reaction-field (reaction field)
  "Return the value of FIELD in the REACTION data-model object.
FIELD is a column name string, e.g. \"emoji\", \"user_id\", \"target_type\"."
  (fxdm:model-field reaction field))

(defun add-reaction (&key target-type target-id user-id emoji)
  "Add an emoji reaction and return the saved data-model.
TARGET-TYPE must be \"post\" or \"reply\".
TARGET-ID is the _id of the target object.
USER-ID is the _id of the reacting user.
EMOJI is the emoji character string, e.g. \"👍\".
If TARGET-TYPE is \"post\", touch-post is called so the post resurfaces.
Does not deduplicate; callers should check for an existing reaction first."
  (let ((r (fxdm:hull +collection+)))
    (setf (fxdm:model-field r "target_type") target-type
          (fxdm:model-field r "target_id")   target-id
          (fxdm:model-field r "user_id")     user-id
          (fxdm:model-field r "emoji")       emoji
          (fxdm:model-field r "created_at")  (get-universal-time))
    (fxdm:insert-model r)
    (when (string= target-type "post")
      (strata.models.post:touch-post target-id))
    r))

(defun remove-reaction (&key target-type target-id user-id emoji)
  "Delete the matching reaction record. Calls touch-post if TARGET-TYPE is \"post\".
All four keyword arguments must match the stored record exactly."
  (db:remove +collection+
             (db:compile-query
              `(:and (:= target_type ,target-type)
                     (:= target_id   ,target-id)
                     (:= user_id     ,user-id)
                     (:= emoji       ,emoji))))
  (when (string= target-type "post")
    (strata.models.post:touch-post target-id)))

(defun list-reactions-for-target (target-type target-id)
  "Return all reaction data-models for TARGET-ID of TARGET-TYPE.
Ordered by emoji then created_at so grouped emoji counts are easy to compute."
  (fxdm:get-all +collection+
                (db:compile-query `(:and (:= target_type ,target-type)
                                         (:= target_id   ,target-id)))
                :sort '(("emoji" . :asc) ("created_at" . :asc))))
