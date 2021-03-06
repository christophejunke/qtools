#|
 This file is a part of Qtools
 (c) 2014 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.qtools)

(defmacro with-call-stack (stack args &body body)
  `(cffi:with-foreign-object (,stack '(:union qt::StackItem) ,(length args))
     ,@(loop for (val type) in args
             for i from 0
             collect `(setf (cffi:foreign-slot-value
                             (cffi:mem-aptr ,stack '(:union qt::StackItem) ,i)
                             '(:union qt::StackItem) ',type)
                            ,val))
     ,@body))

(defmacro fast-direct-call (method object stack)
  `(qt::call-class-fun (load-time-value
                        (qt::qclass-trampoline-fun
                         (qt::qmethod-class ,method)))
                       (load-time-value
                        (qt::qmethod-classfn-index ,method))
                       ,object
                       ,stack))

(defun find-fastcall-method (class name &rest argtypes)
  (let ((methods (ensure-methods (ensure-q+-method name))))
    (loop for method in methods
          for args = (mapcar #'qt::qtype-name (qt::list-qmethod-argument-types method))
          for mclass = (qt::qmethod-class method)
          when (and (= mclass (ensure-qclass class))
                    (every (lambda (a b)
                             (and (translate-name a 'cffi NIL)
                                  (eql (translate-name a 'cffi)
                                       (translate-name b 'cffi))))
                           args argtypes))
          return method)))

(defun find-fastcall-static-method (name &rest argtypes)
  (let ((methods (ensure-methods (ensure-q+-method name))))
    (loop for method in methods
          for args = (mapcar #'qt::qtype-name (qt::list-qmethod-argument-types method))
          when (and (qt::qmethod-static-p method)
                    (every (lambda (a b)
                             (and (translate-name a 'cffi NIL)
                                  (eql (translate-name a 'cffi)
                                       (translate-name b 'cffi))))
                           args argtypes))
          return method)))

(defmacro fast-call (method-descriptor object &rest args)
  (destructuring-bind (method obj-type &optional rettype &rest argtypes) method-descriptor
    (let ((obj (gensym "OBJECT"))
          (stack (gensym "STACK")))
      `(let ((,obj (qt::qobject-pointer ,object)))
         (with-call-stack ,stack ((,obj qt::ptr)
                                  ,@(loop for type in argtypes for arg in args
                                          collect (list arg (translate-name type 'stack-item))))
           (fast-direct-call ,(or (apply #'find-fastcall-method obj-type method argtypes)
                                  (error "Couldn't find method for descriptor ~s"
                                         method-descriptor))
                             ,obj
                             ,stack)
           ,(when rettype
              `(funcall (load-time-value (qt::unmarshaller (qt::find-qtype ,(translate-name rettype 'qtype))))
                        ,stack)))))))

(defmacro fast-static-call (method-descriptor &rest args)
  (destructuring-bind (method &optional rettype &rest argtypes) method-descriptor
    (let ((stack (gensym "STACK")))
      `(with-call-stack ,stack (((cffi:null-pointer) qt::ptr)
                                ,@(loop for type in argtypes for arg in args
                                        collect (list arg (translate-name type 'stack-item))))
         (fast-direct-call ,(or (apply #'find-fastcall-static-method method argtypes)
                                (error "Couldn't find method for descriptor ~s"
                                       method-descriptor))
                           (cffi:null-pointer)
                           ,stack)
         ,(when rettype
            `(funcall (load-time-value (qt::unmarshaller (qt::find-qtype ,(translate-name rettype 'qtype))))
                      ,stack))))))
