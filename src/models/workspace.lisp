;;;; -*- encoding:utf-8 -*-
;;;; Strata - Workspace model

(in-package #:strata.models.workspace)

(defparameter +collection+ "workspaces")

(defun workspace-field (workspace field)
  "Return the value of FIELD in the WORKSPACE data-model object.
FIELD is a column name string (e.g. \"slug\", \"display_name\").
This is a thin accessor wrapper over fxdm:model-field."
  (fxdm:model-field workspace field))

(defun create-workspace (&key slug display-name)
  "Create and persist a new workspace record. Returns the saved data-model.
SLUG is a URL-safe identifier (e.g. \"acme-corp\").
DISPLAY-NAME is the human-readable title shown in the workspace rail.
Initial visibility is set to \"private\"; change it via a direct field update
if public workspaces are needed. The created_at field is set to the current
universal time."
  (let ((w (fxdm:hull +collection+)))
    (setf (fxdm:model-field w "slug")         slug
          (fxdm:model-field w "display_name") display-name
          (fxdm:model-field w "visibility")   "private"
          (fxdm:model-field w "created_at")   (get-universal-time))
    (fxdm:insert-model w)
    w))

(defun find-workspace-by-id (id)
  "Return the workspace data-model whose _id equals the integer ID, or NIL.
ID is the auto-incremented primary key assigned by the database on insert."
  (fxdm:get-one +collection+
                (db:compile-query `(:= _id ,id))))

(defun find-workspace-by-slug (slug)
  "Return the workspace data-model with the given SLUG string, or NIL.
Slugs are unique per installation and are used in URLs and config."
  (fxdm:get-one +collection+
                (db:compile-query `(:= slug ,slug))))

(defun update-workspace (workspace-id &key display-name)
  "Update the DISPLAY-NAME of WORKSPACE-ID.
Only supplied (non-nil) values are applied."
  (let ((w (find-workspace-by-id workspace-id)))
    (when w
      (when display-name
        (setf (fxdm:model-field w "display_name") display-name))
      (fxdm:save w)
      w)))

(defun list-workspaces ()
  "Return all workspace data-models, sorted alphabetically by display_name.
Used to populate the workspace rail in the shell UI."
  (fxdm:get-all +collection+
                (db:query :all)
                :sort '(("display_name" . :asc))))
