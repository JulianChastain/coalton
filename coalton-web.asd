;;; Coalton Compiler - Literate Programming Version
;;;
;;; This ASDF system builds the Coalton compiler from literate CLWEB sources.
;;; The .clw files in web/compiler/ are the authoritative source; tangled
;;; .lisp output is generated during the build process.
;;;
;;; Usage:
;;;   (ql:quickload :coalton-web)  ; Production: tangle and compile
;;;   (clweb:load-web "web/compiler/algorithm")  ; Development: interactive loading
;;;
;;; Documentation:
;;;   (clweb:weave "web/compiler/coalton-book")  ; Generate TeX output
;;;   Then run pdflatex to produce coalton-book.pdf

(asdf:defsystem "coalton-web"
  :description "The Coalton compiler (literate programming version)."
  :author "Coalton contributors (https://github.com/coalton-lang/coalton)"
  :license "MIT"
  :version (:read-file-form "VERSION.txt")

  ;; CLWEB must be loaded first to provide the clweb-file component class
  :defsystem-depends-on ("clweb")

  :around-compile (lambda (compile)
                    (let (#+sbcl (sb-ext:*derive-function-types* t)
                          #+sbcl (sb-ext:*block-compile-default* :specified))
                      (funcall compile)))

  :depends-on ("alexandria"
               "concrete-syntax-tree"
               "eclector"
               "eclector-concrete-syntax-tree"
               "float-features"
               "fset"
               "named-readtables"
               "source-error"
               "trivial-gray-streams")

  :pathname "web/compiler/"
  :serial t
  :components
  (;; Phase 1: Algorithm module (pilot)
   (clweb:clweb-file "algorithm")

   ;; Future phases will add more modules here:
   ;;
   ;; Phase 2-3: Type System
   ;; (:module "typechecker"
   ;;  :serial t
   ;;  :components ((clweb:clweb-file "base")
   ;;               (clweb:clweb-file "kinds")
   ;;               (clweb:clweb-file "types")
   ;;               ...))
   ;;
   ;; Phase 4: Parser
   ;; (:module "parser"
   ;;  :serial t
   ;;  :components ((clweb:clweb-file "base")
   ;;               ...))
   ;;
   ;; Phase 5: Code Generation
   ;; (:module "codegen"
   ;;  :serial t
   ;;  :components ((clweb:clweb-file "ast")
   ;;               ...))
   ))

;;; Weave operation for generating documentation
;;;
;;; To weave the complete Coalton book:
;;;   (asdf:operate 'clweb:weave-op :coalton-web)
;;;
;;; Or for individual files:
;;;   (clweb:weave "web/compiler/algorithm")
