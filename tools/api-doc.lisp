;;;; tools/api-doc.lisp
;;;;
;;;; Walks Strata's own packages and writes an Org-mode API reference to
;;;; docs/API.org. Every exported symbol gets its signature and docstring.
;;;; Symbols with no docstring are flagged so gaps are immediately visible.
;;;;
;;;; Usage (from the Strata project root, system already loadable):
;;;;
;;;;   sbcl --non-interactive \
;;;;     --eval '(asdf:load-system :strata)' \
;;;;     --load tools/api-doc.lisp \
;;;;     --eval '(strata/tools/api-doc:generate)'

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-introspect))

(defpackage #:strata/tools/api-doc
  (:use #:cl)
  (:export #:generate))

(in-package #:strata/tools/api-doc)

(defparameter *package-prefix* "STRATA."
  "Only packages whose name begins with this prefix are documented.")

(defparameter *default-output*
  (asdf:system-relative-pathname :strata "docs/API.org")
  "Where GENERATE writes the reference when no path is supplied.")

(defparameter *category-order*
  '((:class             . "Classes")
    (:condition         . "Conditions")
    (:generic-function  . "Generic functions")
    (:function          . "Functions")
    (:macro             . "Macros")
    (:variable          . "Variables")
    (:constant          . "Constants"))
  "The categories emitted per package, in the order they appear in the output.")

(defun documented-packages (&optional (prefix *package-prefix*))
  "Return Strata's own packages sorted by name, excluding test packages.
Tests are excluded because the reference documents the public API, not the
suite that exercises it."
  (sort
   (remove-if-not
    (lambda (package)
      (let ((name (package-name package)))
        (and (uiop:string-prefix-p prefix name)
             (not (search ".TESTS." name))
             (not (uiop:string-suffix-p ".TESTS" name)))))
    (list-all-packages))
   #'string< :key #'package-name))

(defun external-symbols (package)
  "Return all external symbols of PACKAGE sorted by name."
  (let ((syms '()))
    (do-external-symbols (s package)
      (push s syms))
    (sort syms #'string< :key #'symbol-name)))

(defun classify (symbol)
  "Classify SYMBOL into one API category keyword, or NIL when it fits none.
Categories are mutually exclusive and tested in priority order so that a macro
is never also reported as a function."
  (cond
    ((and (fboundp symbol) (macro-function symbol))        :macro)
    ((and (fboundp symbol)
          (typep (fdefinition symbol) 'generic-function))  :generic-function)
    ((fboundp symbol)                                      :function)
    ((and (find-class symbol nil)
          (subtypep symbol 'condition))                    :condition)
    ((find-class symbol nil)                               :class)
    ((and (boundp symbol) (constantp symbol))              :constant)
    ((boundp symbol)                                       :variable)
    (t nil)))

(defun render-lambda-list (form)
  "Render FORM as a readable lambda-list string.
Symbols print without package qualifiers; keywords keep their leading colon;
nested lists are rendered recursively; other literals print readably."
  (with-output-to-string (out)
    (labels ((render (x)
               (cond
                 ((keywordp x)
                  (format out ":~A" (string-downcase (symbol-name x))))
                 ((symbolp x)
                  (write-string (string-downcase (symbol-name x)) out))
                 ((consp x)
                  (write-char #\( out)
                  (loop for (item . rest) on x do
                    (render item)
                    (when rest (write-char #\Space out)))
                  (write-char #\) out))
                 (t (format out "~(~S~)" x)))))
      (render form))))

(defun signature-string (symbol kind)
  "Return a lowercase lambda-list string for SYMBOL, or NIL when inapplicable.
Variables and constants have no lambda list and return NIL."
  (when (member kind '(:function :macro :generic-function))
    (handler-case
        (render-lambda-list
         (cons symbol (sb-introspect:function-lambda-list symbol)))
      (error ()
        (string-downcase (symbol-name symbol))))))

(defun docstring-for (symbol kind)
  "Return the docstring for SYMBOL in the context of KIND, or NIL if absent."
  (case kind
    ((:function :macro :generic-function) (documentation symbol 'function))
    ((:class :condition)                  (documentation (find-class symbol) t))
    ((:variable :constant)                (documentation symbol 'variable))))

(defun write-symbol (stream symbol kind)
  "Write one symbol entry to STREAM: a level-3 heading, signature, and docstring.
Exported symbols with no docstring are marked /Undocumented/ so gaps are visible."
  (format stream "~%*** =~A=~%" (string-downcase (symbol-name symbol)))
  (let ((sig (signature-string symbol kind)))
    (when sig
      (format stream "~%#+begin_example~%~A~%#+end_example~%" sig)))
  (let ((doc (docstring-for symbol kind)))
    (if doc
        (format stream "~%~A~%" doc)
        (format stream "~%/Undocumented: this exported symbol needs a docstring./~%"))))

(defun write-package (stream package)
  "Write one package section to STREAM, grouping exported symbols by category."
  (format stream "~%* Package =~A=~%"
          (string-downcase (package-name package)))
  (let ((syms (external-symbols package))
        (by-kind (make-hash-table)))
    (if (null syms)
        (format stream "~%(no exported symbols)~%")
        (progn
          (dolist (s syms)
            (let ((k (classify s)))
              (when k (push s (gethash k by-kind)))))
          (loop for (kind . heading) in *category-order*
                for members = (nreverse (gethash kind by-kind))
                when members do
                  (format stream "~%** ~A~%" heading)
                  (dolist (s members)
                    (write-symbol stream s kind)))))))

(defun generate (&optional (output *default-output*))
  "Walk all Strata packages and write an Org API reference to OUTPUT.
The strata system must already be loaded so its packages exist to be
introspected. Returns the truename of the written file."
  (ensure-directories-exist output)
  (with-open-file (stream output :direction :output
                                 :if-exists :supersede
                                 :if-does-not-exist :create)
    (format stream "#+title: Strata API Reference~%")
    (format stream "#+author: Generated by tools/api-doc.lisp~%")
    (format stream "#+startup: showall~%")
    (format stream "#+options: toc:2~%~%")
    (format stream "This file is generated automatically. Do not edit by hand.~%")
    (format stream "Run the generator to refresh it:~%~%")
    (format stream "#+begin_example~%")
    (format stream "sbcl --non-interactive \\~%")
    (format stream "  --eval '(asdf:load-system :strata)' \\~%")
    (format stream "  --load tools/api-doc.lisp \\~%")
    (format stream "  --eval '(strata/tools/api-doc:generate)'~%")
    (format stream "#+end_example~%~%")
    (format stream "Entries marked /Undocumented/ are exported symbols that still~%")
    (format stream "need a docstring added.~%")
    (dolist (package (documented-packages))
      (write-package stream package)))
  (format t "~&Wrote ~A~%" (truename output))
  (truename output))
