;;; color-theme-buffer-local.el --- Install color themes by buffer.
;;; Version: 0.0.1
;;; Author: Victor Borja <vic.borja@gmail.com>
;;; URL: http://github.com/vic/color-theme-buffer-local
;;; Description: Set color-theme by buffer.
;;; 

;;;
;;; Usage for color-theme.el themes:
;;;
;;; (add-hook 'java-mode-hook (lambda nil
;;;   (color-theme-buffer-local 'color-theme-robin-hood (current-buffer))))
;;;
;;; Usage for emacs24 builtin themes:
;;;
;;;
;;; (add-hook 'java-mode-hook (lambda nil
;;;   (load-theme-buffer-local 'misterioso (current-buffer))))



(defun color-theme-buffer-local-install-variables (vars buffer)
  (with-current-buffer buffer
    (let ((vars (color-theme-filter vars color-theme-legal-variables)))
      (dolist (var vars)
        (set (make-variable-buffer-local (car var)) (cdr var))))))

(defun color-theme-buffer-local-reset-faces (buffer)
  (with-current-buffer buffer
    (dolist (face (color-theme-get-faces))
      (make-variable-buffer-local 'face-remapping-alist)
      (face-remap-reset-base face))))


(defun color-theme-buffer-local-spec-compat (spec)
    (let ((props (cadar spec)))
      ;; remove stipple attribute because it causes error :( FIXME
      (when (plist-member props :stipple)
        (setq props (color-theme-plist-delete props :stipple)))
      `((t ,props))))

(defun color-theme-buffer-local-install-face (face spec)
  (or (facep face)
      (make-empty-face face))
  ;; remove weird properties from the default face only
  (when (eq face 'default)
    (setq spec (color-theme-spec-filter spec)))
  ;; Emacs/XEmacs customization issues: filter out :bold when
  ;; the spec contains :weight, etc, such that the spec remains
  ;; "valid" for custom.
  (setq spec (color-theme-spec-compat spec))
  ;; using a spec of ((t (nil))) to reset a face doesn't work
  ;; in Emacs 21, we use the new function face-spec-reset-face
  ;; instead

  (setq spec (color-theme-buffer-local-spec-compat spec))

  (if (eq 'default face)
      (buffer-face-set (cadar spec)))

  (face-remap-set-base face (cadar spec)))

(defvar color-theme-buffer-local-face-alias
  '(
    (modeline . mode-line)
    (modeline-buffer-id . mode-line-buffer-id)
    (modeline-mousable . mode-line-mousable)
    ))

(defun color-theme-buffer-local-install-faces (faces buffer)
  (with-current-buffer buffer
    (make-variable-buffer-local 'face-remapping-alist)
    (when (not color-theme-is-cumulative)
          (color-theme-buffer-local-reset-faces buffer))
    (let ((faces (color-theme-filter faces color-theme-illegal-faces t)))
      (dolist (entry faces)
        (let ((face (nth 0 entry)) (spec (nth 1 entry)))
          (color-theme-buffer-local-install-face face spec)))

      (dolist (alias color-theme-buffer-local-face-alias)
        (when (and (assoc (car alias) faces)
                   (not (assoc (cdr alias) faces)))
          (color-theme-buffer-local-install-face
           (cdr alias)
           (cadr (assoc (car alias) faces)))))
      )))


(defun color-theme-buffer-local-install-params (params buffer)
  (setq params (color-theme-filter
		params color-theme-legal-frame-parameters))
  (make-variable-buffer-local 'buffer-face-mode-face)
  (let (default) 
    (dolist (param params)
      (when (eq (car param) 'foreground-color)
        (setq default (append default (list :foreground (cdr param)))))
      (when (eq (car param) 'background-color)
        (setq default (append default (list :background (cdr param)))))
    )
    (when default
      (setq default (append (if (listp buffer-face-mode-face)
                                (cddr buffer-face-mode-face)
                              (list buffer-face-mode-face))
                            (list  default)))
      (funcall 'buffer-face-set default))))
    

(defun color-theme-buffer-local-install (theme buffer)
  (setq theme (color-theme-canonic theme))
  (with-current-buffer buffer 
    (color-theme-buffer-local-install-variables (color-theme-variables theme) buffer)
    (color-theme-buffer-local-install-faces (color-theme-faces theme) buffer)
    (color-theme-buffer-local-install-params (color-theme-frame-params theme)
                                             buffer)))


;;;###autoload
(defun color-theme-buffer-local (theme &optional buffer)
  "Install the color-theme defined by THEME on BUFFER.

   THEME must be a symbol whose value as a function calls
   `color-theme-install' to install a theme.

   BUFFER defaults to the current buffer if not explicitly given."
  (interactive
   (list (intern (ido-completing-read "Install color-theme: "
                                       (mapcar 'symbol-name
                                               (mapcar 'car color-themes))))
         (ido-read-buffer "on Buffer: " (current-buffer) t)))
  (flet ((color-theme-install (theme)
                              (color-theme-buffer-local-install
                               theme (or buffer (current-buffer)))))
    (funcall theme))) 

(defun custom-theme-buffer-local-set-face (buffer face spec &optional base)
  (with-current-buffer buffer
    (make-variable-buffer-local 'face-remapping-alist)
    (let* ((spec (face-spec-choose spec))
           attrs)
      (while spec
        (when (assq (car spec) face-x-resources)
          (push (car spec) attrs)
          (push (cadr spec) attrs))
        (setq spec (cddr spec)))
      (setq attrs (nreverse attrs))
      (if (and (eq 'default face) base)
          (buffer-face-set attrs))
      (funcall
       (if base 'face-remap-set-base 'face-remap-add-relative)
       face attrs))))


(defun custom-theme-buffer-local-recalc-face (face buffer)
  (with-current-buffer buffer
    
    (if (get face 'face-alias)
        (setq face (get face 'face-alias)))
    
    ;; first set the default spec
    (or (get face 'customized-face)
        (get face 'saved-face)
        (custom-theme-buffer-local-set-face
         buffer face (face-default-spec face) t))

    (let ((theme-faces (reverse (get face 'theme-face))))
      (dolist (spec theme-faces)
        (custom-theme-buffer-local-set-face buffer face (cadr spec))))

    (and (get face 'face-override-spec)
         (custom-theme-buffer-local-set-faceface-remap-add-relative
          buffer face (get face 'face-override-spec)))))

(defun custom-theme-buffer-local-recalc-variable (variable buffer)
  (with-current-buffer buffer
    (make-variable-buffer-local variable)
    (let ((valspec (custom-variable-theme-value variable)))
      (if valspec
          (put variable 'saved-value valspec)
        (setq valspec (get variable 'standard-value)))
      (if (and valspec
               (or (get variable 'force-value)
                   (default-boundp variable)))
          (funcall (or (get variable 'custom-set) 'set-default) variable
                   (eval (car valspec)))))))


;;;###autoload
(defun load-theme-buffer-local (theme &optional buffer)
  "Load an Emacs24 THEME only in BUFFER."
  (interactive
   (list (intern (ido-completing-read
                  "Install theme: "
                  (mapcar 'symbol-name (custom-available-themes))))
         (ido-read-buffer "on Buffer: " (current-buffer) t)))
  (or buffer (setq buffer (current-buffer)))
  (flet ((custom-theme-recalc-face
          (symbol) (custom-theme-buffer-local-recalc-face symbol buffer))
         (custom-theme-recalc-variable
          (symbol) (custom-theme-buffer-local-recalc-variable symbol buffer)))
    (load-theme theme)))


(provide 'color-theme-buffer-local)

;;; color-theme-buffer-local.el ends here
