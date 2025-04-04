import os
from distutils.core import setup, Extension
from Cython.Build import cythonize
from numpy import get_include as numpy_get_include

setup(
    ext_modules=cythonize(
        Extension(
            "cyphydll",
            sources=[os.getenv("PHYDLL_CYTHON_SOURCES")],
            include_dirs=[os.getenv("PHYDLL_INCLUDE_DIR"), numpy_get_include()],
            libraries=["phydll"],
            library_dirs=[os.getenv("PHYDLL_LIBRARIES_DIR")],
            runtime_library_dirs=[os.getenv("PHYDLL_LIBRARIES_DIR")],
        ),
        compiler_directives={'language_level' : "2"}
    )
)
