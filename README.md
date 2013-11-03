highlight-symbol.el
===================

automatic and manual symbol highlighting for Emacs

[![Build Status](https://travis-ci.org/nschum/highlight-symbol.el.png?branch=master)](https://travis-ci.org/nschum/highlight-symbol.el)

Add the following to your .emacs file:

    (require 'highlight-symbol)
    (global-set-key [(control f3)] 'highlight-symbol-at-point)
    (global-set-key [f3] 'highlight-symbol-next)
    (global-set-key [(shift f3)] 'highlight-symbol-prev)
    (global-set-key [(meta f3)] 'highlight-symbol-query-replace)

Use `highlight-symbol-at-point` to toggle highlighting of the symbol at
point throughout the current buffer.  Use `highlight-symbol-mode` to keep the
symbol at point highlighted.

The functions `highlight-symbol-next`, `highlight-symbol-prev`,
`highlight-symbol-next-in-defun` and `highlight-symbol-prev-in-defun` allow for
cycling through the locations of any symbol at point.  Use
`highlight-symbol-nav-mode` to enable key bindings (<key>M-p</key> and
<key>M-p</key>) for navigation.  When `highlight-symbol-on-navigation-p` is set,
highlighting is triggered regardless of `highlight-symbol-idle-delay`.

`highlight-symbol-query-replace` can be used to replace the symbol.
