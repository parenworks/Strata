;;;; -*- encoding:utf-8 -*-
;;;; Strata - Post edit history model
;;;;
;;;; Each row records the body text that existed before an edit.
;;;; The current body always lives on the posts table; post_edits
;;;; stores the previous versions in chronological order.

(in-package #:strata.models.post-edit)

(defparameter +collection+ "post_edits")

(defun post-edit-field (edit field)
  "Return the value of FIELD in the post-edit data-model object."
  (fxdm:model-field edit field))

(defun record-edit (post-id editor-id old-body)
  "Save the pre-edit body of POST-ID as a history row.
EDITOR-ID is the user who made the change.
OLD-BODY is the body text that is being replaced."
  (let ((e (fxdm:hull +collection+)))
    (setf (fxdm:model-field e "post_id")   post-id
          (fxdm:model-field e "editor_id") editor-id
          (fxdm:model-field e "body")      old-body
          (fxdm:model-field e "edited_at") (get-universal-time))
    (fxdm:insert-model e)
    e))

(defun list-edits-for-post (post-id)
  "Return all edit-history rows for POST-ID, newest first."
  (fxdm:get-all +collection+
                (db:compile-query `(:= post_id ,post-id))
                :sort '(("edited_at" . :desc))))
