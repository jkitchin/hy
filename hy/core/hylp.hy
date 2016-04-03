;; Copyright (c) 2016 John Kitchin <jkitchin@andrew.cmu.edu>

;; Permission is hereby granted, free of charge, to any person obtaining a
;; copy of this software and associated documentation files (the "Software"),
;; to deal in the Software without restriction, including without limitation
;; the rights to use, copy, modify, merge, publish, distribute, sublicense,
;; and/or sell copies of the Software, and to permit persons to whom the
;; Software is furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
;; THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;; DEALINGS IN THE SOFTWARE.

;;;; A module of help-related functions.
;;;;

(import hy)
(import re)

(defn hy-language-keywords []
  "Return list of functions in hy.core.language"
  (. hy core language *exports*))

(defn hy-shadow-keywords []
  "Return list of shadowed functions"
  (. hy core shadow *exports*))

(defn hy-macro-keywords []
  "Return list of macro keywords"
  (.keys (get hy.macros._hy_macros nil)))

(defn hy-compiler-keywords []
  "Return a list of keywords defined in compiler.py with @build.
These are read out of the hy/compiler.py file."
  (let [keywords []]
    (with [f (open (.replace  (. hy compiler __file__) ".pyc" ".py"))]
          (for [(, i line) (enumerate (.readlines f))]
            (when (re.search "@build" line)
              (let [m (re.search "\"(.*)\"" line)]
                (when m
                  (.append keywords (get (.groups m) 0)))))))
    keywords))

(defmacro hylp-fname-lineno-docstring [sym]
  "Return name, filename, lineno and doc string for the string SYM in hylang."
  `(cond
    [(in ~sym (hy-language-keywords))
     (,  ~sym
         (. hy core language ~(HySymbol sym) __code__ co_filename)
         (. hy core language ~(HySymbol sym) __code__ co_firstlineno)
         (. hy core language ~(HySymbol sym) __doc__))]

    [(in ~sym (hy-shadow-keywords))
     (, (name ~sym)
        (. hy core shadow ~(HySymbol sym) __code__ co_filename)
        (. hy core shadow ~(HySymbol sym) __code__ co_firstlineno)
        (. hy core shadow ~(HySymbol sym) __doc__))]

    [(in ~sym (hy-macro-keywords))
                                ;(print "macro")
     (, ~sym
        (. (get hy.macros._hy_macros nil ~sym) func_code co_filename)
        (. (get hy.macros._hy_macros nil ~sym) func_code co_firstlineno)
        (. (get hy.macros._hy_macros nil ~sym)  __doc__))]

    [(in ~sym (hy-compiler-keywords))
                                ;(print "compiler")
     (, ~sym nil nil "Defined in hy/compiler.py")]

    [(= (. (type ~(HySymbol (.replace (string sym) "-" "_"))) __name__)
        "builtin_function_or_method")
     (, ~sym nil nil (. ~(HySymbol sym) __doc__))]

    ;; Not found. Maybe a regular symbol from hy? or a python func?
    [true
     (let [SYM ~(HySymbol (.replace (string sym) "-" "_"))]
       (, ~sym
          (. SYM func_code co_filename)
          (. SYM func_code co_firstlineno)
          (. SYM __doc__)))]))


(defn get-code [fname lineno]
  "Extract the code for the sexp in FNAME after LINENO."
  (when (and fname lineno)
    (with [f (open fname)]
          (for [i (range (- lineno 1))]
            (.readline f))
          (setv state 0
                in-string False
                in-comment False
                s "("
                j 0
                ch ""
                pch "")

          ;; get to start
          (while True

            (setv pch ch
                  ch (.read f 1))
            (when (= ch "(")
              (setv state 1)
              (break)))

          (while (and (not (= 0 state)))
            (setv ch (.read f 1))
            (+= s ch)
            (cond
             ;; check for in -string, but not escaped "
             ;; we do not consider comments. () in comments will break this.
             [(and (not (= pch "\\")) (= ch "\""))
              (setv in-string (not in-string))]
             ;; comment line
             [(and (not in-string) (not (= pch "\\")) (= ch ";"))
              (setv in-comment True)]
             ;; break out of comment
             [(and in-comment (= ch "\n"))
              (setv in-comment False)]
             [(and (not in-string) (not in-comment) (= ch ")"))
              (setv state (- state 1))]
             [(and (not in-string) (not in-comment) (= ch "("))
              (+= state 1)]
             ))
          s)))


(defn get-args (code-string)
  "Parse the args out of the CODE-STRING."
  (when code-string
    (let [state 0
          in-string False
          i 0
          args "["]
      (while True
        (setv ch (get code-string i))
        (when (= "[" ch)
          (setv state 1)
          (break))
        (+= i 1))

      (while (not (= 0 state))
        (+= i 1)
        (setv ch (get code-string i))
        (+= args ch)
        (cond
         [(and (= ch "[") (not in-string))
          (+= state 1)]
         [(and (= ch "]") (not in-string))
          (-= state 1)]))
      (setv args (.replace args "\n" ""))
      (setv args (re.sub " +" " " args))
      ;; cut off leading and trailing []
      (cut args 1 -1))))


(defmacro ? [sym]
  "Return help for SYM which is a string."
  `(let [flds (hylp-fname-lineno-docstring ~sym)]
     (.format "Usage: ({0} {1})\n\n{2}\n\n[[{3}::{4}]]\n"
              (get flds 0) ;;name
              (get-args (get-code (get flds 1) (get flds 2)))
              (get flds 3) ;; docstring
              (get flds 1) (get flds 2))))
