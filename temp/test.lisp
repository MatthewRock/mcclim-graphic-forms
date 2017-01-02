;(in-package :clim-gf)
;;;
;;; (run-frame-top-level (make-application-frame 'buttons))
;;;
(in-package :clim-gf)

(define-application-frame buttons () ()
  (:menu-bar nil)
  (:layouts
    (default
      (vertically (:equalize-width t)
        (make-pane 'push-button :label "First")))))

(defmethod clim:activate-callback
    ((button clim:push-button) client gadget-id)
  (with-slots (output-pane) client
    (debug-print "hello-world")))
