;;; highlight-symbol.el --- automatic and manual symbol highlighting
;;
;; Copyright (C) 2007-2009 Nikolaj Schumacher
;;
;; Author: Nikolaj Schumacher <bugs * nschum de>
;; Version: 1.1
;; Keywords: faces, matching
;; URL: http://nschum.de/src/emacs/highlight-symbol/
;; Compatibility: GNU Emacs 22.x, GNU Emacs 23.x
;;
;; This file is NOT part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 2
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;; Add the following to your .emacs file:
;; (require 'highlight-symbol)
;; (global-set-key [(control f3)] 'highlight-symbol-at-point)
;; (global-set-key [f3] 'highlight-symbol-next)
;; (global-set-key [(shift f3)] 'highlight-symbol-prev)
;; (global-set-key [(meta f3)] 'highlight-symbol-prev)))
;; (global-set-key [(control meta f3)] 'highlight-symbol-query-replace)
;;
;; Use `highlight-symbol-at-point' to toggle highlighting of the symbol at
;; point throughout the current buffer.  Use `highlight-symbol-mode' to keep the
;; symbol at point highlighted.
;;
;; The functions `highlight-symbol-next', `highlight-symbol-prev',
;; `highlight-symbol-next-in-defun' and `highlight-symbol-prev-in-defun' allow
;; for cycling through the locations of any symbol at point.
;; When `highlight-symbol-on-navigation-p' is set, highlighting is triggered
;; regardless of `highlight-symbol-idle-delay'.
;;
;; `highlight-symbol-query-replace' can be used to replace the symbol.
;;
;;; Change Log:
;;
;; 2009-04-13 (1.1)
;;    Added `highlight-symbol-query-replace'.
;;
;; 2009-03-19 (1.0.5)
;;    Fixed `highlight-symbol-idle-delay' void variable message.
;;    Fixed color repetition bug.  (thanks to Hugo Schmitt)
;;
;; 2008-05-02 (1.0.4)
;;    Added `highlight-symbol-on-navigation-p' option.
;;
;; 2008-02-26 (1.0.3)
;;    Added `highlight-symbol-remove-all'.
;;
;; 2007-09-06 (1.0.2)
;;    Fixed highlighting with delay set to 0.  (thanks to Stefan Persson)
;;
;; 2007-09-05 (1.0.1)
;;    Fixed completely broken temporary highlighting.
;;
;; 2007-07-30 (1.0)
;;    Keep temp highlight while jumping.
;;    Replaced `highlight-symbol-faces' with `highlight-symbol-colors'.
;;    Fixed dependency and Emacs 21 bug.  (thanks to Gregor Gorjanc)
;;    Prevent calling `highlight-symbol-at-point' on nil.
;;
;; 2007-04-20 (0.9.1)
;;    Fixed bug in `highlight-symbol-jump'.  (thanks to Per Nordlöw)
;;
;; 2007-04-06 (0.9)
;;    Initial release.
;;
;;; Code:

(require 'thingatpt)
(require 'hi-lock)
(eval-when-compile (require 'cl))

(push "^No symbol at point$" debug-ignored-errors)

(defgroup highlight-symbol nil
  "Automatic and manual symbols highlighting"
  :group 'faces
  :group 'matching)

(defface highlight-symbol-face
  '((((class color) (background dark))
     (:background "gray30"))
    (((class color) (background light))
     (:background "gray90")))
  "*Face used by `highlight-symbol-mode'."
  :group 'highlight-symbol)

(defvar highlight-symbol-timer nil)

(defun highlight-symbol-update-timer (value)
  (when highlight-symbol-timer
    (cancel-timer highlight-symbol-timer))
  (setq highlight-symbol-timer
        (and value (/= value 0)
             (run-with-idle-timer value t 'highlight-symbol-temp-highlight))))

(defvar highlight-symbol-mode nil)

(defun highlight-symbol-set (symbol value)
  (when symbol (set symbol value))
  (when highlight-symbol-mode
    (highlight-symbol-update-timer value)))

(defcustom highlight-symbol-idle-delay 1.5
  "*Number of seconds of idle time before highlighting the current symbol.
If this variable is set to 0, no idle time is required.
Changing this does not take effect until `highlight-symbol-mode' has been
disabled for all buffers."
  :type 'number
  :set 'highlight-symbol-set
  :group 'highlight-symbol)

(defcustom highlight-symbol-colors
  '("yellow" "DeepPink" "cyan" "MediumPurple1" "SpringGreen1"
    "DarkOrange" "HotPink1" "RoyalBlue1" "OliveDrab")
  "*Colors used by `highlight-symbol-at-point'.
highlighting the symbols will use these colors in order."
  :type '(repeat color)
  :group 'highlight-symbol)

(defcustom highlight-symbol-on-navigation-p nil
  "*Wether or not to temporary highlight the symbol when using
`highlight-symbol-jump' family of functions."
  :type 'boolean
  :group 'highlight-symbol)

(defvar highlight-symbol-color-index 0)
(make-variable-buffer-local 'highlight-symbol-color-index)

(defvar highlight-symbol nil)
(make-variable-buffer-local 'highlight-symbol)

(defvar highlight-symbol-list nil)
(make-variable-buffer-local 'highlight-symbol-list)

(defconst highlight-symbol-border-pattern
  (if (>= emacs-major-version 22) '("\\_<" . "\\_>") '("\\<" . "\\>")))

(defun highlight-symbol-get-prompt ()
  (mapconcat
   'identity
   (let ((case-fold-search nil)
         fg bg)
     (loop for i from 0 below (length highlight-symbol-list)
           for sym in (reverse highlight-symbol-list)
           collect (save-excursion
                     (save-restriction
                       (widen)
                       (goto-char (point-min))
                       (if (re-search-forward sym nil 'no-error)
                           (let ((face-setting (car (get-char-property-and-overlay (1- (point)) 'face))))
                             (if (listp face-setting)
                                 (setq bg (cdr (assq 'background-color face-setting))
                                       fg (cdr (assq 'foreground-color face-setting)))
                               (setq bg nil
                                     fg nil))
                             (propertize
                              sym
                              'face
                              (list :background bg :foreground fg)))
                         (format "(missing: %s)" sym))))))
   ", "))

;;;###autoload
(define-minor-mode highlight-symbol-mode
  "Minor mode that highlights the symbol under point throughout the buffer.
Highlighting takes place after `highlight-symbol-idle-delay'."
  nil " hl-s" nil
  (if highlight-symbol-mode
      ;; on
      (let ((hi-lock-archaic-interface-message-used t))
        (unless hi-lock-mode (hi-lock-mode 1))
        (highlight-symbol-update-timer highlight-symbol-idle-delay)
        (add-hook 'post-command-hook 'highlight-symbol-mode-post-command nil t))
    ;; off
    (remove-hook 'post-command-hook 'highlight-symbol-mode-post-command t)
    (highlight-symbol-mode-remove-temp)
    (kill-local-variable 'highlight-symbol)))

;;;###autoload
(defun highlight-symbol-at-point (arg)
  "Toggle highlighting of the symbol at point.
This highlights or unhighlights the symbol at point using the first
element in of `highlight-symbol-faces'.

With universal arg (C-u), prompt to remove all highlights."
  (interactive "P")
  (if (null arg)
      (let ((symbol (if (use-region-p)
                        (progn
                          (setq deactivate-mark t)
                          (regexp-quote (filter-buffer-substring (region-beginning) (region-end))))
                      (highlight-symbol-get-symbol))))
        (unless hi-lock-mode (hi-lock-mode 1))
        (if (member symbol highlight-symbol-list)
            ;; remove
            (progn
              (setq highlight-symbol-list (delete symbol highlight-symbol-list))
              (hi-lock-unface-buffer symbol))
          ;; add
          (when (equal symbol highlight-symbol)
            (highlight-symbol-mode-remove-temp))
          (let ((color (nth highlight-symbol-color-index
                            highlight-symbol-colors)))
            (if color ;; wrap
                (incf highlight-symbol-color-index)
              (setq highlight-symbol-color-index 1
                    color (car highlight-symbol-colors)))
            (setq color `((background-color . ,color)
                          (foreground-color . "black")))
            ;; highlight
            (with-no-warnings
              (if (< emacs-major-version 22)
                  (hi-lock-set-pattern `(,symbol (0 (quote ,color) t)))
                (hi-lock-set-pattern symbol color)))
            (push symbol highlight-symbol-list))))
    (if (null highlight-symbol-list)
        (message "No symbols currently highlighted.")
      (let ((prompt
             (concat "Unhighlight "
                     (highlight-symbol-get-prompt)
                     "? (y/n)" ))
            (cursor-in-echo-area t)
            input)
        (when (eq (upcase (read-char prompt)) ?Y)
          (highlight-symbol-remove-all))))))

;;;###autoload
(defun highlight-symbol-remove-all ()
  "Remove symbol highlighting in buffer."
  (interactive)
  (mapc 'hi-lock-unface-buffer highlight-symbol-list)
  (setq highlight-symbol-list nil))

;;;###autoload
(defun highlight-symbol-next ()
  "Jump to the next location of the symbol at point within the function."
  (interactive)
  (highlight-symbol-jump 1))

;;;###autoload
(defun highlight-symbol-prev ()
  "Jump to the previous location of the symbol at point within the function."
  (interactive)
  (highlight-symbol-jump -1))

;;;###autoload
(defun highlight-symbol-next-in-defun ()
  "Jump to the next location of the symbol at point within the defun."
  (interactive)
  (save-restriction
    (narrow-to-defun)
    (highlight-symbol-jump 1)))

;;;###autoload
(defun highlight-symbol-prev-in-defun ()
  "Jump to the previous location of the symbol at point within the defun."
  (interactive)
  (save-restriction
    (narrow-to-defun)
    (highlight-symbol-jump -1)))

;;;###autoload
(defun highlight-symbol-query-replace (symbol replacement)
  "*Replace the symbol at point."     
  (interactive (let ((symbol (highlight-symbol-get-symbol)))
                 (highlight-symbol-temp-highlight)
                 (set query-replace-to-history-variable
                      (cons symbol
                            (eval query-replace-to-history-variable)))
                 (list
                  symbol
                  (read-from-minibuffer "Replacement: " nil nil nil
                                        query-replace-to-history-variable))))
  (goto-char (car (highlight-symbol-bounds)))
  (query-replace-regexp symbol replacement))

(defun highlight-symbol-get-symbol ()
  "Return current highlit thing at point or failing that,
return a regular expression dandifying the symbol at point."
  (let* ((bounds (highlight-symbol-bounds))
         (beg (car bounds))
         (end (cdr bounds))
         res)
    (when (and beg end)
      (setq res (let ((str (filter-buffer-substring beg end)))
                  (dolist (regex highlight-symbol-list)
                    (when (string-match regex str)
                      (return regex))))))
    (or res
        (concat (car highlight-symbol-border-pattern)
                (filter-buffer-substring beg end)
                (cdr highlight-symbol-border-pattern)))))

(defun highlight-symbol-temp-highlight ()
  "Highlight the current symbol until a command is executed."
  (when highlight-symbol-mode
    (let ((symbol (highlight-symbol-get-symbol)))
      (unless (or (equal symbol highlight-symbol)
                  (member symbol highlight-symbol-list))
        (highlight-symbol-mode-remove-temp)
        (when symbol
          (setq highlight-symbol symbol)
          (hi-lock-set-pattern symbol 'highlight-symbol-face))))))

(defun highlight-symbol-mode-remove-temp ()
  "Remove the temporary symbol highlighting."
  (when highlight-symbol
    (hi-lock-unface-buffer highlight-symbol)
    (setq highlight-symbol nil)))

(defun highlight-symbol-mode-post-command ()
  "After a command, change the temporary highlighting.
Remove the temporary symbol highlighting and, unless a timeout is specified,
create the new one."
  (if (eq this-command 'highlight-symbol-jump)
      (when highlight-symbol-on-navigation-p
        (highlight-symbol-temp-highlight))
    (if (eql highlight-symbol-idle-delay 0)
        (highlight-symbol-temp-highlight)
      (highlight-symbol-mode-remove-temp))))

(defun highlight-symbol-jump (dir)
  "Jump to the next or previous occurence of the symbol at point.
DIR has to be 1 or -1."
  (let* ((case-fold-search nil)
         (bounds (highlight-symbol-bounds))
         (symbol (highlight-symbol-get-symbol))
         (offset (- (point) (if (< 0 dir) (cdr bounds) (car bounds)))))
    (unless (eq last-command 'highlight-symbol-jump)
      (push-mark))
    ;; move a little, so we don't find the same instance again
    (goto-char (- (point) offset))
    (let ((target (re-search-forward symbol nil t dir)))
      (unless target
        (goto-char (if (< 0 dir) (point-min) (point-max)))
        (setq target (re-search-forward symbol nil nil dir)))
      (goto-char (+ target offset)))
    (setq this-command 'highlight-symbol-jump)
    (setq regexp-search-ring (cons symbol (delete symbol regexp-search-ring)))))

(defun highlight-symbol-bounds ()
  "Return cons (beg . end) of bounds of highlit item."
  (let* ((prop (get-char-property-and-overlay (point) 'face))
         (fg (and (consp (car prop))
                  (cdr (assq 'foreground-color (car prop)))))
         (bg (and (consp (car prop))
                  (cdr (assq 'background-color (car prop))))))
    (if (and fg bg)
        (cons (previous-single-property-change (point) 'face)
              (next-single-property-change (point) 'face))
      (let ((symbol (bounds-of-thing-at-point 'symbol)))
        (or symbol
            (error "No symbol at point"))))))
  

(provide 'highlight-symbol)

;;; highlight-symbol.el ends here
