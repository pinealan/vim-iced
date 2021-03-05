(ns iced-repl
  (:require [nrepl.cmdline :as cmd]))

(defn -main [& _]
  (->> "deps.edn"
       slurp
       read-string
       :__middlewares__
       pr-str
       (cmd/-main "-m")))

(def cider-middleware
  ['cider.nrepl/wrap-classpath
   'cider.nrepl/wrap-clojuredocs
   'cider.nrepl/wrap-complete
   'cider.nrepl/wrap-debug
   'cider.nrepl/wrap-format
   'cider.nrepl/wrap-info
   'cider.nrepl/wrap-macroexpand
   'cider.nrepl/wrap-ns
   'cider.nrepl/wrap-out
   'cider.nrepl/wrap-spec
   'cider.nrepl/wrap-test
   'cider.nrepl/wrap-trace
   'cider.nrepl/wrap-undef
   'cider.nrepl/wrap-xref
   'refactor-nrepl.middleware/wrap-refactor
   'iced.nrepl/wrap-iced])
