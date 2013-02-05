;;; figl
;;; Copyright (C) 2013 Andy Wingo <wingo@pobox.com>
;;; 
;;; Figl is free software: you can redistribute it and/or modify it
;;; under the terms of the GNU Lesser General Public License as
;;; published by the Free Software Foundation, either version 3 of the
;;; License, or (at your option) any later version.
;;; 
;;; Figl is distributed in the hope that it will be useful, but WITHOUT
;;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General
;;; Public License for more details.
;;; 
;;; You should have received a copy of the GNU Lesser General Public
;;; License along with this program.  If not, see
;;; <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; figl is the Foreign Interface to GL.
;;
;;; Code:

(define-module (figl gl runtime)
  #:use-module (system foreign)
  #:use-module (figl runtime)
  #:export (current-gl-resolver
            current-gl-get-dynamic-object
            define-gl-procedure
            define-gl-procedures))

(module-use! (module-public-interface (current-module))
             (resolve-interface '(figl runtime)))

;;
;; OpenGL and loading.  What a mess.  So, in the beginning, when
;; Microsoft added support for OpenGL to Windows, they did so via a
;; trampoline DLL.  This DLL had a fixed number of entry points, and it
;; was independent of the driver that the graphics card provided.  It
;; also provided an extension interface, wglGetProcAddress, which could
;; return additional GL procedures by name.  Microsoft was unwilling to
;; extend their trampoline DLL for whatever reason, and so on Windows
;; you always needed to wglGetProcAddress for almost any OpenGL
;; function.
;;
;; Time passed and GLX and other GL implementations started to want
;; extensions too.  This let application vendors ship applications that
;; could take advantage of the capabilities of users's graphics cards
;; without requiring that they be present.
;;
;; There are a couple of differences between WGL and GLX, however.
;; Chiefly, wglGetProcAddress can only be called once you have a
;; context, and the resulting function can only be used in that context.
;; In practice it seems that it can be used also in other contexts that
;; end up referring to that same driver and GPU.  GLX on the other hand
;; is context-independent, but presence of a function does not mean that
;; the corresponding functionality is actually available.  In theory
;; users have to check for the presence of the GL extension or check the
;; core GL version, depending on whether the interface is an extension
;; or in GL core.
;;
;; Because of this difference between the GLX and WGL semantics, there
;; is no core "glGetProcAddress" function.  It's terrible: each
;; windowing system is responsible for providing their own
;; function-loader interface.
;;
;; Finally, Guile needs to load up at least some interfaces using
;; dynamic-link / dynamic-pointer in order to be able to talk to the
;; library at all (and to open a context in the case of Windows), and it
;; happens that these interfaces also work fine for getting some of the
;; GL functionality!
;;
;; All of this mess really has very little place in the world of free
;; software, where dynamic linking is entirely sufficient to deal with
;; this issue, but it is how things have evolved.
;;
;; Our solution is to provide extension points to allow a user to
;; specify a glXGetProcAddress-like procedure, and to specify the
;; dynamic object used to lookup symbols in the fallback case.
;; Functions will end up lazily caching a foreign function wrapper, one
;; per function.  This means that a minority of Windows configurations
;; (using multiple different output gpu/driver combinations at once)
;; won't work.  Oh well.
;;

;; Parameterize this with glXGetProcAddress, eglGetProcAddress, etc.
(define current-gl-resolver
  (make-parameter (lambda (name) %null-pointer)))

;; Parameterize this with a procedure that returns a dynamic object we
;; can use to get libGL bindings.
(define current-gl-get-dynamic-object
  (make-parameter (lambda () (dynamic-link))))

(define (resolve name)
  (let ((ptr ((current-gl-resolver) (symbol->string name))))
    (if (null-pointer? ptr)
        (dynamic-pointer (symbol->string name)
                         ((current-gl-get-dynamic-object)))
        ptr)))

(define-syntax define-gl-procedure
  (syntax-rules (->)
    ((define-gl-procedure (name (pname ptype) ... -> type)
       docstring)
     (define-foreign-procedure (name (pname ptype) ... -> type)
       (resolve 'name)
       docstring))))

(define-syntax define-gl-procedures
  (syntax-rules ()
    ((define-gl-procedures ((name prototype ...) ...)
       docstring)
     (begin
       (define-gl-procedure (name prototype ...)
         docstring)
       ...))))
