;;; -*- Mode:Lisp; Syntax:ANSI-Common-Lisp; Coding:utf-8; Package:Varray -*-
;;;; core.lisp

(in-package #:varray)

"Core classes, methods and specs for virtual arrays."

;; specialized types for April virtual arrays
(deftype ava-worker-count () `(integer 0 ,(max 1 (1- (serapeum:count-cpus :default 2)))))
(deftype ava-rank () `(integer 0 ,(1- array-rank-limit)))
(deftype ava-dimension () `(integer 0 ,(1- array-dimension-limit)))
(deftype ava-size () `(integer 0 ,(1- array-total-size-limit)))

(defparameter *workers-count* (max 1 (1- (serapeum:count-cpus :default 2))))

(defclass va-class (standard-class)
  nil (:documentation "Metaclass for virtual array objects."))

(defmethod closer-mop:validate-superclass ((class va-class)
                                           (superclass cl:standard-class))
  t)

(defclass varray ()
  ((%shape :accessor varray-shape
           :initform nil
           :initarg :shape
           :documentation "The array's shape - typically populated by a (shape-of) method.")
   (%generator :accessor varray-generator
               :initform nil
               :initarg :generator
               :documentation "The array's generator - typically populated by an (generator-of) method.")
   (%prototype :accessor varray-prototype
               :initform nil
               :initarg :prototype
               :documentation "The array's prototype - typically populated by a (prototype-of) method.")
   (%meta :accessor varray-meta
          :initform nil
          :initarg :meta
          :documentation "Metadata for the array."))
  (:metaclass va-class)
  (:documentation "Virtual array - the ancestor class for all virtual array objects."))

(defun varrayp (item)
  (typep item 'varray))

(defun subrendering-p (item)
  (and (or (typep item 'varray-derived)
           (typep item 'vad-subrendering))
       (vads-subrendering item)))

(defgeneric etype-of (varray)
  (:documentation "Get the element type of an array."))

(defgeneric prototype-of (varray)
  (:documentation "Get the prototype of an array."))

(defgeneric shape-of (varray)
  (:documentation "Get the shape of an array."))

(defgeneric size-of (varray)
  (:documentation "Get the size of an array."))

(defgeneric rank-of (varray)
  (:documentation "Get the rank of an array."))

(defgeneric indexer-of (varray &optional params)
  (:documentation "Get an indexing function for an array."))

(defgeneric base-indexer-of (varray &optional params)
  (:documentation "Get an indexing function for a virtual array's base."))

(defgeneric sub-indexer-of (varray)
  (:documentation "Get a sub-indexing function for an array."))

(defgeneric generator-of (varray &optional indexers params)
  (:documentation "Get a generating function for an array."))

(defgeneric metadata-of (varray)
  (:documentation "Get metadata of a virtual array."))

;; dedicated reduction methods for particlar virtual array types

(defgeneric get-reduced (varray function)
  (:documentation "Get the result of an array reduced using a particular function."))

(defgeneric render (varray &rest params)
  (:documentation "Render an array into memory."))

(defun get-dimensional-factors (dimensions &optional as-vector)
  "Get the set of dimensional factors corresponding to a set of array dimensions."
  (let ((factor) (last-index))
    (if as-vector
        (let* ((rank (length dimensions))
               (output (make-array rank :element-type
                                   ;; (list 'integer 0 (reduce #'* (rest dimensions)))
                                   '(unsigned-byte 32)
                                   )))
          (loop :for d :in (reverse dimensions) :for dx :from 0
                :do (setf factor (setf (aref output (- rank dx 1))
                                       (if (zerop dx) 1 (* factor last-index)))
                          last-index d))
          output)
        (reverse (loop :for d :in (reverse dimensions) :for dx :from 0
                       :collect (setq factor (if (zerop dx) 1 (* factor last-index)))
                       :do (setq last-index d))))))

(defun apl-array-prototype (array)
  "Returns the default element for an array based on that array's first element (its prototype in array programming terms); blank spaces in the case of a character prototype and zeroes for others."
  (labels ((derive-element (input)
             (if (characterp input)
                 #\  (if (not (arrayp input))
                         (if (varrayp input)
                             (prototype-of input)
                             (let ((itype (type-of input)))
                               ;; in ECL (and others?), the integer type of a scalar is that number alone,
                               ;; i.e. (integer 2 2) for 2, so make sure the integer range starts with 0
                               (if (eql 'null itype)
                                   'null (coerce 0 (if (eql 'ratio itype) 'integer
                                                       (if (and (listp itype) (eql 'integer (first itype)))
                                                           (list 'integer (min 0 (second itype))
                                                                 (max 0 (or (third itype) 0)))
                                                           (if (typep input 'number) itype 'number)))))))
                         (if (zerop (array-total-size input))
                             (make-array (array-dimensions input))
                             (derive-element (row-major-aref input 0)))))))
    (if (not (arrayp array))
        (if (varrayp array) (prototype-of array)
            (derive-element array))
        (if (zerop (array-total-size array))
            (if (eql 'character (array-element-type array))
                #\  (coerce 0 (array-element-type array)))
            (let ((first-element (row-major-aref array 0)))
              (if (not (arrayp first-element))
                  (derive-element first-element)
                  (funcall (if (< 0 (array-rank first-element))
                               #'identity (lambda (item) (make-array nil :initial-element item)))
                           (let ((first-element (if (< 0 (array-rank first-element))
                                                    first-element (aref first-element))))
                             (if (and (arrayp first-element)
                                      (zerop (array-total-size first-element)))
                                 first-element
                                 (make-array (array-dimensions first-element)
                                             :element-type (array-element-type first-element)
                                             :initial-element (derive-element first-element)))))))))))

(defmethod prototype-of ((item t))
  "The prototype representation of an item is returned by the (apl-array-prototype) function."
  (if (listp item) ;; lists, used to implement things like namespaces, have a nil prototype
      nil (if (and (arrayp item)
                 (array-displacement item)
                 (vectorp (array-displacement item))
                 (listp (aref (array-displacement item) 0))
                 (member :empty-array-prototype (aref (array-displacement item) 0)))
            ;; if an empty array prototype has been stored, retrieve it
            (getf (aref (array-displacement item) 0) :empty-array-prototype)
            (if (and (arrayp item) (zerop (array-rank item)))
                (aplesque:make-empty-array (disclose item))
                (apl-array-prototype item)))))

(defmethod prototype-of ((varray varray))
  "The default prototype for a virtual array is 0."
  0)

(defmethod etype-of ((item t))
  "A literal array's element type is returned by the (array-element-type) function."
  (assign-element-type item))

(defmethod etype-of ((array array))
  "A literal array's element type is returned by the (array-element-type) function."
  (array-element-type array))

(defmethod etype-of ((varray varray))
  "The default element type for a virtual array is T."
  't)

(defmethod shape-of ((_ t))
  "Non-arrays have a nil shape."
  (declare (ignore _))
  nil)

(defmethod shape-of ((array array))
  "Literal array shapes are given by (array-dimensions)."
  (array-dimensions array))

(defmethod shape-of ((varray varray))
  "Virtual array shapes are referenced using the (varray-shape) method."
  (varray-shape varray))
  
(defmethod size-of ((item t))
  "Virtual array shapes are referenced using the (varray-shape) method."
  (if (not (arrayp item))
      1 (array-total-size item)))

(defmethod size-of ((varray varray))
  "Virtual array shapes are referenced using the (varray-shape) method."
  (reduce #'* (shape-of varray)))

(defmethod rank-of ((item t))
  "Non-arrays have a rank of 0."
  (declare (ignore item))
  0)

(defmethod rank-of ((array array))
  "Literal array ranks are given by (array-rank)."
  (array-rank array))

(defmethod rank-of ((varray varray))
  "A virtual array's rank is the length of its shape."
  (length (shape-of varray)))

(defmethod indexer-of ((item t) &optional params)
  "The indexer for a non-array is its identity."
  item)

(defmethod indexer-of ((array array) &optional params)
  (if (= 0 (array-rank array))
      ;; array
      ;; TODO: this causes tree printing test to fail
      (lambda (index)
        (when (< index (array-total-size array))
          (row-major-aref array index)))
      (if (= 0 (array-total-size array))
          (prototype-of array)
          ;; TODO: why does wrapping this in a (lambda) cause problems? like array-lib's (0↑⊂,⊂⍬) from 99
          (lambda (index)
            (when (< index (array-total-size array))
              (row-major-aref array index))))))

(defun join-indexers (indexers type)
  (if (not indexers)
      #'identity
      (let ((ctype) ;; the type in common
            (reversed-indexers)
            ;; will default if a type is not specified
            (defaulting (member type '(t nil))))
         (loop :for i :in indexers :while (not defaulting)
              :do (if (or (not (listp i)) (not (first i)))
                      (setf defaulting t)
                      (push (first i) reversed-indexers)))
        (when defaulting
          (setf reversed-indexers nil)
          (loop :for i :in indexers :do (push (if (not (listp i)) i (second i))
                                              reversed-indexers)))
        ;; (print (list :re indexers reversed-indexers defaulting type))
        (values (lambda (index)
                  (let ((index-out index))
                    (loop :for i :in reversed-indexers :do (setf index-out (funcall i index-out)))
                    index-out))
                (when (not defaulting) type)))))

(defmethod generator-of ((item t) &optional indexers params)
  (declare (ignore indexers params))
  item)

(defmethod generator-of ((array array) &optional indexers params)
  (multiple-value-bind (composite-indexer is-not-defaulting)
      (join-indexers indexers (getf params :indexer-key))
    (values
     (let ((array-size (array-total-size array)))
       (if (and is-not-defaulting (getf params :indexer-key)
                (member (getf params :indexer-key) '(:e8 :e16 :e32 :e64)))
           (let* ((factors (get-dimensional-factors (shape-of array) t))
                  (encoded-type (intern (format nil "I~a" (getf params :encoding)) "KEYWORD"))
                  (converter (decode-rmi (getf params :encoding) (getf params :index-width)
                                         (array-rank array) factors)))
             ;; (print (list :con converter factors (format nil "I~a" (getf params :encoding))))
             (lambda (index)
               (let ((index-out (funcall converter (funcall composite-indexer index))))
                 (when (< index-out array-size) (row-major-aref array index-out)))))
           (lambda (index)
             (let ((index-out (funcall composite-indexer index)))
               (when (< index-out array-size) (row-major-aref array index-out))))))
     is-not-defaulting)))

(defmethod metadata-of ((item t))
  (declare (ignore item))
  nil)

(defmethod metadata-of ((varray varray))
  (varray-meta varray))

(defmethod render ((item t) &rest params)
  "Rendering a non-virtual array object simply returns the object."
  item)

(defun subrendering-base (item)
  (when (typep item 'varray-derived)
    (or (subrendering-p (vader-base item))
        (subrendering-base (vader-base item)))))

(defun sub-byte-element-size (array)
  "Return the element size in bits if the argument is an array whose elements are integers smaller than 7 bits."
  (and (arrayp array)
       (let ((type (array-element-type array)))
         (or (and (eql 'bit type) 1)
             #+clasp (case type (ext:byte2 2)
                           (ext:integer2 2) (ext:byte4 4) (ext:integer4 4))
             #+(not clasp) (and (listp type)
                                (eql 'unsigned-byte (first type))
                                (> 7 (second type))
                                (second type))))))

(defmethod generator-of ((varray varray) &optional indexers params)
  (let ((composite-indexer (join-indexers indexers t))
        (this-indexer (indexer-of varray)))
    ;; (print (list :pg params))
    (if (not (functionp this-indexer))
        this-indexer (lambda (index)
                       (funcall this-indexer (funcall composite-indexer index))))))

(defmethod generator-of :around ((varray varray) &optional indexers params)
  (if (typep varray 'vad-reindexing) (call-next-method)
      (let ((this-generator (call-next-method)))
        ;; (print (list :par params varray))
        (if (not (functionp this-generator))
            this-generator
            (multiple-value-bind (composite-indexer is-not-defaulting)
                (join-indexers indexers t)
              ;; (print (list :ind is-not-defaulting))
              (values (lambda (index)
                        (let ((index-out index))
                          (funcall this-generator (funcall composite-indexer index))))
                      is-not-defaulting))))))

(let ((encoder-table
        (intraverser
         (:eindex-width +eindex-width+ :cindex-width +cindex-width+
          :rank-width +rank-width+ :rank-plus +rank-plus+)
         (the (function ((simple-array (unsigned-byte 62) (+rank-plus+))) ;; TODO: variable type
                        function)
              (lambda (factors)
                (the (function ((unsigned-byte +eindex-width+))
                               (unsigned-byte +eindex-width+))
                     (lambda (index)
                       (let ((remaining index)
                             (output (the (unsigned-byte +eindex-width+) 0)))
                         (loop :for f :of-type (unsigned-byte 62) :across factors
                               :for ix :of-type (unsigned-byte +rank-width+)
                                 := (1- +rank-plus+) :then (1- ix)
                               :do (multiple-value-bind (factor remainder)
                                       (floor remaining f)
                                     (setf output (dpb factor (byte +cindex-width+
                                                                    (* +cindex-width+ ix))
                                                       output)
                                           remaining remainder)))
                         output))))))))
  (defun encode-rmi (factors iwidth itype)
    (let ((base-encoder (gethash (list iwidth itype (length factors)) encoder-table)))
      (when base-encoder (funcall base-encoder factors)))))

;; (format t "#x~4,'0X~%" (funcall (encode-rmi :i32 #(12 4 1) 8) 14))

(let ((function-table
        (intraverser
         (:eindex-width +eindex-width+ :cindex-width +cindex-width+ :rank-width +rank-width+
          :sub-base-width +sub-base-width+ :rank-plus +rank-plus+)
         (the (function ((simple-array (unsigned-byte 32) (+rank-plus+))) ;; TODO: variable type
                        function)
              (lambda (factors)
                (declare (optimize (speed 3) (safety 0))
                         (type (simple-array (unsigned-byte 32) (+rank-plus+)) factors))
                (the (function ((unsigned-byte +eindex-width+))
                               (unsigned-byte +eindex-width+))
                     (lambda (index)
                       (declare (type (unsigned-byte +eindex-width+) index))
                       (let ((output (the (unsigned-byte +eindex-width+) 0)))
                         (loop :for fx :of-type (unsigned-byte +rank-width+)
                                 := (1- +rank-plus+) :then (1- fx)
                               :for ix :of-type (unsigned-byte 32) :across factors
                               :do (incf (the (unsigned-byte +eindex-width+) output)
                                         (* (the (unsigned-byte +eindex-width+) ix)
                                            (the (unsigned-byte +cindex-width+)
                                                 (ldb (byte +cindex-width+
                                                            (* +cindex-width+ fx))
                                                      index)))))
                         (the (unsigned-byte +eindex-width+) output)))))))))
  (defun decode-rmi (width element-width rank factors)
    (let ((match (gethash (list width element-width rank) function-table)))
      (values (when match (funcall match factors))
              (lambda (index)
                (let ((output 0))
                  (loop :for fx :from rank :downto 0
                        :for ix :across factors
                        :do (incf output (* ix (ldb (byte element-width
                                                          (* element-width fx))
                                                    index))))
                  output))))))

(let* (( 8-bit-factors (make-array 8 :element-type '(unsigned-byte 64)))
       (16-bit-factors (make-array 4 :element-type '(unsigned-byte 64)))
       (32-bit-factors (make-array 2 :element-type '(unsigned-byte 64)))
       (function-table
         (intraverser
          (:eindex-width +eindex-width+ :cindex-width +cindex-width+
           :rank-width +rank-width+ :sub-base-width +sub-base-width+ :rank-plus +rank+)
          (the (function ((simple-array (unsigned-byte +cindex-width+) (+rank+)))
                         function)
               (lambda (dimensions)
                 (declare (optimize (speed 3) (safety 0))
                          (type (simple-array (unsigned-byte +cindex-width+) (+rank+)) dimensions))
                 (let ((factors (case +cindex-width+
                                  (8  (the (simple-array (unsigned-byte 64) (8))  8-bit-factors))
                                  (16 (the (simple-array (unsigned-byte 64) (4)) 16-bit-factors))
                                  (32 (the (simple-array (unsigned-byte 64) (2)) 32-bit-factors)))))
                   (the (function ((unsigned-byte +eindex-width+))
                                  (unsigned-byte +eindex-width+))
                        (lambda (index)
                          (declare (type (unsigned-byte +eindex-width+) index))
                          (let ((output index) (complete (the (unsigned-byte +rank-width+) 0)))
                            (declare (type (unsigned-byte +eindex-width+) output))
                            (loop :for ix :of-type (unsigned-byte +rank-width+)
                                  :from 0 :below +rank+
                                  :for dim :of-type (unsigned-byte +cindex-width+) :across dimensions
                                  :for fac :of-type (unsigned-byte 64) :across factors
                                  :while (zerop complete)
                                  :do (if (< (the (unsigned-byte +cindex-width+)
                                                  (ldb (byte +cindex-width+ (* +cindex-width+ ix))
                                                       index))
                                             (1- dim))
                                          (incf (the (unsigned-byte +rank-width+) complete)
                                                (the bit (signum (incf output fac))))
                                          (setf output (dpb 0 (byte +cindex-width+ (* +cindex-width+ ix))
                                                            output))))
                            ;; (print (list :in (format nil "#x~4,'0X" index)
                            ;;              (format nil "#x~4,'0X" output)))
                            (the (unsigned-byte +eindex-width+) output))))))))))
  (loop :for i :below 8 :do (setf (aref  8-bit-factors i) (expt 256 i)))
  (loop :for i :below 4 :do (setf (aref 16-bit-factors i) (expt 65536 i)))
  (loop :for i :below 2 :do (setf (aref 32-bit-factors i) (expt 4294967296 i)))
  
  (defun increment-encoded (width element-width dimensions)
    (let* ((rank (length dimensions))
           (match (gethash (list width element-width rank) function-table)))
      (values (when match (funcall match dimensions))
              (let ((factors (case element-width (8 8-bit-factors)
                               (16 16-bit-factors) (32 32-bit-factors))))
                (lambda (index)
                  (let ((output index) (complete))
                    (loop :for ix :from 0 :below rank :while (not complete)
                          :do (if (< (ldb (byte element-width (* element-width ix))
                                          index)
                                     (1- (aref dimensions ix)))
                                  (setf complete (incf output (aref factors ix)))
                                  (setf output (dpb 0 (byte element-width (* element-width ix))
                                                    output))))
                    output)))))))

;; (format t "#x~8,'0X" (funcall (increment-encoded :i32 #(2 3 4) 8) #x20001))
;; (format t "#x~8,'0X" (funcall (increment-encoded 32 8 (make-array 3 :element-type '(unsigned-byte 8) :initial-contents '(2 3 4))) #x20001))

(defun get-indexing-function (typekey factors shape-vector sbesize interval divisions
                              total-size index-type encoding-type to-call)
  ;; TODO: when encoded indexing is disabled, the following will fail:
  ;; (april::april-f (with (:space array-lib-space)) "(2 1)(2 1)(2 1)(2 1) from ta4")
  ;; why does this happen?
  (let* ((ekey (intern (format nil "I~a" encoding-type) "KEYWORD"))
         (encoder (when encoding-type (encode-rmi factors encoding-type index-type )))
         (incrementer (when encoding-type (increment-encoded encoding-type index-type
                                                             shape-vector)))
         (default-indexer (lambda (index)
                            (lambda ()
                              ;; (print (list :mm index t))
                              (let* ((start-intervals (ceiling (* interval index)))
                                     (start-at (* sbesize start-intervals))
                                     (count (if (< index (1- divisions))
                                                (* sbesize (- (ceiling (* interval (1+ index)))
                                                              start-intervals))
                                                (- total-size start-at))))
                                (loop :for i :from start-at :to (1- (+ start-at count))
                                      :do (funcall to-call i))))))
         (flat-indexer-table
           (intraverser
            (:lindex-width +lindex-width+)
            (the (function ((unsigned-byte +lindex-width+)))
                 (lambda (index)
                   (the (function nil)
                        (lambda ()
                          (let* ((start-intervals (the (unsigned-byte +lindex-width+)
                                                       (ceiling (* interval index))))
                                 (start-at (the (unsigned-byte +lindex-width+)
                                                (* sbesize start-intervals)))
                                 (count (the (unsigned-byte +lindex-width+)
                                             (if (< index (1- divisions))
                                                 (* sbesize (- (ceiling (* interval (1+ index)))
                                                               start-intervals))
                                                 (- total-size start-at)))))
                            (loop :for i :from start-at :to (1- (+ start-at count))
                                  :do (funcall to-call i)))))))))
         (encoded-indexer-table
           (intraverser
            (:eindex-width +eindex-width+ :cindex-width +cindex-width+)
            (the (function ((unsigned-byte +eindex-width+)))
                 (lambda (index)
                   ;; (print (list :ee index +eindex-width+))
                   (the (function nil)
                        (lambda ()
                          (let* ((start-intervals (the (unsigned-byte +eindex-width+)
                                                       (ceiling (* interval index))))
                                 (start-at (the (unsigned-byte +eindex-width+)
                                                (* sbesize start-intervals)))
                                 (count (the (unsigned-byte +eindex-width+)
                                             (if (< index (1- divisions))
                                                 (* sbesize (- (ceiling (* interval (1+ index)))
                                                               start-intervals))
                                                 (- total-size start-at))))
                                 (coords (funcall encoder start-at)))
                            (loop :for i :below count
                                  :do (funcall to-call coords)
                                      (when (< i (1- count))
                                        (setf coords (funcall incrementer coords))))))))))))
    ;; (print (list :en encoding-type (list index-type encoding-type)))
    (list (if encoding-type (gethash (list encoding-type index-type) encoded-indexer-table)
              (gethash (list index-type) flat-indexer-table))
          default-indexer)))

(defmethod render ((varray varray) &rest params)
  ;; (declare (optimize (speed 3)))
  (let* ((output-shape (shape-of varray))
         (output-rank (length output-shape))
         (metadata (metadata-of varray))
         (indexer)
         (index-type (or (when (getf metadata :max-size)
                           (loop :for w :in '(8 16 32 64) :when (< (getf metadata :max-size)
                                                                   (expt 2 w))
                                 :return w))
                         t))
         (d-index-type (when (and (> output-rank 0)
                                  (not (eq t index-type)))
                         (let ((fraction (floor index-type output-rank)))
                           (loop :for w :in '(8 16 32 64)
                                 :when (< (getf metadata :max-dim)
                                          (expt 2 w))
                                   :return w))))
         (encoding (when d-index-type
                     ;; encoded integer size that can hold the encoded dimensions,
                     ;; ranging from 8 to 64 bits; for example, a 32-bit integer could hold
                     ;; 4x8 or 2x16-bit dimension indices and a 64-bit integer could hold 8x8,
                     ;; 4x16 or 2x32 dimension indices
                     (let ((fraction (floor index-type output-rank)))
                       (loop :for w :in '(8 16 32 64)
                             :when (>= w (* output-rank d-index-type))
                               :return w))))
         (type-key (intern (format nil "~a~a" (cond (encoding "E")
                                                    (t "I"))
                                   (or encoding index-type))
                           "KEYWORD"))
         (default-generator) (to-subrender))
    
    (when (getf (varray-meta varray) :gen-meta)
      (setf (getf (rest (getf (varray-meta varray) :gen-meta)) :index-type) d-index-type
            (getf (rest (getf (varray-meta varray) :gen-meta)) :indexer-key) type-key
            (getf (rest (getf (varray-meta varray) :gen-meta)) :index-width) encoding))

    (setf (getf metadata :index-width) index-type
          (getf metadata :indexer-key) type-key)

    (multiple-value-bind (this-generator is-not-defaulting)
        (generator-of varray nil (list :indexer-key type-key :index-width d-index-type
                                       :encoding encoding))
      (setf indexer this-generator
            default-generator (not is-not-defaulting)))
    
    (when (and (typep varray 'vader-select)
               (< 0 (size-of varray)) (functionp indexer))
      (funcall indexer 0))
    ;; IPV-TODO: HACK to handle select subrendering, which is only set when the
    ;; first element is generated - figure out a better way to do this
    (setf to-subrender (or (subrendering-p varray)
                           (subrendering-base varray)))

    (if output-shape
        (if (zerop (the (unsigned-byte 62) (reduce #'* output-shape)))
            (let* ((prototype (prototype-of varray))
                   (out-meta (when (arrayp prototype)
                               (make-array 1 :initial-contents
                                           (list (list :empty-array-prototype prototype))))))
              ;; a nil element type results in a t-type array;
              ;; nil types may occur from things like +/⍬
              (if out-meta (make-array output-shape :displaced-to out-meta)
                  (make-array output-shape :element-type (or (etype-of varray) t))))
            (let* ((output (make-array output-shape :element-type (etype-of varray)))
                   (dfactors (when encoding (get-dimensional-factors output-shape t)))
                   ;; the decoder function converts non-row-major index formats like
                   ;; sub-byte-encoded coordinate vectors back to row-major indices
                   ;; to reference elements in the output array
                   (decoder (if (or default-generator (not encoding)) ;; TOGGLE
                                #'identity (decode-rmi encoding d-index-type output-rank dfactors)))
                   (render-index
                     (if to-subrender
                         (lambda (i)
                           (let ((indexed (if (not (functionp indexer))
                                              indexer (funcall indexer i))))
                             (setf (row-major-aref output (funcall decoder i))
                                   (render indexed))))
                         (lambda (i)
                           (if (functionp indexer)
                               (setf (row-major-aref output (funcall decoder i))
                                     (funcall indexer i))
                               (setf (row-major-aref output (funcall decoder i))
                                     indexer)))))
                   (sbsize (sub-byte-element-size output))
                   (sbesize (if sbsize (/ 64 sbsize) 1))
                   (wcadj *workers-count*)
                   (divisions (min wcadj (ceiling (/ (size-of varray) sbesize))))
                   (total-size (size-of varray))
                   (interval (/ total-size sbesize *workers-count*))
                   (lpchannel (lparallel::make-channel))
                   (shape-vector (when (and d-index-type output-rank)
                                   (make-array output-rank :initial-contents (reverse output-shape)
                                                           :element-type (list 'unsigned-byte
                                                                               d-index-type))))
                   (process-pair (get-indexing-function
                                  type-key dfactors shape-vector sbesize interval divisions
                                  total-size d-index-type encoding render-index))
                   (process (or (and (not default-generator)
                                     (first process-pair))
                                (second process-pair)))
                   (threaded-count 0))
              ;; (print (list :pro process-pair))
              ;; (print (list :out (type-of output) (type-of varray)
              ;;              divisions division-size sbesize sbsize
              ;;              (typep varray 'vader-composing)
              ;;              (when (typep varray 'vader-composing)
              ;;                (vacmp-threadable varray))))
              ;; (print (list :ts to-subrender (setf april::ggt varray)))
              (loop :for d :below divisions
                    :do (if ;; (or (and (typep varray 'vader-composing)
                            ;;          (not (vacmp-threadable varray)))
                            ;;     ;; don't thread when rendering the output of operators composed
                            ;;     ;; with side-affecting functions as for {⎕RL←5 1 ⋄ 10?⍵}¨10⍴1000
                            ;;     (loop :for worker :across (lparallel.kernel::workers lparallel::*kernel*)
                            ;;           :never (null (lparallel.kernel::running-category worker))))
                            t
                            (funcall (funcall process d))
                            (progn (incf threaded-count)
                                   (lparallel::submit-task
                                    lpchannel (funcall process d)))))
              (loop :repeat threaded-count
                    :do (lparallel::receive-result lpchannel))
              output))
        (funcall (if (subrendering-p varray)
                     (lambda (item)
                       (let ((rendered (render item)))
                         ;; (print (list :rr rendered item varray
                         ;;              (subrendering-p varray)))
                         ;; (if (typep varray 'vacomp-reduce)
                         ;;     (push varray april::ggg))
                         (if (and (zerop (rank-of rendered))
                                  (or (not (arrayp rendered))
                                      ;; (print (subrendering-p varray))
                                      (and (typep varray 'vacomp-reduce)
                                           (subrendering-p varray))))
                             ;; handle the case of {,/⍵}/3⍴⊂⍳3
                             rendered (enclose rendered))))
                     (lambda (item)
                       (let ((rendered (apply #'render item params)))
                         (if (or (not (shape-of rendered))
                                 (typep varray 'vader-mix) ;; put these in a superclass
                                 (typep varray 'vader-pick))
                             rendered (enclose rendered)))))
                 (if (not (functionp indexer))
                     indexer (funcall indexer 0))))))

(defun segment-length (size section-count)
  "Create a vector of lengths and start points for segments of a vector to be processed in parallel."
  (let* ((section-count (min section-count size))
         (division-size (/ size section-count))
         (start-points (make-array section-count))
         (section-lengths (make-array section-count)))
    (dotimes (i section-count) (setf (aref start-points i) (floor (* i division-size))))
    (dotimes (i section-count) (setf (aref section-lengths i)
                                     (- (if (= i (1- section-count))
                                            size (aref start-points (1+ i)))
                                        (aref start-points i))))
    (values start-points section-lengths)))

(defmacro get-promised (object form)
  `(if ,object (force ,object)
       (progn (setf ,object (promise))
              (fulfill ,object ,form)
              (force ,object))))

(defmacro get-or-assign-shape (object form)
  `(or (varray-shape ,object) (setf (varray-shape ,object) ,form)))

(defclass vad-subrendering ()
  ((%subrendering :accessor vads-subrendering
                  :initform t
                  :initarg :subrendering
                  :documentation "Whether the array contains nested elements to be subrendered."))
  (:metaclass va-class)
  (:documentation "Superclass of derived arrays containing sub-arrays to be rendered."))

(defclass vad-with-io ()
  ((%index-origin :accessor vads-io
                  :initform 0
                  :initarg :index-origin
                  :documentation "Parameter specifying the index origin for an array operation."))
  (:metaclass va-class)
  (:documentation "Superclass of array transformations taking index origin as an implicit argument."))

(defclass vad-with-dfactors ()
  ((%dfactors :accessor vads-dfactors
              :initform nil
              :initarg :dfactors
              :documentation "Array's dimensional factors."))
  (:metaclass va-class)
  (:documentation "Superclass of derived arrays with cached dimensional factors."))

(defclass varray-primal (varray)
  nil (:metaclass va-class)
  (:documentation "A primal array: a virtual array defined wholly by its parameters, not derived from another array."))

(defclass varray-derived (varray)
  ((%base :accessor vader-base
          :initform nil
          :initarg :base
          :documentation "The array from which the array is derived.")
   (%layer :accessor vader-layer
           :initform 0
           :initarg :layer
           :documentation "The number of derived virtual arrays downstream of this array.")
   (%subrendering :accessor vads-subrendering
                  :initform nil
                  :initarg :subrendering
                  :documentation "Whether the array contains nested elements to be subrendered.")
   (%content :accessor vader-content
             :initform nil
             :initarg :inverse
             :documentation "Cached rendered content of the array."))
  (:metaclass va-class)
  (:documentation "A derived array: a virtual array derived from another array."))

(defmethod initialize-instance :around ((varray varray-derived) &key)
  "If the instance's base slot is already bound, it has been populated through one of he above type combinatorics and so should be returned with no changes."
  (when (not (slot-boundp varray '%base))
    (call-next-method))
  
  (when (typep (vader-base varray) 'varray-derived)
    (setf (vader-layer varray) ;; count layers from a non-derived array
          (1+ (vader-layer (vader-base varray))))))

(defmethod shape-of :around ((varray varray-derived))
  (let ((this-shape (call-next-method)))
    (if (varray-meta varray)
        this-shape
        (let* ((this-rank (length this-shape))
               (this-size (reduce #'* this-shape))
               (base-meta (when (typep (vader-base varray) 'varray-derived)
                            (varray-meta (vader-base varray))))
               (base-shape (or (getf base-meta :max-shape)
                               (shape-of (vader-base varray))))
               (max-dim (or (getf base-meta :max-dim)
                            (reduce #'max (or base-shape '(0)))))
               (base-rank (length base-shape))
               (base-size (or (getf base-meta :max-size)
                              (reduce #'* base-shape)))
               (base-lower-rank (< base-rank this-rank))
               (max-shape (if base-lower-rank this-shape base-shape))
               (generator-meta (or (getf base-meta :gen-meta) (list :items))))
          (setf max-shape (if base-lower-rank
                              (loop :for s :in this-shape :for sx :from 0
                                    :collect (let ((item (if (>= sx base-rank)
                                                             s (max s (nth sx base-shape)))))
                                               (setf max-dim (max item max-dim))
                                               item))
                              (loop :for s :in base-shape :for sx :from 0
                                    :collect (let ((item (if (>= sx this-rank)
                                                             s (max s (nth sx this-shape)))))
                                               (setf max-dim (max item max-dim))
                                               item))))
          
          (setf (getf (varray-meta varray) :max-size) (max this-size base-size)
                (getf (varray-meta varray) :max-shape) max-shape
                (getf (varray-meta varray) :max-dim) max-dim
                (getf (varray-meta varray) :gen-meta) generator-meta)
          this-shape))))

(defmethod etype-of ((varray varray-derived))
  "The default shape of a derived array is the same as its base array."
  (if (varrayp (vader-base varray))
      (etype-of (vader-base varray))
      (if (arrayp (vader-base varray))
          (array-element-type (vader-base varray))
          (assign-element-type (vader-base varray)))))

(defmethod prototype-of ((varray varray-derived))
  (let ((shape (shape-of varray)))
    ;; (print (list :vd varray (vader-base varray)
    ;;              (print (prototype-of (vader-base varray)))
    ;;              (subrendering-p varray)
    ;;              (subrendering-p (vader-base varray))))
    ;; (print (list :ba varray (vader-base varray) shape
    ;;              (render (vader-base varray))))
    (if (or (not shape) (loop :for dim :in shape :never (zerop dim)))
        (if (and (not (or (typep varray 'vader-expand)
                          (typep varray 'vader-catenate)))
                 ;; TODO: functions that combine an array of arguments shouldn't have base subrendering
                 ;; checked. Is there a better way to establish this rule?
                 (subrendering-p (vader-base varray)))
            (aplesque::make-empty-array (disclose (render (vader-base varray))))
            (if (subrendering-p varray)
                (aplesque::make-empty-array (disclose (render (vader-base varray))))
                ;; (prototype-of (disclose (render (vader-base varray))))
                (let* ((indexer (generator-of varray))
                       (indexed (if (not (functionp indexer))
                                    indexer (funcall indexer 0))))
                  ;; (print (list :aaa indexed varray))
                  ;; (print (list :in indexed (typep indexed 'varray) (type-of indexed)
                  ;;              (if (varrayp indexed) (vader-base indexed))))
                  ;; TODO: remove-disclose when [⍴ shape] is virtually implemented
                  (if indexed (if (typep indexed 'varray)
                                  (prototype-of indexed)
                                  (aplesque::make-empty-array (disclose indexed)))
                      (prototype-of (vader-base varray))))))
        (prototype-of (vader-base varray)))))

(defmethod shape-of ((varray varray-derived))
  "The default shape of a derived array is the same as the original array."
  (get-promised (varray-shape varray) (shape-of (vader-base varray))))

(defmethod base-indexer-of ((varray varray-derived) &optional params)
  "The default shape of a derived array is the same as the original array."
  (let ((this-shape (shape-of varray)))
    (generator-of (vader-base varray) nil
                  (append (list :shape-deriving (if (typep varray 'vader-reshape)
                                                  (shape-of varray)
                                                  (if (and (typep varray 'vader-section)
                                                           (= 1 (size-of (vads-argument varray))))
                                                      (funcall (lambda (item)
                                                                 (if (typep item 'sequence)
                                                                     (coerce item 'list)
                                                                     (list item)))
                                                               (render (vads-argument varray))))))
                        params))))