;;;; -*- encoding:utf-8 -*-
;;;; Strata - Mention model

(in-package #:strata.models.mention)

(defparameter +collection+ "mentions")

(defun mention-field (mention field)
  "Return the value of FIELD in the MENTION data-model object.
FIELD is a column name string, e.g. \"mentioned_user_id\", \"post_id\"."
  (fxdm:model-field mention field))

(defun record-mention (&key post-id reply-id mentioned-user-id)
  "Record a parsed @mention and return the saved data-model.
Exactly one of POST-ID or REPLY-ID should be non-nil; the other is stored as 0.
MENTIONED-USER-ID is the _id of the user who was mentioned.
Call this from the post/reply creation path after parsing @name tokens
from the body text to drive notification queries."
  (let ((m (fxdm:hull +collection+)))
    (setf (fxdm:model-field m "post_id")            (or post-id 0)
          (fxdm:model-field m "reply_id")           (or reply-id 0)
          (fxdm:model-field m "mentioned_user_id")  mentioned-user-id
          (fxdm:model-field m "created_at")         (get-universal-time))
    (fxdm:insert-model m)
    m))

(defun extract-usernames (body)
  "Return a list of unique username strings found as @username tokens in BODY.
Matches word characters after @, e.g. @alice or @bob_smith."
  (let ((results nil))
    (cl-ppcre:do-matches-as-strings (m "@([\\w]+)" body)
      (let ((name (subseq m 1)))
        (pushnew name results :test #'string=)))
    results))

(defun parse-and-record-mentions (&key post-id reply-id body channel-name poster-name)
  "Extract @username tokens from BODY, record each mention, and fire the
:mention hook so push notifications are sent.  CHANNEL-NAME and POSTER-NAME
are used as display strings in the push notification payload.
Safe to call when DB or hooks are unavailable; errors are silently ignored."
  (handler-case
      (let* ((names (extract-usernames body))
             (uids  nil))
        (dolist (name names)
          (let ((u (handler-case (fluxion.user:get name) (error () nil))))
            (when u
              (let ((uid (fluxion.user:user-id u)))
                (record-mention :post-id post-id
                                :reply-id reply-id
                                :mentioned-user-id uid)
                (push uid uids)))))
        (when (and uids (fluxion.hooks:hook-defined-p :mention))
          (fluxion.hooks:trigger :mention
                                 (list :mentioned-user-ids uids
                                       :channel-name channel-name
                                       :poster-name  poster-name))))
    (error () nil)))

(defun list-mentions-for-user (user-id &key (limit 50))
  "Return up to LIMIT recent mentions for USER-ID, ordered newest first.
Used to populate the @mentions inbox view. LIMIT defaults to 50."
  (fxdm:get-all +collection+
                (db:compile-query `(:= mentioned_user_id ,user-id))
                :sort '(("created_at" . :desc))
                :amount limit))
