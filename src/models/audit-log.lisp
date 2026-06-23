;;;; -*- encoding:utf-8 -*-
;;;; Strata - Audit log model
;;;;
;;;; Records administrative actions for accountability and debugging.
;;;; Written by the admin component actions and any code that modifies
;;;; users, channels, or workspaces in a privileged context.

(in-package #:strata.models.audit-log)

(defparameter +collection+ "audit_log")

(defun audit-log-field (entry field)
  "Return the value of FIELD in the audit-log ENTRY data-model."
  (fxdm:model-field entry field))

(defun record-event (actor-id action &key (target-type "") (target-id 0) (detail ""))
  "Append an audit log entry and return the saved data-model.
ACTOR-ID is the user _id performing the action.
ACTION is a short keyword-style string, e.g. \"user.invite\", \"user.disable\".
TARGET-TYPE is the kind of object affected (\"user\", \"channel\", \"workspace\").
TARGET-ID is the _id of the affected object (0 if not applicable).
DETAIL is a freetext description appended for context."
  (let ((e (fxdm:hull +collection+)))
    (setf (fxdm:model-field e "actor_id")    actor-id
          (fxdm:model-field e "action")      action
          (fxdm:model-field e "target_type") target-type
          (fxdm:model-field e "target_id")   target-id
          (fxdm:model-field e "detail")      detail
          (fxdm:model-field e "created_at")  (get-universal-time))
    (fxdm:insert-model e)
    e))

(defun list-recent-events (&key (limit 100))
  "Return the most recent LIMIT audit log entries, newest first."
  (fxdm:get-all +collection+
                (db:compile-query :all)
                :sort  '(("created_at" . :desc))
                :limit limit))

(defun list-events-for-actor (actor-id &key (limit 50))
  "Return up to LIMIT audit log entries for ACTOR-ID, newest first."
  (fxdm:get-all +collection+
                (db:compile-query `(:= actor_id ,actor-id))
                :sort  '(("created_at" . :desc))
                :limit limit))
