;;;; -*- encoding:utf-8 -*-
;;;; Strata - Reply model
;;;;
;;;; Creating a reply always calls strata.models.post:touch-post on the
;;;; parent so the original post resurfaces in the channel feed.

(in-package #:strata.models.reply)

(defparameter +collection+ "replies")

(defun reply-field (reply field)
  "Return the value of FIELD in the REPLY data-model object.
FIELD is a column name string, e.g. \"body\", \"author_id\", \"post_id\"."
  (fxdm:model-field reply field))

(defun create-reply (&key post-id author-id body)
  "Create and persist a reply to POST-ID. Returns the saved data-model.
POST-ID is the _id of the post being replied to.
AUTHOR-ID is the _id of the replying user.
BODY is the plain-text reply content.
Always calls touch-post on POST-ID so the parent resurfaces in the feed."
  (let ((r (fxdm:hull +collection+)))
    (setf (fxdm:model-field r "post_id")    post-id
          (fxdm:model-field r "author_id")  author-id
          (fxdm:model-field r "body")       body
          (fxdm:model-field r "created_at") (get-universal-time))
    (fxdm:insert-model r)
    (strata.models.post:touch-post post-id)
    (strata.models.mention:parse-and-record-mentions
     :reply-id    (fxdm:model-id r)
     :post-id     post-id
     :body        body
     :poster-name (princ-to-string author-id))
    r))

(defun find-reply-by-id (id)
  "Return the reply data-model whose _id equals the integer ID, or NIL."
  (fxdm:get-one +collection+
                (db:compile-query `(:= _id ,id))))

(defun list-replies-for-post (post-id)
  "Return all replies for POST-ID sorted by created_at ascending.
This is the ordering used in the thread pane: oldest reply first."
  (fxdm:get-all +collection+
                (db:compile-query `(:= post_id ,post-id))
                :sort '(("created_at" . :asc))))
