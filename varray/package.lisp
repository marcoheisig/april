;;;; package.lisp

(defpackage #:varray
  (:use #:cl)
  (:export #:varray #:etype-of #:shape-of #:indexer-of #:render
           #:vvector-integer-progression #:vader-turn)
  (:shadowing-import-from #:aplesque.forms #:indexer-section #:indexer-expand #:indexer-turn #:indexer-permute))