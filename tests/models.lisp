;;;; -*- encoding:utf-8 -*-
;;;; Strata tests - Model layer tests

(in-package #:strata.tests)

(def-suite strata-model-tests
  :description "Tests for the Strata model layer.")

(in-suite strata-model-tests)

;;; -------------------------------------------------------
;;; Workspace
;;; -------------------------------------------------------

(test workspace-create-and-find
  "create-workspace persists a record that find-workspace-by-slug retrieves."
  (with-test-db
    (let ((ws (make-workspace :slug "ws-test" :name "WS Test")))
      (is (not (null ws)))
      (let ((found (strata.models.workspace:find-workspace-by-slug "ws-test")))
        (is (not (null found)))
        (is (string= "WS Test"
                     (strata.models.workspace:workspace-field found "display_name")))))))

;;; -------------------------------------------------------
;;; Channel
;;; -------------------------------------------------------

(test channel-create-and-find
  "create-channel persists a record retrievable by find-channel-by-slug."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (ch    (make-channel ws-id :slug "ch-test" :name "Ch Test")))
      (is (not (null ch)))
      (let ((found (strata.models.channel:find-channel-by-slug ws-id "ch-test")))
        (is (not (null found)))
        (is (string= "Ch Test"
                     (strata.models.channel:channel-field found "name")))))))

(test channel-update
  "update-channel changes name and description."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (ch    (make-channel ws-id))
           (ch-id (fluxion.db.model:model-id ch)))
      (strata.models.channel:update-channel ch-id :name "Renamed" :description "Desc")
      (let ((found (strata.models.channel:find-channel-by-id ch-id)))
        (is (string= "Renamed"
                     (strata.models.channel:channel-field found "name")))
        (is (string= "Desc"
                     (strata.models.channel:channel-field found "description")))))))

(test channel-archive
  "archive-channel sets visibility to archived."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (ch    (make-channel ws-id))
           (ch-id (fluxion.db.model:model-id ch)))
      (strata.models.channel:archive-channel ch-id)
      (let ((found (strata.models.channel:find-channel-by-id ch-id)))
        (is (string= "archived"
                     (strata.models.channel:channel-field found "visibility")))))))

(test channel-private-membership-filter
  "list-channels-for-user excludes private channels the user is not a member of."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (_open (make-channel ws-id :slug "open-ch" :name "Open" :kind "open"))
           (priv  (make-channel ws-id :slug "priv-ch" :name "Private" :kind "private"))
           (priv-id (fluxion.db.model:model-id priv)))
      (declare (ignore _open))
      (let* ((visible-without (strata.models.channel:list-channels-for-user ws-id 99 nil))
             (slugs-without   (mapcar (lambda (c)
                                        (strata.models.channel:channel-field c "slug"))
                                      visible-without)))
        (is (member "open-ch" slugs-without :test #'string=))
        (is (not (member "priv-ch" slugs-without :test #'string=))))
      (let* ((visible-with (strata.models.channel:list-channels-for-user ws-id 99 (list priv-id)))
             (slugs-with   (mapcar (lambda (c)
                                     (strata.models.channel:channel-field c "slug"))
                                   visible-with)))
        (is (member "priv-ch" slugs-with :test #'string=))))))

;;; -------------------------------------------------------
;;; Post
;;; -------------------------------------------------------

(test post-create-and-find
  "create-post persists a record retrievable by find-post-by-id."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (ch    (make-channel ws-id))
           (ch-id (fluxion.db.model:model-id ch))
           (post  (make-post ch-id :body "Hello world" :kind "message"))
           (pid   (fluxion.db.model:model-id post)))
      (is (not (null post)))
      (let ((found (strata.models.post:find-post-by-id pid)))
        (is (not (null found)))
        (is (string= "Hello world"
                     (strata.models.post:post-field found "body")))
        (is (string= "message"
                     (strata.models.post:post-field found "kind")))))))

(test post-list-for-channel
  "list-posts-for-channel returns posts in the channel."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (ch    (make-channel ws-id))
           (ch-id (fluxion.db.model:model-id ch)))
      (make-post ch-id :body "Post 1")
      (make-post ch-id :body "Post 2")
      (let ((posts (strata.models.post:list-posts-for-channel ch-id)))
        (is (>= (length posts) 2))))))

(test post-set-status
  "set-post-status changes the status field."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (ch    (make-channel ws-id))
           (ch-id (fluxion.db.model:model-id ch))
           (post  (make-post ch-id))
           (pid   (fluxion.db.model:model-id post)))
      (strata.models.post:set-post-status pid "resolved")
      (let ((found (strata.models.post:find-post-by-id pid)))
        (is (string= "resolved"
                     (strata.models.post:post-field found "status")))))))

