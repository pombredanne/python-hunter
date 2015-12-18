import os
from _csv import field_size_limit
from distutils.sysconfig import get_python_lib

cimport cython
import sys
from cpython cimport pystate

from .actions import CodePrinter
from .env import SITE_PACKAGES_PATH
from .env import SYS_PREFIX_PATHS


cdef extern from "frameobject.h":
    ctypedef struct PyObject

    ctypedef class types.CodeType[object PyCodeObject]:
        cdef object co_filename
        cdef int co_firstlineno

    ctypedef class types.FrameType[object PyFrameObject]:
        cdef CodeType f_code
        cdef PyObject *f_back
        cdef PyObject *f_trace
        cdef int f_lineno

    void PyEval_SetTrace(pystate.Py_tracefunc func, PyObject*obj)



cdef tuple kind_names = ("call", "exception", "line", "return", "c_call", "c_exception", "c_return")

cdef int trace_func(Tracer self, FrameType frame, int kind, object arg) except -1:
    frame.f_trace = <PyObject*> self;

    if self._handler is None:
        raise RuntimeError("Tracer is not started.")

    print('self._handler(Event', (frame, kind_names[kind], arg, self))

    if self._previous_tracer:
        self._previous_tracer(frame, kind, arg)

@cython.final
cdef class Tracer:
    """
    Tracer object.

    """
    cdef:
        public object _handler
        public object _previous_tracer

    def __cinit__(self):
        self._handler = None
        self._previous_tracer = None

    def __str__(self):
        return "Tracer(_handler={}, _previous_tracer={})".format(
            "<not started>" if self._handler is None else self._handler,
            self._previous_tracer,
        )

    def __call__(self, frame, kind, arg):
        """
        The settrace function.

        .. note::

            This always returns self (drills down) - as opposed to only drilling down when predicate(event) is True
            because it might
            match further inside.
        """
        trace_func(self, frame, kind_names.index(kind), arg)
        return self

    def trace(self, *predicates, **options):
        """
        Starts tracing. Can be used as a context manager (with slightly incorrect semantics - it starts tracing
        before ``__enter__`` is
        called).

        Args:
            predicates (:class:`hunter.Q` instances): Runs actions if any of the given predicates match.
            options: Keyword arguments that are passed to :class:`hunter.Q`, for convenience.
        """
        if "action" not in options and "actions" not in options:
            options["action"] = CodePrinter
        merge = options.pop("merge", True)
        clear_env_var = options.pop("clear_env_var", False)
        # predicate = Q(*predicates, **options)

        if clear_env_var:
            os.environ.pop("PYTHONHUNTER", None)

        previous_tracer = sys.gettrace()
        if previous_tracer is self:
            pass
            # if merge:
            #     self._handler |= predicate
        else:
            PyEval_SetTrace(<pystate.Py_tracefunc> trace_func, <PyObject*> self)

            self._previous_tracer = previous_tracer
            self._handler = True  #predicate
        return self

    def stop(self):
        """
        Stop tracing. Restores previous tracer (if any).
        """
        sys.settrace(self._previous_tracer)
        self._previous_tracer = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()

