;;;; -*- encoding:utf-8 -*-
;;;; Strata - Channel read-receipt model

(in-package #:strata.models.channel-read)

(defparameter +collection+ "channel_reads")

(defun channel-read-field (record field)
  "Return the value of FIELD in the channel-read RECORD data-model.
FIELD is a column name string, e.g. \"last_read_post_id\", \"updated_at\"."
  (fxdm:model-field record field))

(defun mark-channel-read (&key user-id channel-id last-post-id)
  "Upsert the read receipt for USER-ID in CHANNEL-ID.
LAST-POST-ID is the _id of the most recent post the user has seen.
If a record already exists for the (user-id, channel-id) pair it is updated
in-place; otherwise a new record is inserted. updated_at is always set to now.
This drives the unread count badge in the channel sidebar."
  (let ((existing (get-channel-read user-id channel-id)))
    (if existing
        (progn
          (setf (fxdm:model-field existing "last_read_post_id") last-post-id
                (fxdm:model-field existing "updated_at")        (get-universal-time))
          (fxdm:save existing))
        (let ((r (fxdm:hull +collection+)))
          (setf (fxdm:model-field r "user_id")          user-id
                (fxdm:model-field r "channel_id")       channel-id
                (fxdm:model-field r "last_read_post_id") last-post-id
                (fxdm:model-field r "updated_at")        (get-universal-time))
          (fxdm:insert-model r)))))

(defun get-channel-read (user-id channel-id)
  "Return the channel-read data-model for USER-ID in CHANNEL-ID, or NIL.
Returns NIL if the user has never read the channel (treat as all-unread)."
  (fxdm:get-one +collection+
                (db:compile-query `(:and (:= user_id    ,user-id)
                                         (:= channel_id ,channel-id)))))
