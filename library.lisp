;;; -*- Mode:Lisp; Syntax:ANSI-Common-Lisp; Coding:utf-8; Package:April -*-
;;;; library.lisp

(in-package #:april)

"This file contains the functions in April's 'standard library' that aren't provided by the aplesque package, mostly functions that are specific to the APL language and not generally applicable to array processing."

(defun without (omega alpha)
  (flet ((compare (o a)
	   (funcall (if (and (characterp a) (characterp o))
			#'char= (if (and (numberp a) (numberp o))
				    #'= (lambda (a o) (declare (ignore a o)))))
		    o a)))
    (let ((included)
	  (omega-vector (if (or (vectorp omega)	(not (arrayp omega)))
			    (disclose omega)
			    (make-array (list (array-total-size omega))
					:displaced-to omega :element-type (element-type omega)))))
      (loop :for element :across alpha
	 :do (let ((include t))
	       (if (vectorp omega-vector)
		   (loop :for ex :across omega-vector
		      :do (if (compare ex element) (setq include nil)))
		   (if (compare omega-vector element) (setq include nil)))
	       (if include (setq included (cons element included)))))
      (make-array (list (length included)) :element-type (element-type alpha)
		  :initial-contents (reverse included)))))

(defun scalar-compare (omega alpha)
  (funcall (if (and (characterp alpha) (characterp omega))
	       #'char= (if (and (numberp alpha) (numberp omega))
			   #'= (lambda (a o) (declare (ignore a o)))))
	   omega alpha))

(defun count-to (index index-origin)
  "Implementation of APL's ⍳ function."
  (let ((index (disclose index)))
    (if (integerp index)
	(if (= 0 index) (vector)
	    (let ((output (make-array (list index) :element-type (list 'integer 0 index))))
	      (loop :for ix :below index :do (setf (aref output ix) (+ ix index-origin)))
	      output))
	(if (vectorp index)
	    (let ((output (make-array (array-to-list index))))
	      (across output (lambda (elem coords)
			       (setf (apply #'aref output coords)
				     (make-array (length index)
						 :element-type
						 (list 'integer 0 (+ index-origin
								     (reduce #'max coords)))
						 :initial-contents
						 (if (= 0 index-origin)
						     coords (loop :for c :in coords
							       :collect (+ c index-origin)))))))
	      output)
	    (error "The argument to ⍳ must be an integer, i.e. ⍳9, or a vector, i.e. ⍳2 3.")))))

(defun shape (omega)
  (if (or (not (arrayp omega))
	  (= 0 (rank omega)))
      #() (if (and (eql 'simple-array (first (type-of omega)))
		   (eq t (second (type-of omega)))
		   (eq nil (third (type-of omega))))
	      0 (if (vectorp omega)
		    (make-array 1 :element-type (list 'integer 0 (length omega))
				:initial-contents (list (length omega)))
		    (let* ((omega-dims (dims omega))
			   (max-dim (reduce #'max omega-dims)))
		      (make-array (list (length omega-dims))
				  :initial-contents omega-dims :element-type (list 'integer 0 max-dim)))))))

(defun at-index (omega alpha axes index-origin)
  "Find the value(s) at the given index or indices in an array. Used to implement [⌷ index]."
  (if (not (arrayp omega))
      (if (and (numberp alpha)
	       (= index-origin alpha))
	  omega (error "Invalid index."))
      (choose omega (let ((coords (funcall (if (arrayp alpha) #'array-to-list #'list)
					   (apply-scalar #'- alpha index-origin)))
			  ;; the inefficient array-to-list is used here in case of nested
			  ;; alpha arguments like (⊂1 2 3)⌷...
			  (axis (if (first axes) (loop :for item :across (first axes)
						    :collect (- item index-origin)))))
		      (if (not axis)
			  ;; pad coordinates with nil elements in the case of an elided reference
			  (append coords (loop :for i :below (- (rank omega) (length coords)) :collect nil))
			  (loop :for dim :below (rank omega)
			     :collect (if (member dim axis) (first coords))
			     :when (member dim axis) :do (setq coords (rest coords))))))))

(defun segments (item)
  (cond ((or (characterp item)
	     (stringp item)
	     (integerp item))
	 1)
	((rationalp item) 2)
	((floatp item) 2)
	((complexp item) (+ (segments (realpart item))
			    (segments (imagpart item))))))

(defun find-depth (omega)
  "Find the depth of an array. Used to implement [≡ depth]."
  (if (not (arrayp omega))
      0 (array-depth omega)))

(defun find-first-dimension (omega)
  "Find the first dimension of an array. Used to implement [≢ first dimension]."
  (if (not (arrayp omega))
      1 (first (dims omega))))

(defun membership (omega alpha)
  (flet ((compare (item1 item2)
	   (if (and (characterp item1) (characterp item2))
	       (char= item1 item2)
	       (if (and (numberp item1) (numberp item2))
		   (= item1 item2)
		   (if (and (arrayp item1) (arrayp item2))
		       (array-compare item1 item2))))))
    (if (not (arrayp alpha))
	(if (not (arrayp omega))
	    (if (compare omega alpha) 1 0)
	    (if (not (loop :for item :across omega :never (compare item alpha)))
		1 0))
	(let* ((output (make-array (dims alpha) :element-type 'bit :initial-element 0))
	       (omega (enclose omega))
	       (to-search (if (vectorp omega)
			      omega (make-array (array-total-size omega)
						:displaced-to omega :element-type (element-type omega)))))
	  ;; TODO: this could be faster with use of a hash table and other additions
	  (dotimes (index (array-total-size output))
	    (let ((found))
	      (loop :for item :across to-search :while (not found)
		 :do (setq found (compare item (row-major-aref alpha index))))
	      (if found (setf (row-major-aref output index) 1))))
	  output))))
  
(defun where-equal-to-one (omega index-origin)
  "Return a vector of coordinates from an array where the value is equal to one. Used to implement [⍸ where]."
  (let* ((indices) (match-count 0)
	 (orank (rank omega)))
    (if (= 0 orank)
	(if (= 1 omega) 1 0)
	(progn (across omega (lambda (index coords)
			       (declare (dynamic-extent index coords))
			       (if (= 1 index)
				   (let* ((max-coord 0)
					  (coords (mapcar (lambda (i)
							    (setq max-coord
								  (max max-coord (+ i index-origin)))
							    (+ i index-origin))
							  coords)))
				     (incf match-count)
				     (setq indices (cons (if (< 1 orank)
							     (nest (make-array
								    orank :element-type (list 'integer 0 max-coord)
								    :initial-contents coords))
							     (first coords))
							 indices))))))
	       (if (not indices)
		   0 (make-array (list match-count)
				 :element-type (if (< 1 orank)
						   t (list 'integer 0 (reduce #'max indices)))
				 :initial-contents (reverse indices)))))))

(defun tabulate (omega)
  "Return a two-dimensional array of values from an array, promoting or demoting the array if it is of a rank other than two. Used to implement [⍪ table]."
  (if (not (arrayp omega))
      omega (if (vectorp omega)
		(let ((output (make-array (list (length omega) 1) :element-type (element-type omega))))
		  (loop :for i :below (length omega) :do (setf (row-major-aref output i) (aref omega i)))
		  output)
		(let ((o-dims (dims omega)))
		  (make-array (list (first o-dims) (reduce #'* (rest o-dims)))
			      :element-type (element-type omega)
			      :displaced-to (copy-array omega))))))

(defun ravel-array (index-origin)
  (lambda (omega &optional axes)
    (ravel index-origin omega axes)))

(defun catenate-arrays (index-origin)
  (lambda (omega alpha &optional axes)
    (let ((axis *first-axis-or-nil*))
      (if (floatp axis)
	  ;; laminate in the case of a fractional axis argument
	  (laminate alpha omega (ceiling axis))
	  ;; simply stack the arrays if there is no axis argument or it's an integer
	  (catenate alpha omega (or axis (max 0 (1- (max (rank alpha) (rank omega))))))))))

(defun catenate-on-first (index-origin)
  (lambda (omega alpha &optional axes)
    (if (and (vectorp alpha) (vectorp omega))
	(if (and *first-axis-or-nil* (< 0 *first-axis-or-nil*))
	    (error (concatenate 'string "Specified axis is greater than 1, vectors"
				" have only one axis along which to catenate."))
	    (if (and axes (> 0 *first-axis-or-nil*))
		(error (format nil "Specified axis is less than ~a." index-origin))
		(catenate alpha omega 0)))
	(if (or (not axes)
		(integerp (first axes)))
	    (catenate alpha omega (or *first-axis-or-nil* 0))))))

(defun section-array (index-origin &optional inverse)
  (lambda (omega alpha &optional axes)
    (let ((omega (enclose omega))
	  (alpha-index alpha)
	  (alpha (if (arrayp alpha)
		     alpha (vector alpha))))
      (section omega (if axes (make-array (rank omega)
					  :initial-contents
					  (loop :for axis :below (rank omega)
					     :collect (if inverse (if (/= axis (- (first axes) index-origin))
								      0 alpha-index)
							  (if (= axis (- (first axes) index-origin))
							      alpha-index (nth axis (dims omega))))))
			 alpha)
	       :inverse inverse))))

(defun pick (index-origin)
  "Fetch an array element, within successively nested arrays for each element of the left argument."
  (lambda (omega alpha)
    (labels ((pick-point (point input)
	       (if (is-unitary point)
		   (let ((point (disclose point)))
		     ;; if this is the last level of nesting specified, fetch the element
		     (if (not (arrayp point))
			 (aref input (- point index-origin))
			 (if (vectorp point)
			     (apply #'aref input (loop :for p :across point :collect (- p index-origin)))
			     (error "Coordinates for ⊃ must be expressed by scalars or vectors."))))
		   ;; if there are more elements of the left argument left to go, recurse on the element designated
		   ;; by the first element of the left argument and the remaining elements of the point
		   (pick-point (if (< 2 (length point))
				   (make-array (1- (length point))
					       :initial-contents (loop :for i :from 1 :to (1- (length point))
								    :collect (aref point i)))
				   (aref point 1))
			       (disclose (pick-point (aref point 0) input))))))
      ;; TODO: swap out the vector-based point for an array-based point
      (if (= 1 (array-total-size omega))
	  (error "Right argument to dyadic ⊃ may not be unitary.")
	  (disclose (pick-point alpha omega))))))

(defun array-intersection (omega alpha)
  "Return a vector of values common to two arrays. Used to implement [∩ intersection]."
  (let ((omega (enclose omega))
	(alpha (enclose alpha)))
    (if (or (not (vectorp alpha))
	    (not (vectorp omega)))
	(error "Arguments must be vectors.")
	(let* ((match-count 0)
	       (matches (loop :for item :across alpha :when (find item omega :test #'array-compare)
			   :collect item :and :do (incf match-count))))
	  (if (= 1 match-count)
	      (first matches)
	      (make-array (list match-count) :initial-contents matches
			  :element-type (type-in-common (element-type alpha) (element-type omega))))))))

(defun unique (omega)
  "Return a vector of unique values in an array. Used to implement [∪ unique]."
  (if (not (arrayp omega))
      omega (let ((vector (if (vectorp omega)
			      omega (re-enclose omega (make-array (1- (rank omega))
								  :element-type 'fixnum
								  :initial-contents
								  (loop :for i :from 1 :to (1- (rank omega))
								     :collect i))))))
	      (let ((uniques) (unique-count 0))
		(loop :for item :across vector :when (not (find item uniques :test #'array-compare))
		   :do (setq uniques (cons item uniques)
			     unique-count (1+ unique-count)))
		(if (= 1 unique-count)
		    (disclose (first uniques))
		    (make-array unique-count :element-type (element-type vector)
				:initial-contents (reverse uniques)))))))

(defun array-union (omega alpha)
  "Return a vector of unique values from two arrays. Used to implement [∪ union]."
  (let ((omega (enclose omega))
	(alpha (enclose alpha)))
    (if (or (not (vectorp alpha))
	    (not (vectorp omega)))
	(error "Arguments must be vectors.")
	(let* ((unique-count 0)
	       (uniques (loop :for item :across omega :when (not (find item alpha :test #'array-compare))
			   :collect item :and :do (incf unique-count))))
	  (catenate alpha (make-array unique-count :initial-contents uniques
				      :element-type (type-in-common (element-type alpha)
								    (element-type omega)))
		    0)))))

(defun unique-mask (array)
  (let ((output (make-array (first (dims array)) :element-type 'bit :initial-element 1))
	(displaced (if (< 1 (rank array)) (make-array (rest (dims array))
						      :displaced-to array
						      :element-type (element-type array))))
	(uniques) (increment (reduce #'* (rest (dims array)))))
    (loop :for x :below (first (dims array))
       :do (if (and displaced (< 0 x))
	       (adjust-array displaced (rest (dims array))
			     :displaced-to array :element-type (element-type array)
			     :displaced-index-offset (* x increment)))
       (if (member (or displaced (aref array x)) uniques :test #'array-compare)
	   (setf (aref output x) 0)
	   (setf uniques (cons (if displaced (make-array (rest (dims array)) :displaced-to array
							 :element-type (element-type array)
							 :displaced-index-offset (* x increment))
				   (aref array x))
			       uniques))))
    output))

(defun permute-array (index-origin)
  (lambda (omega &optional alpha)
    (if (not (arrayp omega))
	omega (aops:permute (if alpha (loop :for i :across (enclose alpha) :collect (- i index-origin))
				(loop :for i :from (1- (rank omega)) :downto 0 :collect i))
			    omega))))

(defun matrix-inverse (omega)
  (if (not (arrayp omega))
      (/ omega)
      (if (< 2 (rank omega))
	  (error "Matrix inversion only works on arrays of rank 2 or 1.")
	  (if (and (= 2 (rank omega)) (reduce #'= (dims omega)))
	      (invert-matrix omega)
	      (left-invert-matrix omega)))))

(defun matrix-divide (omega alpha)
  (each-scalar t (array-inner-product (invert-matrix omega)
				      alpha (lambda (arg1 arg2) (apply-scalar #'* arg1 arg2))
				      #'+)))

(defun encode (omega alpha)
  "Encode a number or array of numbers as per a given set of bases. Used to implement [⊤ encode]."
  (let* ((omega (if (arrayp omega)
		    omega (enclose omega)))
	 (alpha (if (arrayp alpha)
		    alpha (enclose alpha)))
	 (odims (dims omega)) (adims (dims alpha))
	 (last-adim (first (last adims)))
	 (out-coords (loop :for i :below (+ (- (rank alpha) (count 1 adims))
					    (- (rank omega) (count 1 odims))) :collect 0))
	 (output (make-array (or (append (loop :for dim :in adims :when (< 1 dim) :collect dim)
					 (loop :for dim :in odims :when (< 1 dim) :collect dim))
				 '(1))))
	 (dxc))
    (flet ((rebase (base-coords number)
	     (let ((operand number) (last-base 1)
		   (base 1) (component 1) (element 0))
	       (loop :for index :from (1- last-adim) :downto (first (last base-coords))
		  :do (setq last-base base
			    base (* base (apply #'aref alpha (append (butlast base-coords 1)
								     (list index))))
			    component (if (= 0 base)
					  operand (* base (nth-value 1 (floor (/ operand base)))))
			    operand (- operand component)
			    element (/ component last-base)))
	       element)))
      (across alpha (lambda (aelem acoords)
		      (declare (ignore aelem) (dynamic-extent acoords))
		      (across omega (lambda (oelem ocoords)
				      (declare (dynamic-extent oelem ocoords))
				      (setq dxc 0)
				      (if out-coords
					  (progn (loop :for dx :below (length acoords) :when (< 1 (nth dx adims))
						    :do (setf (nth dxc out-coords) (nth dx acoords)
							      dxc (1+ dxc)))
						 (loop :for dx :below (length ocoords) :when (< 1 (nth dx odims))
						    :do (setf (nth dxc out-coords) (nth dx ocoords)
							      dxc (1+ dxc)))))
				      (setf (apply #'aref output (or out-coords '(0)))
					    (rebase acoords oelem))))))
      (if (is-unitary output)
	  (disclose output)
	  (each-scalar t output)))))

(defun decode (omega alpha)
  "Decode an array of numbers as per a given set of bases. Used to implement [⊥ decode]."
  (let* ((omega (if (arrayp omega)
		    omega (enclose omega)))
	 (alpha (if (arrayp alpha)
		    alpha (enclose alpha)))
	 (odims (dims omega)) (adims (dims alpha))
	 (last-adim (first (last adims)))
	 (rba-coords (loop :for i :below (rank alpha) :collect 0))
	 (rbo-coords (loop :for i :below (rank omega) :collect 0))
	 (out-coords (loop :for i :below (max 1 (+ (1- (rank alpha)) (1- (rank omega)))) :collect 0))
	 (output (make-array (or (append (butlast adims 1) (rest odims)) '(1))))
	 (dxc))
    (flet ((rebase (base-coords number-coords)
	     (let ((base 1) (result 0) (bclen (length base-coords)))
	       (loop :for i :from 0 :to (- bclen 2)
		  :do (setf (nth i rba-coords) (nth i base-coords)))
	       (loop :for i :from 1 :to (1- (length number-coords))
		  :do (setf (nth i rbo-coords) (nth i number-coords)))
	       (if (and (not (is-unitary base-coords))
			(not (is-unitary number-coords))
			(/= (first odims) (first (last adims))))
		   (error (concatenate 'string "If neither argument to ⊥ is scalar, the first dimension"
				       " of the right argument must equal the last "
				       "dimension of the left argument."))
		   (loop :for index :from (if (< 1 last-adim) (1- last-adim) (1- (first odims)))
		      :downto 0 :do (setf (nth 0 rbo-coords) (if (< 1 (first odims)) index 0)
					  (nth (1- bclen) rba-coords) (if (< 1 last-adim) index 0))
			(incf result (* base (apply #'aref omega rbo-coords)))
			(setq base (* base (apply #'aref alpha rba-coords)))))
	       result)))
      (across alpha (lambda (aelem acoords)
		      (declare (ignore aelem) (dynamic-extent acoords))
		      (across omega (lambda (oelem ocoords)
				      (declare (ignore oelem) (dynamic-extent ocoords))
				      (setq dxc 0)
				      (loop :for dx :below (1- (length acoords))
					 :do (setf (nth dxc out-coords) (nth dx acoords)
						   dxc (1+ dxc)))
				      (if ocoords (loop :for dx :from 1 :to (1- (length ocoords))
						     :do (setf (nth dxc out-coords) (nth dx ocoords)
							       dxc (1+ dxc))))
				      (setf (apply #'aref output (or out-coords '(0)))
					    (rebase acoords ocoords)))
			      :elements (loop :for i :below (rank omega) :collect (if (= i 0) 0)))))
      :elements (loop :for i :below (rank alpha) :collect (if (= i (1- (rank alpha))) 0)))
    (if (is-unitary output) (disclose output) (each-scalar t output))))

(defun left-invert-matrix (in-matrix)
  "Perform left inversion of matrix. Used to implement [⌹ matrix inverse]."
  (let* ((input (if (= 2 (rank in-matrix))
		    in-matrix (make-array (list (length in-matrix) 1))))
	 (input-displaced (if (/= 2 (rank in-matrix))
			      (make-array (list 1 (length in-matrix)) :element-type (element-type input)
					  :displaced-to input))))
    (if input-displaced (loop :for i :below (length in-matrix) :do (setf (row-major-aref input i)
									 (aref in-matrix i))))
    (let ((result (array-inner-product (invert-matrix (array-inner-product (or input-displaced
									       (aops:permute '(1 0) input))
									   input #'* #'+))
				       (or input-displaced (aops:permute '(1 0) input))
				       #'* #'+)))
      (if (= 1 (rank in-matrix))
	  (make-array (size result) :element-type (element-type result) :displaced-to result)
	  result))))

(defun format-array (print-precision)
  (lambda (omega &optional alpha)
    (if (not alpha)
	(array-impress omega :collate t
		       :segment (lambda (number &optional segments)
				  (aplesque::count-segments number print-precision segments))
		       :format (lambda (number &optional segments)
				 (print-apl-number-string number segments print-precision)))
	(if (not (integerp alpha))
	    (error (concatenate 'string "The left argument to ⍕ must be an integer specifying"
				" the precision at which to print floating-point numbers."))
	    (array-impress omega :collate t
			   :segment (lambda (number &optional segments)
				      (aplesque::count-segments number (- alpha) segments))
			   :format (lambda (number &optional segments)
				     (print-apl-number-string number segments print-precision alpha)))))))

(defun generate-index-array (array)
  (let ((output (make-array (dims array) :element-type (list 'integer 0 (size array)))))
    (loop :for i :below (size array) :do (setf (row-major-aref output i) i))
    output))

(defun assign-selected (array indices values)
  (if (or (= 0 (rank values))
	  (and (= (rank indices) (rank values))
	       (loop :for i :in (dims indices) :for v :in (dims values) :always (= i v))))
      (let ((output (if (and (= 0 (rank values))
			     (or (eq t (element-type array))
				 (and (listp (type-of array))
				      (or (eql 'simple-vector (first (type-of array)))
					  (and (eql 'simple-array (first (type-of array)))
					       (typep values (second (type-of array))))))))
			array (make-array (dims array) :element-type (if (/= 0 (rank values))
									 t (assign-element-type values))))))
	(loop :for i :below (size array) :do (setf (row-major-aref output i) (row-major-aref array i)))
	(loop :for i :below (size indices) :do (setf (row-major-aref output (row-major-aref indices i))
						     (if (= 0 (rank values))
							 values (row-major-aref values i))))
	output)
      (error "Area of array to be reassigned does not match shape of values to be assigned.")))

(defmacro apply-reducing (operation-symbol operation axes &optional first-axis)
  (let ((omega (gensym)) (o (gensym)) (a (gensym)) (symstring (string operation-symbol)))
    `(lambda (,omega)
       (if (= 0 (size ,omega))
	   (if (/= 1 (rank ,omega))
	       ;; if reducing an empty vector, return the identity operator for compatible lexical functions
	       ;; higher-dimensional empty arrays will yield an [⍬ empty vector]
	       #() ,(or (if (= 1 (length symstring))
			    (second (assoc (aref symstring 0)
					   '((#\+ 0) (#\- 0) (#\× 1) (#\÷ 1) (#\⋆ 1) (#\* 1) (#\! 1) 
					     (#\< 0) (#\≤ 1) (#\= 1) (#\≥ 1) (#\> 0) (#\≠ 0) (#\| 0)
					     (#\^ 1) (#\∧ 1) (#\∨ 0) (#\⌈ most-negative-long-float)
					     (#\⌊ most-positive-long-float))
					   :test #'char=)))
			'(error "Invalid function for reduction of empty array.")))
	   (if (= 1 (size ,omega))
	       ,omega (disclose-atom
		       (do-over ,omega (lambda (,o ,a) (apl-call ,operation-symbol ,operation ,a ,o))
				,(if axes `(- ,(first axes) index-origin)
				     (if first-axis 0 `(1- (rank ,omega))))
				:reduce t :in-reverse t)))))))

(defmacro apply-scanning (operation-symbol operation axes &optional first-axis)
  (let ((omega (gensym)) (o (gensym)) (a (gensym)))
    `(lambda (,omega)
       (do-over ,omega (lambda (,o ,a) (apl-call ,operation-symbol ,operation ,o ,a))
		,(if axes `(- ,(first axes) index-origin)
		     (if first-axis 0 `(1- (rank ,omega))))))))

(defmacro apply-to-each (symbol operation-monadic operation-dyadic)
  (let ((index (gensym)) (coords (gensym)) (output (gensym)) (item (gensym))
	(omega (gensym)) (alpha (gensym)) (a (gensym)) (o (gensym))
	(monadic-op (if (and (listp operation-monadic)
			     (eql 'with-properties (first operation-monadic)))
			(third operation-monadic) operation-monadic))
	(dyadic-op (if (and (listp operation-dyadic)
			    (eql 'with-properties (first operation-dyadic)))
		       (third operation-monadic) operation-dyadic)))
    (flet ((expand-dyadic (a1 a2 &optional reverse)
	     ;; the enclose-clause here and the (arrayp ,a1) clause below are added just so that the compiled
	     ;; clause will not cause problems when expanding with an explicit scalar argument, as with 3/¨⍳3
	     (let ((call (if reverse `(nest (apl-call ,symbol ,dyadic-op ,index ,a2))
			     `(nest (apl-call ,symbol ,dyadic-op ,a2 ,index)))))
	       `(let ((,output (make-array (dims ,a1))))
		  (across ,a1 (lambda (,index ,coords)
				(declare (dynamic-extent ,index ,coords))
				(setf (apply #'aref ,output ,coords)
				      (each-scalar t ,call))))
		  ,output))))
      `(lambda (,omega &optional ,alpha)
	 (declare (ignorable ,alpha))
	 (each-scalar
	  t ,(if (or (not (listp dyadic-op))
		     (not (listp (second dyadic-op)))
		     (< 1 (length (second dyadic-op))))
		 ;; don't create the dyadic clauses if the function being passed is monadic-only
		 `(if ,alpha (cond ((not (arrayp ,omega))
				    ,(expand-dyadic alpha omega))
				   ((not (arrayp ,alpha))
				    ,(expand-dyadic omega alpha t))
				   ((is-unitary ,omega)
				    ,(expand-dyadic alpha `(disclose ,omega)))
				   ((is-unitary ,alpha)
				    ,(expand-dyadic omega `(disclose ,alpha) t))
				   ((and (= (size ,alpha) (size ,omega))
					 (= (rank ,alpha) (rank ,omega))
					 (loop :for ,a :in (dims ,alpha) :for ,o :in (dims ,omega)
					      :always (= ,a ,o)))
				    (aops:each (lambda (,o ,a)
						 (nest (apl-call ,symbol ,dyadic-op ,o ,a)))
					       ,omega ,alpha))
				   (t (error "Mismatched argument shapes to ¨.")))
		      (aops:each (lambda (,item) (nest (apl-call ,symbol ,monadic-op (disclose ,item))))
				 ,omega))
		 `(aops:each (lambda (,item) (nest (apl-call ,symbol ,monadic-op (disclose ,item))))
			     ,omega)))))))

(defmacro apply-commuting (symbol operation-dyadic)
  (let ((omega (gensym)) (alpha (gensym)))
    `(lambda (,omega &optional ,alpha)
       (apl-call ,symbol ,operation-dyadic (if ,alpha ,alpha ,omega)
		 ,omega))))

(defmacro apply-to-grouped (symbol operation-dyadic)
  ;; TODO: eliminate consing here
  (let ((key (gensym)) (keys (gensym)) (key-test (gensym)) (indices-of (gensym))
	(key-table (gensym)) (key-list (gensym)) (item-sets (gensym)) (li (gensym))
	(item (gensym)) (items (gensym)) (vector (gensym)) (coords (gensym))
	(alpha (gensym)) (omega (gensym)))
    `(lambda (,omega &optional ,alpha)
       (let* ((,keys (if ,alpha ,alpha ,omega))
	      (,key-test #'equalp)
	      (,indices-of (lambda (,item ,vector)
			     (loop :for ,li :below (length ,vector)
				:when (funcall ,key-test ,item (aref ,vector ,li))
				:collect (+ index-origin ,li))))
	      (,key-table (make-hash-table :test ,key-test))
	      (,key-list))
	 (across ,keys (lambda (,item ,coords)
			 (declare (dynamic-extent ,item ,coords))
			 (if (loop :for ,key :in ,key-list :never (funcall ,key-test ,item ,key))
			     (setq ,key-list (cons ,item ,key-list)))
			 (setf (gethash ,item ,key-table)
			       (cons (apply #'aref (cons ,omega ,coords))
				     (gethash ,item ,key-table)))))
	 (let* ((,item-sets (loop :for ,key :in (reverse ,key-list)
			       :collect (apl-call ,symbol ,operation-dyadic
						  (let ((,items (if ,alpha (gethash ,key ,key-table)
								    (funcall ,indices-of
									     ,key ,keys))))
						    (make-array (list (length ,items))
								:initial-contents
								(reverse ,items)))
						  ,key))))
	   (mix-arrays 1 (apply #'vector ,item-sets)))))))

(defmacro apply-producing-inner (right-symbol right-operation left-symbol left-operation)
  (let* ((op-right `(lambda (alpha omega) (apl-call ,right-symbol ,right-operation omega alpha)))
	 (op-left `(lambda (alpha omega) (apl-call ,left-symbol ,left-operation omega alpha)))
	 (result (gensym)) (arg1 (gensym)) (arg2 (gensym)) (alpha (gensym)) (omega (gensym)))
    `(lambda (,omega ,alpha)
       (if (and (not (arrayp ,omega))
		(not (arrayp ,alpha)))
	   (funcall (lambda (,result)
		      (if (not (and (arrayp ,result) (< 1 (rank ,result))))
			  ,result (vector ,result)))
		    ;; enclose the result in a vector if its rank is > 1
		    ;; to preserve the rank of the result
		    (reduce ,op-left (aops:each (lambda (e) (aops:each #'disclose e))
						(apply-scalar ,op-right ,alpha ,omega))))
	   (each-scalar t (array-inner-product ,alpha ,omega
					       (lambda (,arg1 ,arg2)
						 (if (or (arrayp ,arg1) (arrayp ,arg2))
						     (apply-scalar ,op-right ,arg1 ,arg2)
						     (funcall ,op-right ,arg1 ,arg2)))
					       ,op-left))))))

(defmacro apply-producing-outer (right-symbol right-operation)
  (let* ((op-right `(lambda (alpha omega) (apl-call ,right-symbol ,right-operation omega alpha)))
	 (inverse (gensym)) (element (gensym)) (alpha (gensym)) (omega (gensym)) (a (gensym)) (o (gensym))
	 (placeholder (gensym)))
    `(lambda (,omega ,alpha)
       (if (or (not (or (not (arrayp ,omega)) (not (arrayp ,alpha))
			(dims ,omega) (dims ,alpha)))
       	       (= 0 (size ,omega)) (= 0 (size ,alpha)))
	   ;; if the arguments are empty, return an empty array with the dimensions of the arguments appended
	   (make-array (append (dims ,alpha) (dims ,omega)))
	   (if (is-unitary ,omega)
	       (if (is-unitary ,alpha)
		   (nest (apl-call :fn ,op-right ,alpha ,omega))
		   (each-scalar t (aops:each (lambda (,element)
					       (let ((,a ,element)
						     (,o (disclose-unitary-array (disclose ,omega))))
						 (nest (apl-call :fn ,op-right ,a ,o))))
					     ,alpha)))
	       (if (is-unitary ,alpha)
		   (each-scalar t (aops:each (lambda (,element)
					       (let ((,o ,element)
						     (,a (disclose-unitary-array (disclose ,alpha))))
						 (nest (apl-call :fn ,op-right ,a ,o))))
					     ,omega))
		   (let ((,inverse (aops:outer (lambda (,o ,a)
						 (let ((,o (if (= 0 (rank ,o)) (disclose ,o)
							       (if (arrayp ,o) ,o (vector ,o))))
						       (,a (if (= 0 (rank ,a)) (disclose ,a)
							       (if (arrayp ,a) ,a (vector ,a)))))
						   ',right-operation
						   (if (is-unitary ,o)
						       ;; swap arguments in case of a
						       ;; unitary omega argument
						       (let ((,placeholder ,a))
							 (setq ,a ,o
							       ,o ,placeholder)))
						   (each-scalar t (nest
								   (funcall
								    ;; disclose the output of
								    ;; user-created functions; otherwise
								    ;; fn←{⍺×⍵+1}
								    ;; 1 2 3∘.fn 4 5 6 (for example)
								    ;; will fail
								    ,(if (and (listp right-operation)
									      (or (eq 'function
										      (first right-operation))
										  (eq 'scalar-function
										      (first right-operation))))
									 '#'disclose '#'identity)
								    (apl-call :fn ,op-right ,a ,o))))))
					       ,alpha ,omega)))
		     (each-scalar t (if (not (is-unitary ,alpha))
					,inverse (aops:permute (reverse (alexandria:iota (rank ,inverse)))
							       ,inverse))))))))))

(defmacro apply-composed (right-symbol right-value right-function-monadic right-function-dyadic
			    left-symbol left-value left-function-monadic left-function-dyadic is-confirmed-monadic)
  (let* ((alpha (gensym)) (omega (gensym)) (processed (gensym))
	 (fn-right (or right-function-monadic right-function-dyadic))
	 (fn-left (or left-function-monadic left-function-dyadic)))
    `(lambda (,omega &optional ,alpha)
       (declare (ignorable ,alpha))
       ,(if (and fn-right fn-left)
	    (let ((clauses (list `(apl-call ,left-symbol ,left-function-dyadic ,processed ,alpha)
				 `(apl-call ,left-symbol ,left-function-monadic ,processed))))
	      `(let ((,processed (apl-call ,right-symbol ,right-function-monadic ,omega)))
		 ,(if is-confirmed-monadic (second clauses)
		      `(if ,alpha ,@clauses))))
	    `(apl-call :fn ,(or right-function-dyadic left-function-dyadic)
		       ,(if (not fn-right) right-value omega)
		       ,(if (not fn-left) left-value omega))))))

(defmacro apply-at-rank (right-value left-symbol left-function-monadic left-function-dyadic)
  (let ((rank (gensym)) (orank (gensym)) (arank (gensym)) (fn (gensym))
	(romega (gensym)) (ralpha (gensym)) (alpha (gensym)) (omega (gensym))
	(o (gensym)) (a (gensym)) (r (gensym)))
    ;; TODO: eliminate consing here
    `(lambda (,omega &optional ,alpha)
       (let* ((,rank (disclose ,right-value))
	      (,orank (rank ,omega))
	      (,arank (rank ,alpha))
	      (,fn (if (not ,alpha)
		       (lambda (,o) (apl-call ,left-symbol ,left-function-monadic ,o))
		       (lambda (,o ,a) (apl-call ,left-symbol ,left-function-dyadic ,o ,a))))
	      (,romega (if (and ,omega (< ,rank ,orank))
			   (re-enclose ,omega (each (lambda (,r) (- ,r index-origin))
						    (make-array (list ,rank)
								:initial-contents
								(nthcdr (- ,orank ,rank)
									(iota ,orank :start index-origin)))))))
	      (,ralpha (if (and ,alpha (< ,rank ,arank))
			   (re-enclose ,alpha (each (lambda (,r) (- ,r index-origin))
						    (make-array (list ,rank)
								:initial-contents
								(nthcdr (- ,arank ,rank)
									(iota ,arank :start index-origin))))))))
	 (if ,alpha (merge-arrays (if ,romega (if ,ralpha (each ,fn ,romega ,ralpha)
						  (each ,fn ,romega
							(make-array (dims ,romega)
								    :initial-element ,alpha)))
				      (if ,ralpha (each ,fn (make-array (dims ,ralpha)
									:initial-element ,omega)
							,ralpha)
					  (funcall ,fn ,omega ,alpha))))
	     (if ,romega (merge-arrays (each ,fn ,romega) :nesting nil)
		 (funcall ,fn ,omega)))))))

(defmacro apply-to-power (op-right sym-left left-function-monadic left-function-dyadic)
  (let ((alpha (gensym)) (omega (gensym)) (arg (gensym)) (index (gensym)))
    `(lambda (,omega &optional ,alpha)
       (let ((,arg (disclose ,omega)))
	 (loop :for ,index :below (disclose ,op-right)
	    :do (setq ,arg (if ,alpha (apl-call ,sym-left ,left-function-dyadic ,arg ,alpha)
			       (apl-call ,sym-left ,left-function-monadic ,arg))))
	 ,arg))))

(defmacro apply-until (sym-right op-right sym-left op-left)
  (let ((alpha (gensym)) (omega (gensym)) (arg (gensym)) (prior-arg (gensym)))
    `(lambda (,omega &optional ,alpha)
       (declare (ignorable ,alpha))
       (let ((,arg ,omega)
	     (,prior-arg ,omega))
	 (loop :while (= 0 (apl-call ,sym-right ,op-right ,prior-arg ,arg))
	    :do (setq ,prior-arg ,arg
		      ,arg (if ,alpha (apl-call ,sym-left ,op-left ,arg ,alpha)
			       (apl-call ,sym-left ,op-left ,arg))))
	 ,arg))))

(defmacro apply-at (right-symbol right-value right-function-monadic
		    left-symbol left-value left-function-monadic left-function-dyadic)
  (let* ((index (gensym)) (omega-var (gensym)) (output (gensym)) (item (gensym))
	 (coord (gensym)) (coords (gensym)) (result (gensym)) (alen (gensym))
	 (alpha (gensym)) (omega (gensym)))
    (cond (right-function-monadic
	   `(lambda (,omega &optional ,alpha)
	      (declare (ignorable ,alpha))
	      (each-scalar (lambda (,item ,coords)
			     (declare (ignore ,coords))
			     (let ((,result (disclose (apl-call ,right-symbol ,right-function-monadic ,item))))
			       (if (= 1 ,result)
				   (disclose ,(cond ((or left-function-monadic left-function-dyadic)
						     `(if ,alpha (apl-call ,left-symbol ,left-function-dyadic
									   ,item ,alpha)
							  (apl-call ,left-symbol ,left-function-monadic ,item)))
						    (t left-value)))
				   (if (= 0 ,result)
				       ,item (error ,(concatenate
						      'string "Domain error: A right function operand"
						      " of @ must only return 1 or 0 values."))))))
			   ,omega)))
	  (t `(lambda (,omega)
		(let* ((,omega-var (apply-scalar #'- ,right-value index-origin))
		       (,output (make-array (dims ,omega)))
		       (,coord))
		  ;; make copy of array without type constraint; TODO: is there a more
		  ;; efficient way to do this?
		  (across ,omega (lambda (,item ,coords)
				   (declare (dynamic-extent ,item ,coords))
				   (setf (apply #'aref (cons ,output ,coords))
					 ,item)))
		  (loop :for ,index :below (length ,omega-var)
		     :do (setq ,coord (aref ,omega-var ,index))
		       (choose ,output (append (if (arrayp ,coord)
						   (mapcar #'list (array-to-list ,coord))
						   (list (list ,coord)))
					       ;; pad choose value with nils to elide
					       (loop :for i :below (1- (rank ,output)) :collect nil))
			       :set ,@(cond (left-function-monadic (list left-function-monadic))
					    (t `((if (is-unitary ,left-value)
						     (disclose ,left-value)
						     (lambda (,item ,coords)
						       (declare (ignore ,item))
						       (let ((,alen (if (not (listp ,coord))
									1 (length ,coord))))
							 (choose ,left-value
								 (mapcar #'list
									 (append (list ,index)
										 (nthcdr ,alen ,coords)))))))
						 :set-coords t)))))
		  ,output))))))

(defmacro apply-stenciled (right-value left-symbol left-function-dyadic)
  (let* ((omega (gensym)) (window-dims (gensym)) (movement (gensym)) (o (gensym)) (a (gensym))
	 (op-left `(lambda (,o ,a) (apl-call ,left-symbol ,left-function-dyadic ,o ,a)))
	 (iaxes (gensym)))
    `(lambda (,omega)
       (flet ((,iaxes (value index) (loop :for x :below (rank value) :for i :from 0
				       :collect (if (= i 0) index nil))))
	 (cond ((< 2 (rank ,right-value))
		(error "The right operand of ⌺ may not have more than 2 dimensions."))
	       ((not ,left-function-dyadic)
		(error "The left operand of ⌺ must be a function."))
	       (t (let ((,window-dims (if (not (arrayp ,right-value))
					  (vector ,right-value)
					  (if (= 1 (rank ,right-value))
					      ,right-value (choose ,right-value (,iaxes ,right-value 0)))))
			(,movement (if (not (arrayp ,right-value))
				       (vector 1)
				       (if (= 2 (rank ,right-value))
					   (choose ,right-value (,iaxes ,right-value 1))
					   (make-array (length ,right-value)
						       :element-type 'fixnum
						       :initial-element 1)))))
		    (merge-arrays (stencil ,omega ,op-left ,window-dims ,movement)))))))))
