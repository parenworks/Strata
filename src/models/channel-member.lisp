;;;; -*- encoding:utf-8 -*-
;;;; Strata - Channel membership model

(in-package #:strata.models.channel-member)

(defparameter +collection+ "channel_members")

(defun member-field (member-record field)
  "Return the value of FIELD from a CHANNEL-MEMBERS data-model object."
  (fxdm:model-field member-record field))

(defun add-member (channel-id user-id &key (role "member"))
  "Add USER-ID to CHANNEL-ID with ROLE (default \"member\").
Role may be \"member\" or \"admin\". Duplicate entries are not checked here;
callers should verify membership first with member-p."
  (let ((m (fxdm:hull +collection+)))
    (setf (fxdm:model-field m "channel_id") channel-id
          (fxdm:model-field m "user_id")    user-id
          (fxdm:model-field m "role")       role
          (fxdm:model-field m "joined_at")  (get-universal-time))
    (fxdm:insert-model m)
    m))

(defun remove-member (channel-id user-id)
  "Remove USER-ID from CHANNEL-ID. No-op if not a member."
  (db:remove +collection+
             (db:compile-query `(:and (:= channel_id ,channel-id)
                                      (:= user_id    ,user-id)))))

(defun member-p (channel-id user-id)
  "Return T if USER-ID is a member of CHANNEL-ID, NIL otherwise."
  (not (null (fxdm:get-one +collection+
                            (db:compile-query `(:and (:= channel_id ,channel-id)
                                                     (:= user_id    ,user-id)))))))

(defun list-members (channel-id)
  "Return all membership records for CHANNEL-ID, ordered by joined_at ascending."
  (fxdm:get-all +collection+
                (db:compile-query `(:= channel_id ,channel-id))
                :sort '(("joined_at" . :asc))))

(defun list-channels-for-user (user-id)
  "Return all channel_id integers that USER-ID is explicitly a member of."
  (mapcar (lambda (m) (member-field m "channel_id"))
          (fxdm:get-all +collection+
                        (db:compile-query `(:= user_id ,user-id)))))
