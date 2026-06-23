;;;; -*- encoding:utf-8 -*-
;;;; Strata - Notification fanout job
;;;;
;;;; Registers the :mention hook and the :post-touched hook.
;;;;
;;;; :mention  -- fans out Web Push notifications to mentioned users in a
;;;;              detached bordeaux-threads thread.
;;;; :post-touched -- pushes a live component patch to every active session
;;;;              so the feed re-sorts without a page reload.

(in-package #:strata.jobs.notifications)

(defun broadcast-post-touched (post-id)
  "Push a component patch to all active sessions when POST-ID is touched.
Each session's strata-shell component re-renders so the feed re-sorts live.
Runs in a background thread so it never blocks the write path."
  (bt:make-thread
   (lambda ()
     (ignore-errors
      (let ((app strata.app:*app*))
        (when app
          (bt:with-lock-held ((fx:app-session-lock app))
            (maphash
             (lambda (sid session)
               (declare (ignore sid))
               (ignore-errors
                (let ((shell (fx:session-component session "strata-shell")))
                  (when shell
                    (fx:push-component-patch session shell)))))
             (fx:app-sessions app)))))))
   :name (format nil "strata-post-touched-~A" post-id)))

(defun start-notification-hooks ()
  "Register the :mention and :post-touched hooks.  Call once at startup."
  (hooks:define-hook
   :mention
   :description "Fired when a post or reply mentions a user."
   :args '(:mentioned-user-ids :channel-name :poster-name))
  (hooks:add-trigger
   :mention :push-fanout
   :handler (lambda (&rest args)
              (let* ((plist        (if (and args (listp (car args))) (car args) args))
                     (uids         (getf plist :mentioned-user-ids))
                     (channel-name (or (getf plist :channel-name) "a channel"))
                     (poster-name  (or (getf plist :poster-name)  "Someone")))
                (bt:make-thread
                 (lambda ()
                   (ignore-errors
                    (strata.push:notify-mentioned-users uids channel-name poster-name)))
                 :name "strata-push-fanout"))))
  (unless (hooks:hook-defined-p :post-touched)
    (hooks:define-hook
     :post-touched
     :description "Fired when a post is updated or receives activity."
     :args '(:post-id)))
  (hooks:add-trigger
   :post-touched :live-resort
   :handler (lambda (&rest args)
              (broadcast-post-touched (car args))))
  (format t "~&[strata] Notification hooks registered.~%"))
