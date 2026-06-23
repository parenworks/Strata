;;;; -*- encoding:utf-8 -*-
;;;; Strata - Post model
;;;;
;;;; A post is the first-class object in a channel.  Every mutation that
;;;; touches a post calls TOUCH-POST, which bumps last_activity and fires
;;;; the :post-touched hook so all subscribed components can re-sort.

(in-package #:strata.models.post)

(defparameter +collection+ "posts")

(defparameter +post-kinds+
  '("message" "question" "decision" "announcement" "task" "poll" "note")
  "Valid post kind values.")

(defparameter +post-statuses+
  '("open" "resolved" "decided" "done")
  "Valid post status values.")

(defun post-field (post field)
  "Return the value of FIELD in the POST data-model object.
FIELD is a column name string, e.g. \"body\", \"kind\", \"status\", \"last_activity\"."
  (fxdm:model-field post field))

(defun touch-post (post-id)
  "Update last_activity on POST-ID to now and persist it, then fire :post-touched.
This is the single write path all mutations go through to resurface a post in
the feed. Replies, reactions, and status changes all call this so the channel
feed ordering always reflects the most recent activity on a thread.
If the :post-touched hook has not been registered this call is a no-op for
the hook but the database update still happens."
  (let ((p (find-post-by-id post-id)))
    (when p
      (setf (fxdm:model-field p "last_activity") (get-universal-time))
      (fxdm:save p)
      (when (fluxion.hooks:hook-defined-p :post-touched)
        (fluxion.hooks:trigger :post-touched post-id))
      p)))

(defun create-post (&key channel-id author-id kind body (status "open") pinned)
  "Create and persist a new post record. Returns the saved data-model.
CHANNEL-ID is the _id of the channel this post belongs to.
AUTHOR-ID is the _id of the posting user.
KIND must be one of +post-kinds+: \"message\" (default), \"question\",
  \"decision\", \"announcement\", \"task\", \"poll\", or \"note\".
BODY is the plain-text (or lightly marked-up) content.
STATUS defaults to \"open\"; valid values are in +post-statuses+.
PINNED, if non-nil, pins the post to the top of the feed.
Fires :post-created with the new post's _id if that hook is registered."
  (let ((p (fxdm:hull +collection+)))
    (setf (fxdm:model-field p "channel_id")    channel-id
          (fxdm:model-field p "author_id")      author-id
          (fxdm:model-field p "kind")           (or kind "message")
          (fxdm:model-field p "body")           body
          (fxdm:model-field p "status")         (or status "open")
          (fxdm:model-field p "pinned")         (if pinned 1 0)
          (fxdm:model-field p "last_activity")  (get-universal-time)
          (fxdm:model-field p "created_at")     (get-universal-time))
    (fxdm:insert-model p)
    (when (fluxion.hooks:hook-defined-p :post-created)
      (fluxion.hooks:trigger :post-created (fxdm:model-id p)))
    (strata.models.mention:parse-and-record-mentions
     :post-id      (fxdm:model-id p)
     :body         body
     :channel-name (princ-to-string channel-id)
     :poster-name  (princ-to-string author-id))
    p))

(defun find-post-by-id (id)
  "Return the post data-model whose _id equals the integer ID, or NIL."
  (fxdm:get-one +collection+
                (db:compile-query `(:= _id ,id))))

(defun list-posts-for-channel (channel-id &key include-resolved (limit 50))
  "Return posts for CHANNEL-ID sorted by pinned DESC then last_activity DESC.
By default posts with status \"resolved\", \"decided\", or \"done\" are excluded;
pass INCLUDE-RESOLVED t to include them.
LIMIT caps the result set; defaults to 50. This is the primary feed query."
  (if include-resolved
      (fxdm:get-all +collection+
                    (db:compile-query `(:= channel_id ,channel-id))
                    :sort '(("pinned" . :desc) ("last_activity" . :desc))
                    :amount limit)
      (let ((resolved-statuses '("resolved" "decided" "done")))
        (fxdm:get-all +collection+
                      (db:compile-query
                       `(:and (:= channel_id ,channel-id)
                              (:not-in status ,resolved-statuses)))
                      :sort '(("pinned" . :desc) ("last_activity" . :desc))
                      :amount limit))))

(defun reindex-post (post-id)
  "Update the search_vector column for POST-ID using to_tsvector.
Safe to call repeatedly; a no-op if the post is not found."
  (let ((p (find-post-by-id post-id)))
    (when p
      (db:update-expr +collection+
                      (db:compile-query `(:= _id ,post-id))
                      `(("search_vector" . (:expr "to_tsvector('english', coalesce(\"body\", ''))")))))))

(defun search-posts (query-text &key channel-id (limit 20))
  "Return up to LIMIT posts whose search_vector matches QUERY-TEXT.
Uses plainto_tsquery for plain phrase matching.
Optionally filter to a specific CHANNEL-ID."
  (handler-case
      (let* ((channel-clause (if channel-id
                                 (format nil " AND \"channel_id\" = ~D" channel-id)
                                 ""))
             (sql (format nil
                          "SELECT * FROM \"posts\" WHERE \"search_vector\" @@ plainto_tsquery('english', $1)~A ORDER BY ts_rank(\"search_vector\", plainto_tsquery('english', $1)) DESC LIMIT ~D"
                          channel-clause limit))
             (rows (db:select-query sql (list query-text))))
        (mapcar (lambda (row)
                  (fxdm:alist-to-model +collection+ row))
                rows))
    (error (e)
      (format t "~&[strata] search-posts error: ~A~%" e)
      nil)))

(defun update-post-body (post-id new-body &key (editor-id 0))
  "Replace the body of POST-ID with NEW-BODY and stamp edited_at.
Records the previous body in post_edits before overwriting.
Reindexes the search_vector and touches the post to resurface it."
  (let ((p (find-post-by-id post-id)))
    (when p
      (let ((old-body (fxdm:model-field p "body")))
        (strata.models.post-edit:record-edit post-id editor-id old-body))
      (setf (fxdm:model-field p "body")      new-body
            (fxdm:model-field p "edited_at") (get-universal-time))
      (fxdm:save p)
      (reindex-post post-id)
      (touch-post post-id)
      p)))

(defun delete-post (post-id)
  "Permanently remove POST-ID and all its replies, reactions, and mentions.
Returns T if the post existed, NIL otherwise."
  (let ((p (find-post-by-id post-id)))
    (when p
      (db:remove "replies"    (db:compile-query `(:= post_id ,post-id)))
      (db:remove "reactions"  (db:compile-query
                                `(:and (:= target_type "post")
                                       (:= target_id   ,post-id))))
      (db:remove "mentions"   (db:compile-query `(:= post_id ,post-id)))
      (db:remove "bookmarks"  (db:compile-query `(:= post_id ,post-id)))
      (db:remove "post_edits" (db:compile-query `(:= post_id ,post-id)))
      (db:remove "posts"      (db:compile-query `(:= _id ,post-id)))
      t)))

(defun set-post-status (post-id status)
  "Set the status field of POST-ID to STATUS and call touch-post.
STATUS must be one of +post-statuses+: \"open\", \"resolved\", \"decided\", \"done\".
Setting a non-open status will cause the post to disappear from the default
feed view on the next render (list-posts-for-channel excludes them)."
  (let ((p (find-post-by-id post-id)))
    (when p
      (setf (fxdm:model-field p "status") status)
      (fxdm:save p)
      (touch-post post-id)
      p)))
