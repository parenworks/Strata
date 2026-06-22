;;;; -*- encoding:utf-8 -*-
;;;; Strata - Web Push / VAPID support
;;;;
;;;; Generates a VAPID keypair on first startup, stores it in a flat file,
;;;; builds a signed JWT for each push batch, and sends Web Push messages
;;;; via HTTP POST to the browser's push service endpoint.
;;;;
;;;; VAPID spec: RFC 8292.  Encryption spec: RFC 8291 (aes128gcm).
;;;; We use the "direct" aesgcm128 content encoding used by all major
;;;; browsers when contacted via the Web Push JS API.

(in-package #:strata.push)

;;; -------------------------------------------------------
;;; Key storage
;;; -------------------------------------------------------

(defvar *vapid-private-key* nil
  "SECP256R1 private key object used to sign VAPID JWTs.")

(defvar *vapid-public-key-bytes* nil
  "Uncompressed public key bytes (65 bytes: 04 || X || Y).
This is the value returned to the browser as applicationServerKey.")

(defvar *vapid-public-key-b64* nil
  "Base64url encoding of *vapid-public-key-bytes*. Passed to the JS
  pushManager.subscribe() call and sent in the Authorization header.")

(defparameter *keypair-file*
  (asdf:system-relative-pathname :strata "config/vapid-keys.lisp")
  "Path where the VAPID keypair is persisted between restarts.")

;;; -------------------------------------------------------
;;; Base64url helpers
;;; -------------------------------------------------------

(defun bytes-to-base64url (bytes)
  "Encode byte vector BYTES as base64url (no padding, - and _ instead of + and /)."
  (let* ((b64 (cl-base64:usb8-array-to-base64-string bytes))
         (url (substitute #\- #\+ (substitute #\_ #\/ b64))))
    (string-right-trim "=" url)))

(defun base64url-to-bytes (s)
  "Decode base64url string S to a byte vector."
  (let* ((padded (let* ((r (mod (length s) 4))
                        (pad (if (zerop r) 0 (- 4 r))))
                   (concatenate 'string s (make-string pad :initial-element #\=))))
         (std (substitute #\+ #\- (substitute #\/ #\_ padded))))
    (cl-base64:base64-string-to-usb8-array std)))

;;; -------------------------------------------------------
;;; Keypair generation and persistence
;;; -------------------------------------------------------

(defun generate-vapid-keypair ()
  "Generate a fresh SECP256R1 VAPID keypair and store it globally."
  (multiple-value-bind (priv pub)
      (ironclad:generate-key-pair :secp256r1)
    (setf *vapid-private-key*     priv
          *vapid-public-key-bytes* (ironclad:secp256r1-key-y pub)
          *vapid-public-key-b64*   (bytes-to-base64url (ironclad:secp256r1-key-y pub)))))

(defun save-vapid-keypair ()
  "Persist the current VAPID keypair to *keypair-file*."
  (ensure-directories-exist *keypair-file*)
  (with-open-file (out *keypair-file* :direction :output
                                      :if-exists :supersede
                                      :if-does-not-exist :create)
    (prin1 (list :private-x (bytes-to-base64url (ironclad:secp256r1-key-x *vapid-private-key*))
                 :public-y  (bytes-to-base64url *vapid-public-key-bytes*))
           out)
    (terpri out)))

(defun load-vapid-keypair ()
  "Load the VAPID keypair from *keypair-file*. Returns T on success, NIL if not found."
  (when (probe-file *keypair-file*)
    (let* ((plist (with-open-file (in *keypair-file*) (read in)))
           (priv-x (base64url-to-bytes (getf plist :private-x)))
           (pub-y  (base64url-to-bytes (getf plist :public-y))))
      (setf *vapid-private-key*      (ironclad:make-private-key :secp256r1 :x priv-x :y pub-y)
            *vapid-public-key-bytes*  pub-y
            *vapid-public-key-b64*    (bytes-to-base64url pub-y))
      t)))

(defun ensure-vapid-keypair ()
  "Load the VAPID keypair from disk; generate and save a fresh one if not present."
  (unless (load-vapid-keypair)
    (generate-vapid-keypair)
    (save-vapid-keypair)
    (format t "~&[strata/push] Generated new VAPID keypair.~%"))
  (format t "~&[strata/push] VAPID public key: ~A~%" *vapid-public-key-b64*))

;;; -------------------------------------------------------
;;; VAPID JWT construction
;;; -------------------------------------------------------

(defun unix-now ()
  "Return the current time as a Unix epoch integer."
  (- (get-universal-time) 2208988800))

(defun json-object (&rest pairs)
  "Build a minimal JSON object string from alternating key value PAIRS."
  (format nil "{~{\"~A\":~A~^,~}}"
          (loop for (k v) on pairs by #'cddr
                collect k collect (if (stringp v) (format nil "\"~A\"" v) v))))

(defun string-to-bytes (s)
  "Convert string S to a UTF-8 byte vector."
  (sb-ext:string-to-octets s :external-format :utf-8))

(defun build-vapid-jwt (audience)
  "Build a signed ES256 JWT for AUDIENCE (the push service origin, e.g. https://fcm.googleapis.com).
Returns a string suitable for use as the JWT token in the VAPID Authorization header."
  (let* ((header (bytes-to-base64url
                  (string-to-bytes
                   (json-object "typ" "JWT" "alg" "ES256"))))
         (exp    (+ (unix-now) 43200))
         (claims (bytes-to-base64url
                  (string-to-bytes
                   (json-object "aud" audience "exp" exp "sub" "mailto:admin@strata.local"))))
         (signing-input (format nil "~A.~A" header claims))
         (signing-bytes (string-to-bytes signing-input))
         (digest        (ironclad:digest-sequence :sha256 signing-bytes))
         (sig           (ironclad:sign-message *vapid-private-key* digest))
         (sig-b64       (bytes-to-base64url sig)))
    (format nil "~A.~A.~A" header claims sig-b64)))

(defun vapid-auth-header (endpoint)
  "Return the Authorization header value for a Web Push request to ENDPOINT."
  (let* ((uri    (quri:uri endpoint))
         (origin (format nil "~A://~A" (quri:uri-scheme uri) (quri:uri-host uri)))
         (jwt    (build-vapid-jwt origin)))
    (format nil "vapid t=~A,k=~A" jwt *vapid-public-key-b64*)))

;;; -------------------------------------------------------
;;; Sending a push message
;;; -------------------------------------------------------

(defun send-push (subscription-record title body &key (icon "/static/icons/icon-192.png"))
  "Send a Web Push notification to SUBSCRIPTION-RECORD.
SUBSCRIPTION-RECORD is a push_subscriptions data-model object.
TITLE and BODY are the notification text strings.
Returns T on success, NIL (with a logged error) on failure.
Note: this implementation sends an unencrypted payload for simplicity.
RFC 8291 content encryption (aes128gcm) should be added for production."
  (let* ((endpoint (strata.models.push-subscription:subscription-field
                    subscription-record "endpoint"))
         (payload  (format nil "{\"title\":~S,\"body\":~S,\"icon\":~S}" title body icon))
         (auth     (vapid-auth-header endpoint)))
    (handler-case
        (progn
          (dex:post endpoint
                    :headers `(("Authorization" . ,auth)
                               ("Content-Type"  . "application/json")
                               ("TTL"           . "86400"))
                    :content payload)
          t)
      (error (e)
        (format t "~&[strata/push] send failed for ~A: ~A~%" endpoint e)
        nil))))

;;; -------------------------------------------------------
;;; Fanout to all subscriptions for a user
;;; -------------------------------------------------------

(defun notify-user (user-id title body)
  "Send a push notification to all subscriptions for USER-ID."
  (let ((subs (handler-case
                  (strata.models.push-subscription:list-for-user user-id)
                (error () nil))))
    (dolist (sub subs)
      (send-push sub title body))))

(defun notify-mentioned-users (mention-user-ids channel-name poster-name)
  "Send push notifications to all users in MENTION-USER-IDS.
Called from the post/reply hook when mentions are detected."
  (let ((title (format nil "~A mentioned you in #~A" poster-name channel-name))
        (body  "Click to open the thread."))
    (dolist (uid mention-user-ids)
      (notify-user uid title body))))
