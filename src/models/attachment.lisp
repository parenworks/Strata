;;;; -*- encoding:utf-8 -*-
;;;; Strata - Attachment model
;;;;
;;;; Attachments are files uploaded by users and linked to a post or reply.
;;;; Each attachment is stored on disk under *upload-dir* using a UUID-based
;;;; path so filenames cannot collide or be guessed.
;;;;
;;;; Directory layout: <*upload-dir*>/<uuid>/<original-filename>
;;;; Download URL:     /uploads/<uuid>/<original-filename>

(in-package #:strata.models.attachment)

(defparameter +collection+ "attachments")

(defparameter *upload-dir*
  (asdf:system-relative-pathname :strata "uploads/")
  "Root directory where uploaded files are stored.
Override before starting the server if a different path is required.")

(defun attachment-field (attachment field)
  "Return the value of FIELD in the ATTACHMENT data-model object."
  (fxdm:model-field attachment field))

(defun %make-uuid ()
  "Generate a random UUID-like string suitable for directory naming."
  (format nil "~(~8,'0X~)-~(~4,'0X~)-~(~4,'0X~)-~(~4,'0X~)-~(~12,'0X~)"
          (random #xFFFFFFFF)
          (random #xFFFF)
          (logior #x4000 (random #x0FFF))
          (logior #x8000 (random #x3FFF))
          (random #xFFFFFFFFFFFF)))

(defun %sanitise-filename (name)
  "Strip path components and replace unsafe characters in NAME."
  (let ((base (file-namestring (pathname name))))
    (cl-ppcre:regex-replace-all "[^A-Za-z0-9._-]" base "_")))

(defun create-attachment (&key post-id reply-id uploader-id filename
                               content-type size-bytes file-data)
  "Persist an attachment record and write FILE-DATA (a byte vector) to disk.
Exactly one of POST-ID or REPLY-ID must be non-nil.
Returns the saved data-model."
  (let* ((uuid       (%make-uuid))
         (safe-name  (%sanitise-filename filename))
         (dir        (merge-pathnames (format nil "~A/" uuid) *upload-dir*))
         (path       (merge-pathnames safe-name dir)))
    (ensure-directories-exist dir)
    (with-open-file (out path
                         :direction         :output
                         :element-type      '(unsigned-byte 8)
                         :if-does-not-exist :create
                         :if-exists         :supersede)
      (write-sequence file-data out))
    (let ((a (fxdm:hull +collection+)))
      (setf (fxdm:model-field a "uuid")         uuid
            (fxdm:model-field a "post_id")       post-id
            (fxdm:model-field a "reply_id")      reply-id
            (fxdm:model-field a "uploader_id")   uploader-id
            (fxdm:model-field a "filename")      safe-name
            (fxdm:model-field a "content_type")  (or content-type "application/octet-stream")
            (fxdm:model-field a "size_bytes")    size-bytes
            (fxdm:model-field a "created_at")    (get-universal-time))
      (fxdm:insert-model a)
      a)))

(defun find-attachment-by-uuid (uuid)
  "Return the attachment data-model with UUID, or NIL."
  (fxdm:get-one +collection+
                (db:compile-query `(:= uuid ,uuid))))

(defun list-attachments-for-post (post-id)
  "Return all attachments linked to POST-ID, ordered by created_at ascending."
  (fxdm:get-all +collection+
                (db:compile-query `(:= post_id ,post-id))
                :sort '(("created_at" . :asc))))

(defun list-attachments-for-reply (reply-id)
  "Return all attachments linked to REPLY-ID, ordered by created_at ascending."
  (fxdm:get-all +collection+
                (db:compile-query `(:= reply_id ,reply-id))
                :sort '(("created_at" . :asc))))

(defun delete-attachment (uuid)
  "Remove the attachment record and its file from disk.
Returns T if the record existed, NIL otherwise."
  (let ((a (find-attachment-by-uuid uuid)))
    (when a
      (let* ((safe-name (%sanitise-filename (attachment-field a "filename")))
             (dir  (merge-pathnames (format nil "~A/" uuid) *upload-dir*))
             (path (merge-pathnames safe-name dir)))
        (ignore-errors (delete-file path))
        (ignore-errors (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore)))
      (db:remove +collection+
                 (db:compile-query `(:= uuid ,uuid)))
      t)))
