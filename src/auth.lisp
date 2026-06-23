;;;; -*- encoding:utf-8 -*-
;;;; Strata - Auth helpers

(in-package #:strata.auth)

(defun setup-user-tables ()
  "Ensure fluxion.user tables exist. Idempotent; call during app startup."
  (user:setup))

(defun any-users-p ()
  "Return T if at least one user exists in the database, NIL otherwise.
Used by the page handler guard to decide whether to redirect to /setup."
  (not (null (user:list-users))))

(defun user-display-name (user-alist)
  "Return a human-readable name for USER-ALIST.
Tries the display_name extensible field first, then falls back to username."
  (when user-alist
    (let ((uid (user:user-id user-alist))
          (username (user:user-username user-alist)))
      (or (when uid
            (handler-case
                (user:field uid "display_name")
              (error () nil)))
          username
          "User"))))

(defun user-id-from-session (session)
  "Return the integer user ID from SESSION, or 0 if not authenticated."
  (let ((u (fx:session-user session)))
    (if u (or (user:user-id u) 0) 0)))

(defun user-disabled-p (username)
  "Return T if USERNAME has been disabled by an administrator."
  (let ((uid (user:user-id username)))
    (when uid
      (string= "1" (handler-case (user:field uid "disabled")
                     (error () nil))))))

(defun disable-user (username)
  "Mark USERNAME as disabled so they cannot log in."
  (let ((uid (user:user-id username)))
    (unless uid (error "User not found: ~A" username))
    (user:set-field uid "disabled" "1")))

(defun enable-user (username)
  "Re-enable a previously disabled user."
  (let ((uid (user:user-id username)))
    (unless uid (error "User not found: ~A" username))
    (user:set-field uid "disabled" "0")))

(defun is-admin-p (username)
  "Return T if USERNAME has the admin permission."
  (handler-case (user:check username "admin")
    (error () nil)))

(defun get-user-by-id (user-id)
  "Return the user alist for integer USER-ID, or NIL if not found."
  (handler-case
      (fluxion.db:select-one "fluxion_users"
                             (fluxion.db:compile-query `(:= _id ,user-id)))
    (error () nil)))

(defun update-password (username new-password)
  "Update the password hash for USERNAME to a hash of NEW-PASSWORD.
Verification of the current password must be done by the caller before
invoking this function."
  (let ((uid (user:user-id username)))
    (unless uid
      (error "User not found: ~A" username))
    (fluxion.db:update "fluxion_users"
                       (fluxion.db:compile-query `(:= _id ,uid))
                       `(("password_hash" . ,(user:hash-password new-password))))))
