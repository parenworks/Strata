;;;; -*- encoding:utf-8 -*-
;;;; Strata - Inbox component
;;;;
;;;; Renders the user's personal inbox: @mention notifications and
;;;; bookmarked posts, in a two-section tabbed layout.

(in-package #:strata.components.inbox)

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
  "Return the integer user ID from SESSION, or 0."
  (handler-case
      (strata.auth:user-id-from-session session)
    (error () 0)))

(defun session-display-name (session)
  "Return a display name for the current session user."
  (handler-case
      (let ((u (fluxion.server:session-user session)))
        (if u
            (or (strata.auth:user-display-name u)
                (fluxion.user:user-username u)
                "User")
            "Guest"))
    (error () "Guest")))

;;; -------------------------------------------------------
;;; Component
;;; -------------------------------------------------------

(fluxion.components:defcomponent inbox-component
  :id "strata-inbox"
  :slots ((active-tab :initform "mentions" :accessor inbox-active-tab))

  :render
  (let* ((session  (fluxion.components:component-session self))
         (user-id  (session-author-id session))
         (username (session-display-name session))
         (tab      (inbox-active-tab self))
         (mentions (handler-case
                       (strata.models.mention:list-mentions-for-user user-id)
                     (error () nil)))
         (bookmarks (handler-case
                        (strata.models.bookmark:list-bookmarks-for-user user-id)
                      (error () nil))))
    (spinneret:with-html-string
      (:div :id (fluxion.components:component-id self)
            :class "inbox-page"

        (:header :class "inbox-header"
          (:h1 :class "inbox-title" "Inbox")
          (:span :class "inbox-user" username))

        (:nav :class "inbox-tabs"
          (:button :class (if (string= tab "mentions") "inbox-tab active" "inbox-tab")
                   :type "button"
                   :data-on-click (format nil "/action/strata-inbox/switch-tab?tab=mentions")
            (format nil "@ Mentions (~A)" (length mentions)))
          (:button :class (if (string= tab "bookmarks") "inbox-tab active" "inbox-tab")
                   :type "button"
                   :data-on-click (format nil "/action/strata-inbox/switch-tab?tab=bookmarks")
            (format nil "Bookmarks (~A)" (length bookmarks))))

        (cond
          ((string= tab "mentions")
           (:section :class "inbox-section"
             (if mentions
                 (dolist (m mentions)
                   (let* ((post-id  (strata.models.mention:mention-field m "post_id"))
                          (reply-id (strata.models.mention:mention-field m "reply_id"))
                          (ts       (strata.models.mention:mention-field m "created_at"))
                          (post     (when (and post-id (plusp post-id))
                                      (handler-case
                                          (strata.models.post:find-post-by-id post-id)
                                        (error () nil))))
                          (body     (if post
                                        (strata.models.post:post-field post "body")
                                        (format nil "Reply ~A" reply-id))))
                     (:article :class "inbox-item"
                       (:div :class "inbox-item-meta"
                         (:span :class "inbox-item-label" "@mention")
                         (:span :class "post-time" (fmt-time ts)))
                       (:p :class "inbox-item-body" body))))
                 (:p :class "feed-empty" "No mentions yet."))))

          ((string= tab "bookmarks")
           (:section :class "inbox-section"
             (if bookmarks
                 (dolist (b bookmarks)
                   (let* ((post-id (strata.models.bookmark:bookmark-field b "post_id"))
                          (note    (strata.models.bookmark:bookmark-field b "note"))
                          (due     (strata.models.bookmark:bookmark-field b "due_date"))
                          (ts      (strata.models.bookmark:bookmark-field b "created_at"))
                          (post    (when post-id
                                     (handler-case
                                         (strata.models.post:find-post-by-id post-id)
                                       (error () nil))))
                          (body    (if post
                                       (strata.models.post:post-field post "body")
                                       "(post not found)")))
                     (:article :class "inbox-item"
                       (:div :class "inbox-item-meta"
                         (:span :class "inbox-item-label" "Bookmark")
                         (when (and due (plusp (length due)))
                           (:span :class "inbox-item-due" (format nil "Due: ~A" due)))
                         (:span :class "post-time" (fmt-time ts)))
                       (:p :class "inbox-item-body" body)
                       (when (and note (plusp (length note)))
                         (:p :class "inbox-item-note" note)))))
                 (:p :class "feed-empty" "No bookmarks yet.")))))))))

;;; -------------------------------------------------------
;;; Actions
;;; -------------------------------------------------------

(fluxion.components:defaction inbox-component :switch-tab (self params)
  "Switch between mentions and bookmarks tabs."
  (let ((tab (cdr (assoc "tab" params :test #'string=))))
    (when (member tab '("mentions" "bookmarks") :test #'string=)
      (setf (inbox-active-tab self) tab)))
  (fluxion.components:patch-component self))

;;; -------------------------------------------------------
;;; Page renderer
;;; -------------------------------------------------------

(defun make-inbox ()
  "Create a fresh inbox-component instance for use as a per-session factory."
  (make-instance 'inbox-component))

(defun render-inbox-page (session)
  "Render the full inbox HTML page for SESSION."
  (let* ((inbox (fluxion.server:session-component session "strata-inbox"))
         (csrf  (fluxion.server:session-csrf-token session)))
    (unless inbox
      (error "[strata] inbox component not found in session"))
    (fluxion.render:render-page
     :title "Inbox - Strata"
     :head-html (format nil
                  "<script src=\"/static/js/theme.js\"></script>~
                   <link rel=\"stylesheet\" href=\"/static/css/strata.css\">")
     :csrf-token csrf
     :body-html  (fluxion.components:render inbox)
     :script-path "/static/fluxion.js")))
