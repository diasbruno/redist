#|
 This file is a part of Redist
 (c) 2021 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.redist)

(defvar *default-output-directory* #p "~/dist/releases/")

(defun write-dist-index (release stream)
  (format stream "name: ~(~a~)
version: ~a
system-index-url: ~a
release-index-url: ~a
archive-base-url: ~a
canonical-distinfo-url: ~a
distinfo-subscription-url: ~a
available-versions-url: ~a"
          (name (dist release))
          (version release)
          (systems-url release)
          (releases-url release)
          (url (dist release))
          (dist-url release)
          (dist-url (dist release))
          (releases-url (dist release))))

(defun write-dist-releases-index (dist stream)
  (dolist (release (releases dist))
    (format stream "~a ~a~%" (version release) (dist-url release))))

(defun write-release-index (release output stream)
  (format stream "# project url size file-md5 content-sha1 prefix [system-file1...system-fileN]~%")
  (dolist (project (projects release))
    (let ((file (merge-pathnames (path project) output)))
      (format stream "~a ~a ~a ~a ~a ~a~{ ~a~}~%"
              (name project)
              (url project)
              (file-size file)
              (digest file :md5)
              (digest (source-files project) :sha1)
              (prefix project)
              (remove-duplicates (loop for system in (systems project) collect (file-namestring (file system))) :test #'string=)))))

(defun write-system-index (release stream)
  (format stream "# project system-file system-name [dependency1..dependencyN]~%")
  (dolist (project (projects release))
    (dolist (system (systems project))
      (format stream "~a ~a ~a~{ ~a~}~%"
              (name project) (pathname-name (file system)) (name system)
              (dependencies system)))))

(defgeneric compile (thing &key))

(defmethod compile ((name symbol) &rest args &key &allow-other-keys)
  (apply #'compile (dist name) args))

(defmethod compile ((dist dist) &rest args &key (version (next-version dist)) update verbose (projects NIL projects-p) (output *default-output-directory*) (if-exists :supersede) &allow-other-keys)
  (remf args :update)
  (remf args :version)
  (remf args :projects)
  (let ((release (if projects-p
                     (make-release dist :update update :version version :verbose verbose :projects projects)
                     (make-release dist :update update :version version :verbose verbose)))
        (success NIL))
    (unwind-protect
         (multiple-value-prog1 (apply #'compile release args)
           (flet ((f (path)
                    (ensure-directories-exist (merge-pathnames path output))))
             (with-open-file (stream (f (dist-path dist))
                                     :direction :output
                                     :if-exists if-exists)
               (write-dist-index release stream))
             (with-open-file (stream (f (releases-path dist))
                                     :direction :output
                                     :if-exists if-exists)
               (write-dist-releases-index release stream)))
           (setf success T))
      ;; We did not return successfully, so remove the release again.
      (unless success
        ;; FIXME: add delete command to remove files as well.
        ;;        need to be careful to not remove files from shared releases
        (setf (releases dist) (remove release (releases dist)))))))

(defmethod compile ((release release) &key (output *default-output-directory*) (if-exists :supersede) verbose)
  (ensure-directories-exist output)
  ;; Assemble files from new releases
  (dolist (project (projects release))
    (when (or (equal (version release) (version project))
              (not (probe-file (merge-pathnames (path project) output))))
      (compile project :output output :if-exists if-exists :verbose verbose)))
  (flet ((f (path)
           (ensure-directories-exist (merge-pathnames path output))))
    (with-open-file (stream (f (dist-path release))
                            :direction :output
                            :if-exists if-exists)
      (write-dist-index release stream))
    (with-open-file (stream (f (releases-path release))
                            :direction :output
                            :if-exists if-exists)
      (write-release-index release output stream))
    (with-open-file (stream (f (systems-path release))
                            :direction :output
                            :if-exists if-exists)
      (write-system-index release stream))))

(defmethod compile ((release project-release) &key (output *default-output-directory*) (if-exists :supersede) verbose)
  (when verbose
    (verbose "Compiling ~a" (name (project release))))
  (handler-bind ((error (lambda (e)
                          (when verbose
                            (verbose "~a" e))
                          (continue e))))
    (tgz (source-files release) (ensure-directories-exist (merge-pathnames (path release) output))
         :base (source-directory (project release)) :if-exists if-exists)))
