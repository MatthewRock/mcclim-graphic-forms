(in-package :clim-graphic-forms)

(defclass graphic-forms-medium (basic-medium)
  ((font
    :accessor font-of
    :initform nil)
   (image
    :accessor image-of
    :initform nil)
   (buffering-p
    :accessor buffering-p
    :initform t)))

(defvar *medium-origin*     (<+ `(gfs:make-point)))
(defvar *mediums-to-render* nil)

(defun %add-medium-to-render (medium)
  (when (image-of medium)
    (pushnew medium *mediums-to-render* :test #'eql)))

(defun %remove-medium-to-render (medium)
  (setf *mediums-to-render* (remove medium *mediums-to-render*)))

(defun %render-medium-buffer (medium)
  (let ((mirror (climi::port-lookup-mirror (port-of medium) (medium-sheet medium))))
    (with-server-graphics-context (gc mirror)
      (<+ `(gfg:draw-image ,gc ,(image-of medium) ,*medium-origin*)))))

(defun %render-pending-mediums ()
  (loop for medium in *mediums-to-render*
        do (%render-medium-buffer medium))
  (setf *mediums-to-render* nil))

(defun %target-of (medium)
  (if (medium-buffering-output-p medium)
    (let ((sheet (medium-sheet medium)))
	(or (image-of medium)
	    (let* ((region (climi::sheet-mirror-region sheet))
		   (width (floor (bounding-rectangle-max-x region)))
		   (height (floor (bounding-rectangle-max-y region))))
	      (setf (image-of medium)
		    (<+ `(make-instance 'gfg:image
					:size (gfs:make-size ,width ,height)))))))
    (sheet-mirror (medium-sheet medium))))

(defun %ink-to-color (medium ink)
  (cond
    ((subtypep (class-of ink) (find-class 'climi::opacity))
     (setf ink (medium-foreground medium))) ; see discussion of opacity in design.lisp
    ((eql ink +foreground-ink+)
     (setf ink (medium-foreground medium)))
    ((eql ink +background-ink+)
     (setf ink (medium-background medium)))
    ((eql ink +flipping-ink+)
     (warn "+flipping-ink+ is currently unsupported in graphic-forms backend")
     (setf ink nil)))
  (if ink
    (multiple-value-bind (red green blue) (clim:color-rgb ink)
      (<+ `(gfg:make-color :red ,(min (truncate (* red 256)) 255)
			   :green ,(min (truncate (* green 256)) 255)
			   :blue ,(min (truncate (* blue 256)) 255))))
    (with-server-graphics-context (gc (target-of medium))
      (<+ `(gfg:background-color ,gc)))))

(defun text-style-to-font (gc text-style old-data)
  (multiple-value-bind (family face size)
      (text-style-components (merge-text-styles text-style *default-text-style*))
    #+nil (gfs::debug-format "family: ~a  face: ~a  size: ~a~%" family face size)
    ;;
    ;; FIXME: what to do about font data char sets?
    ;;
    ;; FIXME: externalize these specific choices so that applications can
    ;; have better control over them
    ;;
    (let ((face-name (if (stringp family)
                         family
                         (ecase family
                           ((:fix :fixed) "Lucida Console")
                           (:serif        "Times New Roman")
                           (:sans-serif    "Arial"))))
          (pnt-size (case size
                      (:tiny       6)
                      (:very-small 7)
                      (:small      8)
                      (:normal     10)
                      (:large      12)
                      (:very-large 14)
                      (:huge       16)
                      (otherwise   10)))
          (style nil))
      (pushnew (case face
                 ((:bold :bold-italic :bold-oblique :italic-bold :oblique-bold)
                  :bold)
                 (otherwise
                  :normal))
               style)
      (pushnew (case face
                 ((:bold-italic :italic :italic-bold)
                  :italic)
                 (otherwise
                  :normal))
               style)
      (pushnew (case family
                 ((:fix :fixed) :fixed)
                 (otherwise     :normal))
               style)
      (if (or (null old-data)
              (not (eql pnt-size (<+ `(gfg:font-data-point-size ,old-data))))
              (string-not-equal face-name (<+ `(gfg:font-data-face-name ,old-data)))
              (/= (length style)
                  (length (intersection style (<+ `(gfg:font-data-style ,old-data))))))
          (let ((new-data (<+ `(gfg:make-font-data :face-name ,face-name
						   :point-size ,pnt-size
						   :style ',style))))
            (<+ `(make-instance 'gfg:font :gc ,gc :data ,new-data)))
          (<+ `(make-instance 'gfg:font :gc ,gc :data ,old-data))))))

(defmethod invoke-with-special-choices (continuation (medium graphic-forms-medium))
  (let ((sheet (medium-sheet medium)))
    (funcall continuation (sheet-medium sheet))))

(defmethod medium-draw-circle* ((medium graphic-forms-medium)
				center-x center-y radius start-angle end-angle
				filled)
  (medium-draw-ellipse* medium
			center-x center-y
			radius radius
			radius radius
			start-angle end-angle
			filled))

(defmethod medium-draw-glyph ((medium graphic-forms-medium) element x y
			      align-x align-y toward-x toward-y
			      transform-glyphs)
;; FIXME: what is glyph
  ())

;;; a note on xlib:drawable-x, xlib:drawable-y
;;; from: https://tronche.com/gui/x/xlib/window-information/XGetGeometry.html
;;; (xlib:drawable-x and xlib:drawable-y) Return the x and y coordinates that define the location of the drawable. For a window, these coordinates specify the upper-left outer corner relative to its parent's origin. For pixmaps, these coordinates are always zero.
;;; (defmethod mirror-transformation ((port clx-port) mirror)
;;;   (make-translation-transformation (xlib:drawable-x mirror)
;;;                                    (xlib:drawable-y mirror)))
;;; This function is not in spec and not called by other codes.
(defmethod mirror-transformation ((port graphic-forms-port) mirror)
  (let ((point (<+ `(gfw:relative-location ,mirror))))
    (make-translation-transformation (gfs:point-x point)
				     (gfs:point-y point))))

(defmethod text-style-ascent (text-style (medium graphic-forms-medium))
  (declare (ignore text-style))
  (let ((font (font-of medium)))
    (if font
      (with-server-graphics-context (gc (%target-of medium))
	(<+ `(gfg:ascent (gfg:metrics ,gc ,font))))
      1)))

(defmethod text-style-descent (text-style (medium graphic-forms-medium))
  (declare (ignore text-style))
  (let ((font (font-of medium)))
    (if font
      (with-server-graphics-context (gc (%target-of medium))
	(<+ `(gfg:descent (gfg:metrics ,gc ,font))))
      1)))

(defmethod text-style-height (text-style (medium graphic-forms-medium))
  (declare (ignore text-style))
  (let ((font (font-of medium)))
    (if font
      (with-server-graphics-context (gc (%target-of medium))
	(<+ `(gfg:height (gfg:metrics ,gc ,font))))
      1)))

(defmethod text-style-character-width (text-style (medium graphic-forms-medium) char)
  (declare (ignore text-style))
  (let ((font (font-of medium))
      ;  (width 1)
        (text (normalize-text-data char)))
    (if font
	(let ((width (with-server-graphics-context (gc (%target-of medium))
		       (<+ `(setf (gfg:font ,gc) ,font))
		       (<+ `(gfs:size-width (gfg:text-extent ,gc ,text))))))
	  width))
    1))

(defmethod text-style-width (text-style (medium graphic-forms-medium))
  (declare (ignore text-style))
  (let ((font (font-of medium)))
    (if font
      (with-server-graphics-context (gc (%target-of medium))
	(<+ `(gfg:average-char-width (gfg:metrics ,gc ,font))))
      1)))

(defmethod text-size ((medium graphic-forms-medium) string &key text-style (start 0) end)
  (setf string (normalize-text-data string))
  (setf text-style (or text-style (make-text-style nil nil nil)))
  (setf text-style
        (merge-text-styles text-style (medium-default-text-style medium)))
  (sync-text-style medium text-style)
  (with-server-graphics-context (gc (%target-of medium))
    (let ((font (font-of medium)))
      (<+ `(setf (gfg:font ,gc) ,font))
      (let ((metrics (<+ `(gfg:metrics ,gc ,font)))
	    (extent (<+ `(gfg:text-extent ,gc ,(subseq string
						  start
						  (or end (length string)))))))
	(values (<+ `(gfs:size-width ,extent))
		(<+ `(gfg:height ,metrics))
		(<+ `(gfs:size-width ,extent))
		(<+ `(gfg:height ,metrics))
		(<+ `(gfg:ascent ,metrics)))))))

