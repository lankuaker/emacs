;;; Test GNU Emacs modules.

;; Copyright 2015-2017 Free Software Foundation, Inc.

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.  */

(require 'ert)

(require 'mod-test
         (expand-file-name "data/emacs-module/mod-test"
                           (getenv "EMACS_TEST_DIRECTORY")))

;;
;; Basic tests.
;;

(ert-deftest mod-test-sum-test ()
  (should (= (mod-test-sum 1 2) 3))
  (let ((descr (should-error (mod-test-sum 1 2 3))))
    (should (eq (car descr) 'wrong-number-of-arguments))
    (should (stringp (nth 1 descr)))
    (should (eq 0
                (string-match
                 (concat "#<module function "
                         "\\(at \\(0x\\)?[0-9a-fA-F]+\\( from .*\\)?"
                         "\\|Fmod_test_sum from .*\\)>")
                 (nth 1 descr))))
    (should (= (nth 2 descr) 3)))
  (should-error (mod-test-sum "1" 2) :type 'wrong-type-argument)
  (should-error (mod-test-sum 1 "2") :type 'wrong-type-argument)
  ;; The following tests are for 32-bit build --with-wide-int.
  (should (= (mod-test-sum -1 most-positive-fixnum)
             (1- most-positive-fixnum)))
  (should (= (mod-test-sum 1 most-negative-fixnum)
             (1+ most-negative-fixnum)))
  (when (< #x1fffffff most-positive-fixnum)
    (should (= (mod-test-sum 1 #x1fffffff)
               (1+ #x1fffffff)))
    (should (= (mod-test-sum -1 #x20000000)
               #x1fffffff)))
  (should-error (mod-test-sum 1 most-positive-fixnum)
                :type 'overflow-error)
  (should-error (mod-test-sum -1 most-negative-fixnum)
                :type 'overflow-error))

(ert-deftest mod-test-sum-docstring ()
  (should (string= (documentation 'mod-test-sum) "Return A + B")))

(ert-deftest module-function-object ()
  "Extract and test the implementation of a module function.
This test needs to be changed whenever the implementation
changes."
  (let ((func (symbol-function #'mod-test-sum)))
    (should (consp func))
    (should (equal (length func) 4))
    (should (equal (nth 0 func) 'lambda))
    (should (equal (nth 1 func) '(&rest args)))
    (should (equal (nth 2 func) "Return A + B"))
    (let ((body (nth 3 func)))
      (should (consp body))
      (should (equal (length body) 4))
      (should (equal (nth 0 body) #'apply))
      (should (equal (nth 1 body) '#'internal--module-call))
      (should (equal (nth 3 body) 'args))
      (let ((obj (nth 2 body)))
        (should (equal (type-of obj) 'module-function))
        (should (string-match-p
                 (rx "#<module function "
                     (or "Fmod_test_sum"
                         (and "at 0x" (+ hex-digit)))
                     (? " from " (* nonl) "mod-test" (* nonl) )
                     ">")
                 (prin1-to-string obj)))))))

;;
;; Non-local exists (throw, signal).
;;

(ert-deftest mod-test-non-local-exit-signal-test ()
  (should-error (mod-test-signal))
  (let (debugger-args backtrace)
    (should-error
     (let ((debugger (lambda (&rest args)
                       (setq debugger-args args
                             backtrace (with-output-to-string (backtrace)))
                       (cl-incf num-nonmacro-input-events)))
           (debug-on-signal t))
       (mod-test-signal)))
    (should (equal debugger-args '(error (error . 56))))
    (should (string-match-p
             (rx bol "  internal--module-call(" (+ nonl) ?\) ?\n
                 "  apply(internal--module-call " (+ nonl) ?\) ?\n
                 "  mod-test-signal()" eol)
             backtrace))))

(ert-deftest mod-test-non-local-exit-throw-test ()
  (should (equal
           (catch 'tag
             (mod-test-throw)
             (ert-fail "expected throw"))
           65)))

(ert-deftest mod-test-non-local-exit-funcall-normal ()
  (should (equal (mod-test-non-local-exit-funcall (lambda () 23))
                 23)))

(ert-deftest mod-test-non-local-exit-funcall-signal ()
  (should (equal (mod-test-non-local-exit-funcall
                  (lambda () (signal 'error '(32))))
                 '(signal error (32)))))

(ert-deftest mod-test-non-local-exit-funcall-throw ()
  (should (equal (mod-test-non-local-exit-funcall (lambda () (throw 'tag 32)))
                 '(throw tag 32))))

;;
;; String tests.
;;

(defun multiply-string (s n)
  (let ((res ""))
    (dotimes (i n res)
      (setq res (concat res s)))))

(ert-deftest mod-test-globref-make-test ()
  (let ((mod-str (mod-test-globref-make))
        (ref-str (multiply-string "abcdefghijklmnopqrstuvwxyz" 100)))
    (garbage-collect) ;; XXX: not enough to really test but it's something..
    (should (string= ref-str mod-str))))

(ert-deftest mod-test-string-a-to-b-test ()
  (should (string= (mod-test-string-a-to-b "aaa") "bbb")))

;;
;; User-pointer tests.
;;

(ert-deftest mod-test-userptr-fun-test ()
  (let* ((n 42)
         (v (mod-test-userptr-make n))
         (r (mod-test-userptr-get v)))

    (should (eq (type-of v) 'user-ptr))
    (should (integerp r))
    (should (= r n))))

;; TODO: try to test finalizer

;;
;; Vector tests.
;;

(ert-deftest mod-test-vector-test ()
  (dolist (s '(2 10 100 1000))
    (dolist (e '(42 foo "foo"))
      (let* ((v-ref (make-vector 2 e))
             (eq-ref (eq (aref v-ref 0) (aref v-ref 1)))
             (v-test (make-vector s nil)))

        (should (eq (mod-test-vector-fill v-test e) t))
        (should (eq (mod-test-vector-eq v-test e) eq-ref))))))
