;;;; -*- encoding:utf-8 -*-
;;;; Strata - Bookmark model

(in-package #:strata.models.bookmark)

(defparameter +collection+ "bookmarks")

(defun bookmark-field (bookmark field)
  "Return the value of FIELD in the BOOKMARK data-model object.
FIELD is a column name string, e.g. \"note\", \"due_date\", \"post_id\"."
  (fxdm:model-field bookmark field))

(defun add-bookmark (&key user-id post-id note due-date)
  "Save a bookmark of POST-ID for USER-ID and return the data-model.
USER-ID and POST-ID are integer _ids.
NOTE is an optional freetext annotation; defaults to an empty string.
DUE-DATE is an optional ISO-8601 date string used for reminder sorting.
Does not enforce uniqueness; callers should call remove-bookmark first
if replacing an existing bookmark on the same post."
  (let ((b (fxdm:hull +collection+)))
    (setf (fxdm:model-field b "user_id")    user-id
          (fxdm:model-field b "post_id")    post-id
          (fxdm:model-field b "note")       (or note "")
          (fxdm:model-field b "due_date")   (or due-date "")
          (fxdm:model-field b "created_at") (get-universal-time))
    (fxdm:insert-model b)
    b))

(defun remove-bookmark (&key user-id post-id)
  "Delete the bookmark record for USER-ID on POST-ID.
Is a no-op if no such record exists."
  (db:remove +collection+
             (db:compile-query `(:and (:= user_id ,user-id)
                                      (:= post_id ,post-id)))))

(defun bookmark-p (user-id post-id)
  "Return T if USER-ID has bookmarked POST-ID, NIL otherwise."
  (not (null (fxdm:get-one +collection+
                            (db:compile-query
                             `(:and (:= user_id ,user-id)
                                    (:= post_id ,post-id)))))))

(defun list-bookmarks-for-user (user-id &key (limit 50))
  "Return up to LIMIT bookmarks for USER-ID, ordered by due_date ASC then created_at DESC.
Bookmarks with a due_date sort to the top so time-sensitive reminders appear first.
LIMIT defaults to 50."
  (fxdm:get-all +collection+
                (db:compile-query `(:= user_id ,user-id))
                :sort '(("due_date" . :asc) ("created_at" . :desc))
                :amount limit))
