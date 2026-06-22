;;;; -*- encoding:utf-8 -*-
;;;; Strata - Search indexer job
;;;;
;;;; Registers hooks that keep the posts.search_vector column in sync.
;;;; start-search-hooks subscribes to :post-created and :post-touched.
;;;; backfill-search-index reindexes all existing posts on first run.

(in-package #:strata.jobs.search)

(defun reindex-in-background (post-id)
  "Reindex POST-ID in a background thread."
  (bt:make-thread
   (lambda ()
     (handler-case
         (strata.models.post:reindex-post post-id)
       (error (e)
         (format t "~&[strata] search reindex error for post ~A: ~A~%" post-id e))))
   :name "strata-search-reindex"))

(defun start-search-hooks ()
  "Register :post-created and :post-touched triggers to keep search_vector current."
  (hooks:define-hook
   :post-created
   :description "Fired when a new post is created."
   :args '(:post-id))
  (hooks:add-trigger
   :post-created :search-index
   :handler (lambda (&rest args)
              (reindex-in-background (car args))))
  (hooks:add-trigger
   :post-touched :search-reindex
   :handler (lambda (&rest args)
              (reindex-in-background (car args))))
  (format t "~&[strata] Search index hooks registered.~%"))

(defun backfill-search-index ()
  "Reindex all existing posts.  Run once at startup after ensure-schema."
  (bt:make-thread
   (lambda ()
     (handler-case
         (let ((posts (fluxion.db.model:get-all
                       "posts"
                       (fluxion.db:compile-query :all)
                       :amount 10000)))
           (dolist (p posts)
             (handler-case
                 (strata.models.post:reindex-post
                  (fluxion.db.model:model-id p))
               (error () nil)))
           (format t "~&[strata] Search index backfill complete.~%"))
       (error (e)
         (format t "~&[strata] Search index backfill error: ~A~%" e))))
   :name "strata-search-backfill"))