(test post-update-body-and-history
  "update-post-body changes body, stamps edited_at, and records a post-edit row."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (ch    (make-channel ws-id))
           (ch-id (fluxion.db.model:model-id ch))
           (post  (make-post ch-id :body "Original"))
           (pid   (fluxion.db.model:model-id post)))
      (strata.models.post:update-post-body pid "Revised" :editor-id 1)
      (let ((found (strata.models.post:find-post-by-id pid))
            (edits (strata.models.post-edit:list-edits-for-post pid)))
        (is (string= "Revised"
                     (strata.models.post:post-field found "body")))
        (is (not (null (strata.models.post:post-field found "edited_at"))))
        (is (= 1 (length edits)))
        (is (string= "Original"
                     (strata.models.post-edit:post-edit-field (first edits) "body")))))))

(test post-delete-cascades
  "delete-post removes the post and all dependent rows."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (ch    (make-channel ws-id))
           (ch-id (fluxion.db.model:model-id ch))
           (post  (make-post ch-id :body "Gone"))
           (pid   (fluxion.db.model:model-id post)))
      (make-reply pid :body "Reply to be deleted")
      (strata.models.reaction:add-reaction :target-type "post" :target-id pid
                                           :user-id 1 :emoji "👍")
      (strata.models.post:update-post-body pid "Edited" :editor-id 1)
      (is (strata.models.post:delete-post pid))
      (is (null (strata.models.post:find-post-by-id pid)))
      (is (null (strata.models.reply:list-replies-for-post pid)))
      (is (null (strata.models.post-edit:list-edits-for-post pid))))))

;;; -------------------------------------------------------
;;; Reply
;;; -------------------------------------------------------

(test reply-create-and-list
  "create-reply persists a record; list-replies-for-post returns it."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (ch    (make-channel ws-id))
           (ch-id (fluxion.db.model:model-id ch))
           (post  (make-post ch-id))
           (pid   (fluxion.db.model:model-id post))
           (reply (make-reply pid :body "A reply")))
      (is (not (null reply)))
      (let ((replies (strata.models.reply:list-replies-for-post pid)))
        (is (= 1 (length replies)))
        (is (string= "A reply"
                     (strata.models.reply:reply-field (first replies) "body")))))))

;;; -------------------------------------------------------
;;; Reaction
;;; -------------------------------------------------------

(test reaction-add-remove
  "add-reaction creates a row; remove-reaction deletes it."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (ch    (make-channel ws-id))
           (ch-id (fluxion.db.model:model-id ch))
           (post  (make-post ch-id))
           (pid   (fluxion.db.model:model-id post)))
      (strata.models.reaction:add-reaction :target-type "post" :target-id pid
                                           :user-id 1 :emoji "🎉")
      (let ((after-add (strata.models.reaction:list-reactions-for-target "post" pid)))
        (is (= 1 (length after-add))))
      (strata.models.reaction:remove-reaction :target-type "post" :target-id pid
                                              :user-id 1 :emoji "🎉")
      (let ((after-remove (strata.models.reaction:list-reactions-for-target "post" pid)))
        (is (null after-remove))))))

;;; -------------------------------------------------------
;;; Bookmark
;;; -------------------------------------------------------

