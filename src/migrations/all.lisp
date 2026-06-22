;;;; -*- encoding:utf-8 -*-
;;;; Strata - Database schema
;;;;
;;;; ensure-schema creates all tables on startup using CREATE IF NOT EXISTS.
;;;; It is safe to call on every restart: existing tables are left untouched.
;;;; To add a new table, add a db:create call here and restart the server.
;;;; No version numbers, no migration runner, no separate scripts required.

(in-package #:strata.migrations)

(defun ensure-schema ()
  "Create all Strata tables if they do not already exist.
Safe to call on every startup. Adding a new table here and restarting
is all that is required to extend the schema during development."

  (db:create "workspaces"
             '((slug         :text)
               (display_name :text)
               (visibility   :text)
               (created_at   :bigint))
             :if-exists :ignore)

  (db:create "channels"
             '((workspace_id  :integer)
               (slug          :text)
               (name          :text)
               (description   :text)
               (kind          :text)
               (visibility    :text)
               (last_activity :bigint)
               (created_at    :bigint))
             :if-exists :ignore)

  (db:create "posts"
             '((channel_id    :integer)
               (author_id     :integer)
               (kind          :text)
               (body          :text)
               (status        :text)
               (pinned        :integer)
               (last_activity :bigint)
               (created_at    :bigint))
             :if-exists :ignore)

  (db:create "replies"
             '((post_id    :integer)
               (author_id  :integer)
               (body       :text)
               (created_at :bigint))
             :if-exists :ignore)

  (db:create "reactions"
             '((target_type :text)
               (target_id   :integer)
               (user_id     :integer)
               (emoji       :text)
               (created_at  :bigint))
             :if-exists :ignore)

  (db:create "mentions"
             '((post_id           :integer)
               (reply_id          :integer)
               (mentioned_user_id :integer)
               (created_at        :bigint))
             :if-exists :ignore)

  (db:create "bookmarks"
             '((user_id    :integer)
               (post_id    :integer)
               (note       :text)
               (due_date   :text)
               (created_at :bigint))
             :if-exists :ignore)

  (db:create "channel_reads"
             '((user_id           :integer)
               (channel_id        :integer)
               (last_read_post_id :integer)
               (updated_at        :bigint))
             :if-exists :ignore)

  (db:create "channel_members"
             '((channel_id :integer)
               (user_id    :integer)
               (role       :text)
               (joined_at  :bigint))
             :if-exists :ignore)

  (db:alter "channels"
            '((workspace_id      :integer)
              (slug               :text)
              (name               :text)
              (description        :text)
              (kind               :text)
              (visibility         :text)
              (last_activity      :bigint)
              (created_at         :bigint)
              (parent_channel_id  :integer)))

  (db:create "push_subscriptions"
             '((user_id    :integer)
               (endpoint   :text)
               (p256dh     :text)
               (auth_key   :text)
               (created_at :bigint))
             :if-exists :ignore)

  (db:alter "posts"
            '((channel_id    :integer)
              (author_id     :integer)
              (kind          :text)
              (body          :text)
              (status        :text)
              (pinned        :integer)
              (last_activity :bigint)
              (created_at    :bigint)
              (search_vector "tsvector")))

  (db:ensure-index "posts" "posts_search_vector_gin"
                   '("search_vector") :method "GIN"))
