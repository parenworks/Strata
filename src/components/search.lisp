;;;; -*- encoding:utf-8 -*-
;;;; Strata - Search component
;;;;
;;;; Renders a search page: text input, optional kind/status filters,
;;;; and a ranked result list of matching posts.

(in-package #:strata.components.search)

;;; -------------------------------------------------------
;;; Helpers
;;; -------------------------------------------------------

(defun fmt-time (ut)
  "Format universal-time UT as a short readable string."
  (when (and ut (not (zerop ut)))
    (multiple-value-bind (sec min hour day mon year)
        (decode-universal-time ut)
      (declare (ignore sec))
      (format nil "~2,'0d ~a ~d ~2,'0d:~2,'0d"
              day
              (nth (1- mon) '("Jan" "Feb" "Mar" "Apr" "May" "Jun"
                              "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))
              year hour min))))

(defun session-display-name (session)
  "Return display name for SESSION user."
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

(fluxion.components:defcomponent search-component
  :id "strata-search"
  :slots ((query-text  :initform "" :accessor search-query-text)
          (kind-filter :initform "" :accessor search-kind-filter)
          (results     :initform nil :accessor search-results))

  :render
  (let* ((session  (fluxion.components:component-session self))
         (username (session-display-name session))
         (q        (search-query-text self))
         (kind     (search-kind-filter self))
         (hits     (search-results self)))
    (spinneret:with-html-string
      (:div :id (fluxion.components:component-id self)
            :class "search-page"

        (:header :class "inbox-header"
          (:h1 :class "inbox-title" "Search")
          (:span :class "inbox-user" username))

        (:form :class "search-form"
               :data-on-submit (format nil "/action/strata-search/search")
          (:input :class "search-input"
                  :type "text"
                  :name "q"
                  :value q
                  :placeholder "Search posts..."
                  :autofocus t)
          (:select :class "search-filter" :name "kind"
            (:option :value "" (if (string= kind "") "All types" "All types"))
            (dolist (k strata.models.post:+post-kinds+)
              (:option :value k :selected (string= k kind) k)))
          (:button :class "search-submit" :type "submit" "Search"))

        (cond
          ((and q (plusp (length q)) (null hits))
           (:p :class "feed-empty" "No results found."))

          (hits
           (:section :class "search-results"
             (:p :class "search-result-count"
               (format nil "~A result~:P" (length hits)))
             (dolist (post hits)
               (let* ((post-id  (strata.models.post:post-field post "_id"))
                      (body     (strata.models.post:post-field post "body"))
                      (pk       (strata.models.post:post-field post "kind"))
                      (status   (strata.models.post:post-field post "status"))
                      (ts       (strata.models.post:post-field post "created_at")))
                 (:article :class "inbox-item"
                   (:div :class "inbox-item-meta"
                     (:span :class (format nil "post-kind-badge post-kind-~A" pk) pk)
                     (unless (string= status "open")
                       (:span :class (format nil "post-status-badge post-status-~A" status) status))
                     (:span :class "post-time" (fmt-time ts)))
                   (:p :class "inbox-item-body" body)
                   (:button :class "post-action-btn"
                            :type "button"
                            :data-on-click (format nil "/action/strata-shell/open-thread?id=~A" post-id)
                            "Open thread")))))))))))

;;; -------------------------------------------------------
;;; Actions
;;; -------------------------------------------------------

(fluxion.components:defaction search-component :search (self params)
  "Run a full-text search and store results in the component."
  (let* ((q    (cdr (assoc "q"    params :test #'string=)))
         (kind (cdr (assoc "kind" params :test #'string=))))
    (setf (search-query-text self)  (or q "")
          (search-kind-filter self) (or kind ""))
    (when (and q (plusp (length (string-trim '(#\Space #\Tab) q))))
      (let ((hits (handler-case
                      (strata.models.post:search-posts
                       (string-trim '(#\Space #\Tab) q))
                    (error () nil))))
        (setf (search-results self)
              (if (and kind (plusp (length kind)))
                  (remove-if-not
                   (lambda (p)
                     (string= (strata.models.post:post-field p "kind") kind))
                   hits)
                  hits)))))
  (fluxion.components:patch-component self))

;;; -------------------------------------------------------
;;; Page renderer
;;; -------------------------------------------------------

(defun make-search ()
  "Create a fresh search-component instance."
  (make-instance 'search-component))

(defun render-search-page (session)
  "Render the full search HTML page for SESSION."
  (let* ((sc   (fluxion.server:session-component session "strata-search"))
         (csrf (fluxion.server:session-csrf-token session)))
    (unless sc
      (error "[strata] search component not found in session"))
    (fluxion.render:render-page
     :title "Search - Strata"
     :head-html (format nil
                  "<script src=\"/static/js/theme.js\"></script>~
                   <link rel=\"stylesheet\" href=\"/static/css/strata.css\">")
     :csrf-token csrf
     :body-html  (fluxion.components:render sc)
     :script-path "/static/fluxion.js")))