(test bookmark-add-remove-and-check
  "add-bookmark, bookmark-p, remove-bookmark work correctly."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (ch    (make-channel ws-id))
           (ch-id (fluxion.db.model:model-id ch))
           (post  (make-post ch-id))
           (pid   (fluxion.db.model:model-id post)))
      (is (not (strata.models.bookmark:bookmark-p 1 pid)))
      (strata.models.bookmark:add-bookmark :user-id 1 :post-id pid)
      (is (strata.models.bookmark:bookmark-p 1 pid))
      (strata.models.bookmark:remove-bookmark :user-id 1 :post-id pid)
      (is (not (strata.models.bookmark:bookmark-p 1 pid))))))

;;; -------------------------------------------------------
;;; Mention
;;; -------------------------------------------------------

(test mention-parse-and-list
  "extract-usernames extracts @usernames from post body."
  (let ((mentions (strata.models.mention:extract-usernames "Hey @alice and @bob!")))
    (is (member "alice" mentions :test #'string=))
    (is (member "bob"   mentions :test #'string=))
    (is (= 2 (length mentions)))))

(test mention-no-false-positives
  "extract-usernames returns nil when no @mentions are present."
  (is (null (strata.models.mention:extract-usernames "No mentions here."))))

;;; -------------------------------------------------------
;;; Attachment
;;; -------------------------------------------------------

(test attachment-create-and-find
  "create-attachment writes the record and find-attachment-by-uuid retrieves it."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (ch    (make-channel ws-id))
           (ch-id (fluxion.db.model:model-id ch))
           (post  (make-post ch-id))
           (pid   (fluxion.db.model:model-id post))
           (data  (make-array 4 :element-type '(unsigned-byte 8)
                                :initial-contents '(137 80 78 71)))
           (att   (strata.models.attachment:create-attachment
                   :post-id      pid
                   :reply-id     nil
                   :uploader-id  1
                   :filename     "test.png"
                   :content-type "image/png"
                   :size-bytes   4
                   :file-data    data)))
      (is (not (null att)))
      (let* ((uuid  (strata.models.attachment:attachment-field att "uuid"))
             (found (strata.models.attachment:find-attachment-by-uuid uuid)))
        (is (not (null found)))
        (is (string= "test.png"
                     (strata.models.attachment:attachment-field found "filename")))
        (is (string= "image/png"
                     (strata.models.attachment:attachment-field found "content_type")))
        (is (= pid (strata.models.attachment:attachment-field found "post_id")))
        (strata.models.attachment:delete-attachment uuid)
        (is (null (strata.models.attachment:find-attachment-by-uuid uuid)))))))

(test attachment-list-for-post
  "list-attachments-for-post returns all attachments linked to a post."
  (with-test-db
    (let* ((ws    (make-workspace))
           (ws-id (fluxion.db.model:model-id ws))
           (ch    (make-channel ws-id))
           (ch-id (fluxion.db.model:model-id ch))
           (post  (make-post ch-id))
           (pid   (fluxion.db.model:model-id post))
           (data  (make-array 1 :element-type '(unsigned-byte 8) :initial-element 0)))
      (strata.models.attachment:create-attachment
       :post-id pid :reply-id nil :uploader-id 1
       :filename "a.txt" :content-type "text/plain" :size-bytes 1 :file-data data)
      (strata.models.attachment:create-attachment
       :post-id pid :reply-id nil :uploader-id 1
       :filename "b.txt" :content-type "text/plain" :size-bytes 1 :file-data data)
      (let ((atts (strata.models.attachment:list-attachments-for-post pid)))
        (is (= 2 (length atts)))))))

;;; -------------------------------------------------------
;;; Runner
;;; -------------------------------------------------------

(defun run-tests ()
  "Run all Strata tests (models + API) and return the results."
  (run! 'strata-model-tests)
  (run! 'strata-api-tests)
  (run! 'strata-mcp-tests))
