;;;; -*- encoding:utf-8 -*-
;;;; Strata - Thread pane component
;;;;
;;;; Renders the right-hand thread pane for a single post: the original
;;;; post body, all replies in order, and a reply composer.
;;;; Embedded inside the shell as a conditional panel when shell-thread-post-id is set.

(in-package #:strata.components.thread)

;;; -------------------------------------------------------
;;; Helpers
;;; -------------------------------------------------------

(defun fmt-time (ut)
  "Format universal-time UT as a short human-readable string."
  (when ut
    (multiple-value-bind (sec min hour day mon year)
        (decode-universal-time ut)
      (declare (ignore sec))
      (format nil "~2,'0d ~a ~d ~2,'0d:~2,'0d"
              day
              (nth (1- mon) '("Jan" "Feb" "Mar" "Apr" "May" "Jun"
                              "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))
              year hour min))))

(defun session-author-id (session)
  "Extract the numeric user id from SESSION, defaulting to 0."
  (handler-case
      (let ((u (fluxion.server:session-user session)))
        (if u (fluxion.user:user-id u) 0))
    (error () 0)))

;;; -------------------------------------------------------
;;; Render helper (called from shell, not a standalone component)
;;; -------------------------------------------------------

(defun render-thread-pane (post-id shell-component-id session)
  "Return an HTML string for the thread pane showing POST-ID's replies.
SHELL-COMPONENT-ID is the DOM id of the enclosing shell component, used
to build action URLs. SESSION is the current Fluxion session."
  (let* ((post    (handler-case (strata.models.post:find-post-by-id post-id)
                    (error () nil)))
         (replies (handler-case (strata.models.reply:list-replies-for-post post-id)
                    (error () nil)))
         (post-attachments (handler-case
                               (strata.models.attachment:list-attachments-for-post post-id)
                             (error () nil)))
         (uid     (session-author-id session)))
    (spinneret:with-html-string
      (:div :class "thread-pane"
        (:div :class "thread-pane-header"
          (:span :class "thread-pane-title" "Thread")
          (:button :class "thread-pane-close"
                   :type "button"
                   :data-on-click (format nil "/action/~A/close-thread" shell-component-id)
                   :title "Close thread"
                   "x"))

        (:div :class "thread-pane-body"
          (if post
              (let* ((body    (strata.models.post:post-field post "body"))
                     (kind    (or (strata.models.post:post-field post "kind") "message"))
                     (ts      (strata.models.post:post-field post "created_at")))
                (:div :class "thread-original-post"
                  (:div :class "thread-post-meta"
                    (:span :class (format nil "post-kind-badge post-kind-~A" kind) kind)
                    (:span :class "post-time" (fmt-time ts)))
                  (:p :class "post-body" body)
                  (strata.components.shell:render-attachment-list post-attachments)))
              (:p "Post not found."))

          (:div :class "thread-replies"
            (if replies
                (dolist (r replies)
                  (let* ((rid   (fxdm:model-id r))
                         (body  (strata.models.reply:reply-field r "body"))
                         (ts    (strata.models.reply:reply-field r "created_at"))
                         (ratts (handler-case
                                    (strata.models.attachment:list-attachments-for-reply rid)
                                  (error () nil))))
                    (:div :class "thread-reply"
                      (:div :class "thread-reply-meta"
                        (:span :class "post-time" (fmt-time ts)))
                      (:p :class "post-body" body)
                      (strata.components.shell:render-attachment-list ratts))))
                (:p :class "feed-empty" "No replies yet.")))

          (:form :class "thread-composer"
                 :data-on-submit (format nil "/action/~A/reply" shell-component-id)
            (:input :type "hidden" :name "post_id" :value (princ-to-string post-id))
            (:input :type "hidden" :name "author_id" :value (princ-to-string uid))
            (:textarea :class "composer-textarea"
                       :name "body"
                       :placeholder "Reply..."
                       :rows 2
                       :onkeydown "if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();this.closest('form').requestSubmit();}")
            (:button :type "submit" :class "composer-send-btn"
                     :data-disable-during-request t
              "Reply")))))))
