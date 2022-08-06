#|
 This file is a part of Redist
 (c) 2021 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.redist)

(defun tar (files output &key (if-exists :error) (base #p"/"))
  (archive:with-open-archive (archive output
                              :direction :output
                              :if-exists if-exists)
    (let* ((base (truename base))
           (*default-pathname-defaults* base))
      (dolist (file files)
        (with-simple-restart (continue "Ignore the failing file.")
          (let ((entry (archive:create-entry-from-pathname archive (pathname-utils:enough-pathname file base))))
            (with-open-file (stream file
                                    :direction :input
                                    :element-type '(unsigned-byte 8)
                                    :if-does-not-exist :error)
              (archive:write-entry-to-archive archive entry :stream stream))))))
    (archive:finalize-archive archive)
    output))

(defun gz (file output &key (if-exists :error))
  (salza2:gzip-file file output :if-exists if-exists))

(defun tgz (files output &key (if-exists :error) (base #p"/"))
  (let ((tar (make-pathname :type "tar" :defaults output)))
    (tar files tar :if-exists :error :base base)
    (unwind-protect
         (gz tar output :if-exists if-exists)
      (delete-file tar))))

(defun enlist (list &rest els)
  (if (listp list) list (list* list els)))

(defun digest (file/s digest)
  (let ((digest (ironclad:make-digest digest)))
    (dolist (file (enlist file/s) (ironclad:byte-array-to-hex-string
                                   (ironclad:produce-digest digest)))
      (with-open-file (stream file :element-type '(unsigned-byte 8) :if-does-not-exist NIL)
        (when stream
          (ironclad:update-digest digest stream))))))

(defun file-size (file)
  (with-open-file (stream file :element-type '(unsigned-byte 8))
    (file-length stream)))

(defun tempfile ()
  (make-pathname :name (format NIL "~36r-~36r" (get-universal-time) (random #xFFFFFFFFFFFFFFFF))
                 :type "dat"
                 :defaults (uiop:temporary-directory)))

(defun file-match-p (file pattern)
  (let ((file (uiop:unix-namestring file))
        (string (uiop:unix-namestring pattern)))
    (if (pathname-utils:absolute-p pattern)
        (starts-with string file :start1 1)
        (loop for i = -1 then (position #\/ file :start i)
              while i
              thereis (progn (incf i) (starts-with string file :start2 i))))))

(defun gather-sources (base &optional exclude)
  (let ((base (truename base)))
    (loop for file in (directory (merge-pathnames (make-pathname :name :wild :type :wild :directory '(:relative :wild-inferiors)) base))
          for relative = (pathname-utils:enough-pathname file base)
          when (and (filesystem-utils:file-p file)
                    (not (loop for excluded in exclude
                               thereis (file-match-p relative excluded))))
          collect file)))

(defun ensure-instance (instance type &rest initargs)
  (cond ((null instance)
         (apply #'make-instance type initargs))
        ((eql type (type-of instance))
         (apply #'reinitialize-instance instance initargs))
        (T
         (apply #'change-class instance type initargs))))

(defun split (split string)
  (let ((parts ()) (buffer (make-string-output-stream)))
    (flet ((maybe-output ()
             (let ((part (get-output-stream-string buffer)))
               (when (string/= part "") (push part parts)))))
      (loop for char across string
            do (if (char= char split)
                   (maybe-output)
                   (write-char char buffer))
            finally (maybe-output))
      (nreverse parts))))

(defun ends-with (end string)
  (and (<= (length end) (length string))
       (string= end string :start2 (- (length string) (length end)))))

(defun starts-with (start string &key (start1 0) (start2 0))
  (and (<= (- (length start) start1) (- (length string) start2))
       (string= start string :start1 start1 :start2 start2 :end2 (+ start2 (- (length start) start1)))))

(defun url-encode (thing &key (stream NIL) (external-format :utf-8) (allowed "-._~"))
  (flet ((%url-encode (stream)
           (loop for octet across (babel:string-to-octets thing :encoding external-format)
                 for char = (code-char octet)
                 do (cond ((or (char<= #\0 char #\9)
                               (char<= #\a char #\z)
                               (char<= #\A char #\Z)
                               (find char allowed :test #'char=))
                           (write-char char stream))
                          (T (format stream "%~2,'0x" (char-code char)))))))
    (if stream
        (%url-encode stream)
        (with-output-to-string (stream)
          (%url-encode stream)))))

(defun run (command &rest args)
  (loop (with-simple-restart (retry "Retry running the program")
          (return (simple-inferiors:run #-windows command #+windows (format NIL "~a.exe" command)
                                        args :on-non-zero-exit :error)))))

(defun run-string (command &rest args)
  (loop (with-simple-restart (retry "Retry running the program")
          (return (string-right-trim '(#\Return #\Linefeed #\Space)
                                     (simple-inferiors:run #-windows command #+windows (format NIL "~a.exe" command)
                                                           args :on-non-zero-exit :error :output :string))))))

(defun prune-plist (plist)
  (loop for (k v) on plist by #'cddr
        when v collect k
        when v collect v))

(defun verbose (format &rest args)
  (format *error-output* "~&; ~?~%" format args))
