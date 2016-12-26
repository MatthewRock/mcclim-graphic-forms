(in-package :clim-graphic-forms)

(defclass graphic-forms-frame-manager (frame-manager)
  ())

(defmethod make-pane-1 ((fm graphic-forms-frame-manager) (frame application-frame) type &rest args)
  (apply #'make-instance
	 (%find-concrete-pane-class fm type)
	 :frame frame
	 :manager fm
	 :port (port frame)
	 args))

(defmethod %find-concrete-pane-class ((fm graphic-forms-frame-manager) type)
  (when (get type 'climi::concrete-pane-class-name)
    (setf type (get type 'climi::concrete-pane-class-name)))
  (class-name
   (or (find-class
	(intern (concatenate 'string (symbol-name type) "-PANE") :climi)
	nil)
       (if (keywordp type)
	   (find-class (intern (symbol-name type) :climi))
	   (find-class type)))))