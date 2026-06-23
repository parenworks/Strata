;;;; -*- encoding:utf-8 -*-
;;;; Strata - Channel model

(in-package #:strata.models.channel)

(defparameter +collection+ "channels")

(defun channel-field (channel field)
  "Return the value of FIELD in the CHANNEL data-model object.
FIELD is a column name string (e.g. \"name\", \"kind\", \"last_activity\")."
  (fxdm:model-field channel field))

(defun create-channel (&key workspace-id slug name description (kind "open") parent-channel-id)
  "Create and persist a new channel record. Returns the saved data-model.
WORKSPACE-ID is the _id of the owning workspace.
SLUG is a URL-safe identifier unique within the workspace.
NAME is the display name shown in the channel list.
DESCRIPTION is optional freetext; defaults to an empty string.
KIND is \"open\" (default), \"private\", or \"dm\".
Initial visibility is \"private\"; last_activity is set to now."
  (let ((c (fxdm:hull +collection+)))
    (setf (fxdm:model-field c "workspace_id")      workspace-id
          (fxdm:model-field c "slug")               slug
          (fxdm:model-field c "name")               name
          (fxdm:model-field c "description")        (or description "")
          (fxdm:model-field c "kind")               kind
          (fxdm:model-field c "visibility")         "private"
          (fxdm:model-field c "last_activity")      (get-universal-time)
          (fxdm:model-field c "created_at")         (get-universal-time)
          (fxdm:model-field c "parent_channel_id")  parent-channel-id)
    (fxdm:insert-model c)
    c))

(defun find-channel-by-id (id)
  "Return the channel data-model whose _id equals the integer ID, or NIL."
  (fxdm:get-one +collection+
                (db:compile-query `(:= _id ,id))))

(defun find-channel-by-slug (workspace-id slug)
  "Return the channel data-model with SLUG in workspace WORKSPACE-ID, or NIL.
Slugs are unique per workspace, not globally."
  (fxdm:get-one +collection+
                (db:compile-query `(:and (:= workspace_id ,workspace-id)
                                         (:= slug ,slug)))))

(defun list-channels-for-workspace (workspace-id)
  "Return top-level channels in WORKSPACE-ID ordered by last_activity descending.
Only returns channels with no parent (parent_channel_id IS NULL), so sub-channels
are not shown at the top level. Use list-subchannels to get children."
  (fxdm:get-all +collection+
                (db:compile-query `(:and (:= workspace_id ,workspace-id)
                                         (:= parent_channel_id nil)))
                :sort '(("last_activity" . :desc))))

(defun list-channels-for-user (workspace-id user-id member-channel-ids)
  "Return channels visible to USER-ID in WORKSPACE-ID.
Open channels are always included. Private channels are included only
if their _id appears in MEMBER-CHANNEL-IDS (a list of integers).
Only top-level channels are returned; use list-subchannels for children."
  (let ((all (fxdm:get-all +collection+
                            (db:compile-query
                             `(:and (:= workspace_id ,workspace-id)
                                    (:= parent_channel_id nil)))
                            :sort '(("last_activity" . :desc)))))
    (remove-if (lambda (ch)
                 (and (string= (channel-field ch "kind") "private")
                      (not (member (fxdm:model-id ch) member-channel-ids))))
               all)))

(defun list-subchannels (parent-channel-id)
  "Return all direct child channels of PARENT-CHANNEL-ID, ordered by name."
  (fxdm:get-all +collection+
                (db:compile-query `(:= parent_channel_id ,parent-channel-id))
                :sort '(("name" . :asc))))

(defun update-channel (channel-id &key name description)
  "Update the NAME and/or DESCRIPTION of CHANNEL-ID.
Only supplied (non-nil) values are applied."
  (let ((c (find-channel-by-id channel-id)))
    (when c
      (when name
        (setf (fxdm:model-field c "name") name))
      (when description
        (setf (fxdm:model-field c "description") description))
      (fxdm:save c)
      c)))

(defun archive-channel (channel-id)
  "Set the visibility of CHANNEL-ID to \"archived\".
Archived channels are excluded from the sidebar but not deleted."
  (let ((c (find-channel-by-id channel-id)))
    (when c
      (setf (fxdm:model-field c "visibility") "archived")
      (fxdm:save c)
      c)))

(defun unarchive-channel (channel-id)
  "Restore an archived channel by setting its visibility back to \"private\"."
  (let ((c (find-channel-by-id channel-id)))
    (when c
      (setf (fxdm:model-field c "visibility") "private")
      (fxdm:save c)
      c)))

(defun touch-channel (channel-id)
  "Set last_activity on CHANNEL-ID to the current universal time and persist it.
Call this whenever a post is created or replied to in the channel so the
channel sidebar ordering stays fresh."
  (let ((c (find-channel-by-id channel-id)))
    (when c
      (setf (fxdm:model-field c "last_activity") (get-universal-time))
      (fxdm:save c))))
