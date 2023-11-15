import os
from distutils.core import setup, Extension
from Cython.Build import cythonize
from numpy import __path__ as numpy_path

setup(
    ext_modules=cythonize(
        Extension(
            "cyphydll",
            sources=[os.getenv("PHYDLL_CYTHON_SOURCES")],
            include_dirs=[os.getenv("PHYDLL_INCLUDE_DIR"), numpy_path[0]+"/core/include"],
            libraries=["phydll"],
            library_dirs=[os.getenv("PHYDLL_LIBRARIES_DIR")],
            runtime_library_dirs=[os.getenv("PHYDLL_LIBRARIES_DIR")],
        ),
        compiler_directives={'language_level' : "2"}
    )
)
# NUMPY_INC=$(python -c "from numpy import __path__; print(__path__[0])")/core/include;
