;;;; -*- encoding:utf-8 -*-
;;;; Strata tests - DB fixture helpers
;;;;
;;;; with-test-db wraps each test body in a PostgreSQL transaction that is
;;;; always rolled back, so tests leave no permanent state in the database.

(in-package #:strata.tests.fixtures)

(defun %ensure-test-hooks ()
  "Register no-op stubs for application hooks so tests run without the full
app hook registry. Called once after DB connection is established."
  (dolist (hook '(:post-created :post-touched :mention :push-notification))
    (unless (fluxion.hooks:hook-defined-p hook)
      (fluxion.hooks:define-hook hook)
      (fluxion.hooks:add-trigger hook :test-noop
                                 :handler (lambda (&rest args)
                                            (declare (ignore args)) nil)))))

(defun ensure-connected ()
  "Connect to the dev DB if not already connected, then register test hooks."
  (unless strata.app:*db-backend*
    (strata.app:connect-db :database "strata_dev"
                           :user     "strata"
                           :password "localtest123"
                           :host     "localhost"
                           :port     5432))
  (%ensure-test-hooks))

(defmacro with-test-db (&body body)
  "Execute BODY inside a rolled-back PostgreSQL transaction.
All inserts, updates and deletes made during BODY are undone on exit,
whether BODY completes normally or signals a condition.
Hook-not-found conditions are suppressed since the test context does not
start the full application hook registry."
  `(progn
     (ensure-connected)
     (handler-bind ((fluxion.hooks:hook-not-found #'continue))
       (postmodern:with-transaction (txn)
         (unwind-protect
              (progn ,@body)
           (postmodern:abort-transaction txn))))))

(defun make-workspace (&key (slug "test-workspace") (name "Test Workspace"))
  "Insert and return a workspace fixture."
  (strata.models.workspace:create-workspace
   :slug slug :display-name name))

(defun make-channel (workspace-id &key (slug "test-channel") (name "Test Channel") (kind "open"))
  "Insert and return a channel fixture in WORKSPACE-ID."
  (strata.models.channel:create-channel
   :workspace-id workspace-id
   :slug slug
   :name name
   :kind kind))

(defun make-user (&key (username "testuser") (password "testpass"))
  "Create a test user, returning the username string.
If the user already exists the call is a no-op."
  (handler-case
      (fluxion.user:create username :password password)
    (error () nil))
  username)

(defun make-post (channel-id &key (author-id 1) (body "Test post body") (kind "message"))
  "Insert and return a post fixture in CHANNEL-ID.
Hook-not-found conditions from unregistered notification hooks are suppressed
since the test context does not start the full application."
  (handler-bind ((fluxion.hooks:hook-not-found #'continue))
    (strata.models.post:create-post
     :channel-id channel-id
     :author-id  author-id
     :body       body
     :kind       kind)))

(defun make-reply (post-id &key (author-id 1) (body "Test reply body"))
  "Insert and return a reply fixture on POST-ID."
  (strata.models.reply:create-reply
   :post-id   post-id
   :author-id author-id
   :body      body))
