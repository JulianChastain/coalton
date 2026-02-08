(defsystem #:jynx-lisply
  :description "Lisply-protocol HTTP backend for Jynx (Coalton fork)"
  :depends-on (#:coalton #:hunchentoot #:yason #:trapezoid)
  :pathname "mcp/backend/"
  :serial t
  :components ((:file "package")
               (:file "eval")
               (:file "server")))