(defmethod medium-beep ((medium graphic-forms-medium))
  (<+ `(gfs::beep 750 300)))

(defmethod medium-buffering-output-p ((medium graphic-forms-medium))
  (buffering-p medium))

(defmethod (setf medium-buffering-output-p) (buffering (medium graphic-forms-medium))
  (setf (buffering-p medium)))

(defmethod medium-clear-area ((medium graphic-forms-medium) left top right bottom)
  (when (%target-of medium)
    (let ((rect (coordinates->rectangle left top right bottom))
          (color (ink-to-color medium (medium-background medium))))
      (with-server-graphics-context (gc (%target-of medium))
	(<+ `(setf (gfg:background-color ,gc) ,color 
		   (gfg:foreground-color ,gc) ,color))
	(<+ `(gfg:draw-filled-rectangle ,gc ,rect)))))
  (%add-medium-to-render medium))

;;; TODO
(defmethod medium-copy-area ((from-drawable graphic-forms-medium) from-x from-y width height
                             (to-drawable graphic-forms-medium) to-x to-y)
  ())

(defmethod medium-copy-area ((from-drawable graphic-forms-medium) from-x from-y width height
                             (to-drawable pixmap) to-x to-y)
  ())

(defmethod medium-copy-area ((from-drawable pixmap) from-x from-y width height
                             (to-drawable graphic-forms-medium) to-x to-y)
  ())

(defmethod medium-copy-area ((from-drawable pixmap) from-x from-y width height
                             (to-drawable pixmap) to-x to-y)
  ())

(defmethod medium-draw-ellipse* ((medium graphic-forms-medium)
                                 center-x center-y
                                 radius-1-dx radius-1-dy
                                 radius-2-dx radius-2-dy
                                 start-angle end-angle
                                 filled)
  (unless (or (= radius-2-dx radius-1-dy 0)
              (= radius-1-dx radius-2-dy 0))
    (error "MEDIUM-DRAW-ELLIPSE* not for non axis-aligned ellipses."))
  (when (%target-of medium)
    (with-server-graphics-context (gc (%target-of medium))
      (let ((color (ink-to-color medium (medium-ink medium))))
	(if filled
	    (<+ `(setf (gfg:background-color ,gc) ,color)))
	(<+ `(setf (gfg:foreground-color ,gc) ,color)))
      (climi::with-transformed-position
	  ((sheet-native-transformation (medium-sheet medium))
	    center-x center-y)
	(let* ((width (abs (+ radius-1-dx radius-2-dx)))
	       (height (abs (+ radius-1-dy radius-2-dy)))
	       (min-x (floor (- center-x width)))
	       (min-y (floor (- center-y height)))
	       (max-x (floor (+ center-x width)))
	       (max-y (floor (+ center-y height)))
	       (rect (coordinates->rectangle min-x min-y max-x max-y))
	       (start-pnt (compute-arc-point center-x center-y
					     width height
					     start-angle))
	       (end-pnt (compute-arc-point center-x center-y
					   width height
					   end-angle)))
	  (if filled
	      (<+ `(gfg:draw-filled-pie-wedge ,gc ,rect ,start-pnt ,end-pnt)) 
	      (<+ `(gfg:draw-arc ,gc ,rect ,start-pnt ,end-pnt))))))
    (%add-medium-to-render medium)))

(defmethod medium-draw-line* ((medium graphic-forms-medium) x1 y1 x2 y2)
  (when (target-of medium)
    (with-server-graphics-context (gc (target-of medium))
      (let ((color (ink-to-color medium (medium-ink medium))))
	(<+ `(setf (gfg:foreground-color ,gc) ,color)))
      (let ((tr (sheet-native-transformation (medium-sheet medium))))
	(climi::with-transformed-position (tr x1 y1)
	  (climi::with-transformed-position (tr x2 y2)
	    (<+ `(gfg:draw-line ,gc
				(gfs:make-point :x ,(floor x1)
						:y ,(floor y1))
				(gfs:make-point :x ,(floor x2)
						:y ,(floor y2))))))))
    (add-medium-to-render medium)))

(defmethod medium-draw-lines* ((medium graphic-forms-medium) coord-seq)
  (when (target-of medium)
    (with-server-graphics-context (gc (target-of medium))
      (let ((color (ink-to-color medium (medium-ink medium))))
	(<+ `(setf (gfg:foreground-color ,gc) ,color)))
      (let ((tr (sheet-native-transformation (medium-sheet medium))))
	(loop for (x1 y1 x2 y2) on (coerce coord-seq 'list) by #'cddddr do
	     (climi::with-transformed-position (tr x1 y1)
	       (climi::with-transformed-position (tr x2 y2)
		 (<+ `(gfg:draw-line ,gc
				 (gfs:make-point :x ,(floor x1)
						 :y ,(floor y1))
				 (gfs:make-point :x ,(floor x2)
						 :y ,(floor y2)))))))))
    (add-medium-to-render medium)))

(defmethod medium-draw-point* ((medium graphic-forms-medium) x y)
  (when (target-of medium)
    (with-server-graphics-context (gc (target-of medium))
      (let ((color (ink-to-color medium (medium-ink medium))))
	(<+ `(setf (gfg:foreground-color ,gc) ,color)))
      (let ((tr (sheet-native-transformation (medium-sheet medium))))
	(climi::with-transformed-position (tr x y)
	  (<+ `(gfg:draw-point ,gc (gfs:make-point :x ,(floor x)
						   :y ,(floor y)))))))
    (add-medium-to-render medium)))

(defmethod medium-draw-points* ((medium graphic-forms-medium) coord-seq)
  (when (target-of medium)
    (with-server-graphics-context (gc (target-of medium))
      (let ((color (ink-to-color medium (medium-ink medium))))
	(<+ `(setf (gfg:foreground-color ,gc) ,color)))
      (let ((tr (sheet-native-transformation (medium-sheet medium))))
	(loop for (x y) on (coerce coord-seq 'list) by #'cddr do
	     (climi::with-transformed-position (tr x y)
	       (<+ `(gfg:draw-point ,gc
				    (gfs:make-point :x ,(floor x)
						    :y ,(floor y))))))))
    (add-medium-to-render medium)))

(defmethod medium-draw-polygon* ((medium graphic-forms-medium) coord-seq closed filled)
  (when (target-of medium)
    (with-server-graphics-context (gc (target-of medium))
      (climi::with-transformed-positions
	  ((sheet-native-transformation (medium-sheet medium)) coord-seq)
	(let ((points-list (coordinates->points coord-seq))
	      (color (ink-to-color medium (medium-ink medium)))))
	  (if filled
	      (<+ `(setf (gfg:background-color ,gc) ,color)))
	  (<+ `(setf (gfg:foreground-color ,gc) ,color))
	  (when (and closed (not filled))
	    (push (car (last points-list)) points-list))
	  (if filled
	      (<+ `(gfg:draw-filled-polygon ,gc ',points-list))
	      (<+ `(gfg:draw-polygon ,gc ',points-list))))))
  (add-medium-to-render medium))

(defmethod medium-draw-rectangle* ((medium graphic-forms-medium) left top right bottom filled)
  (when (target-of medium)
    (with-server-graphics-context (gc (target-of medium))
      (let ((tr (sheet-native-transformation (medium-sheet medium))))
	(climi::with-transformed-position (tr left top)
	  (climi::with-transformed-position (tr right bottom)
	    (let ((rect (coordinates->rectangle left top right bottom))
		  (color (ink-to-color medium (medium-ink medium))))
	      (if filled
		  (<+ `(setf (gfg:background-color ,gc) ,color)))
	      (<+ `(setf (gfg:foreground-color ,gc) ,color))
	      (if filled
		  (<+ `(gfg:draw-filled-rectangle ,gc ,rect))
		  (<+ `(gfg:draw-rectangle ,gc ,rect))))))))
    (add-medium-to-render medium)))

(defmethod medium-draw-rectangles* ((medium graphic-forms-medium) position-seq filled)
  (when (target-of medium)
    (with-server-graphics-context (gc (target-of medium))
      (let ((tr (sheet-native-transformation (medium-sheet medium)))
	    (color (ink-to-color medium (medium-ink medium))))
	(if filled
	    (<+ `(setf (gfg:background-color ,gc) ,color)))
	(<+ `(setf (gfg:foreground-color ,gc) ,color))
	(loop for i below (length position-seq) by 4 do
	     (let ((x1 (floor (elt position-seq (+ i 0))))
		   (y1 (floor (elt position-seq (+ i 1))))
		   (x2 (floor (elt position-seq (+ i 2))))
		   (y2 (floor (elt position-seq (+ i 3)))))
	       (climi::with-transformed-position (tr x1 y1)
		 (climi::with-transformed-position (tr x2 y2)
		   (let ((rect (coordinates->rectangle x1 y1 x2 y2)))
		     (if filled
			 (<+ `(gfg:draw-filled-rectangle ,gc ,rect))
			 (<+ `(gfg:draw-rectangle ,gc ,rect))))))))))
    (add-medium-to-render medium)))

(defmethod medium-draw-text* ((medium graphic-forms-medium) string x y
                              start end
                              align-x align-y
                              toward-x toward-y transform-glyphs)
  (declare (ignore align-x align-y toward-x toward-y transform-glyphs))
  #+nil (<+ `(gfs::debug-format "medium-draw-text: ~d, ~d  ~s~%" ,x ,y ,string))
  (when (target-of medium)
    (sync-text-style medium
                     (merge-text-styles (medium-text-style medium)
                                        (medium-default-text-style medium)))
    (setf string (normalize-text-data string))
    (with-server-graphics-context (gc (target-of medium))
      (let ((font (font-of medium)))
	(if font
	    (<+ `(setf (gfg:font ,gc) ,font)))
	(let ((ascent (<+ `(gfg:ascent (gfg:metrics ,gc ,font))))
	      (x (floor x))
	      (y (floor y)))
	  (<+ `(gfg:draw-text ,gc
			      ,(subseq string start (or end (length string)))
			      (gfs:make-point :x ,x :y ,(- y ascent)))))))
    (add-medium-to-render medium)))

(defmethod medium-finish-output ((medium graphic-forms-medium))
  (when (image-of medium)
    (render-medium-buffer medium)))

(defmethod medium-force-output ((medium graphic-forms-medium))
  (when (image-of medium)
    (render-medium-buffer medium)))

(defmethod (setf medium-text-style) :before (text-style (medium graphic-forms-medium))
  (sync-text-style medium
                   (merge-text-styles (medium-text-style medium)
                                      (medium-default-text-style medium))))

(defmethod (setf medium-line-style) :before (line-style (medium graphic-forms-medium))
  ())
