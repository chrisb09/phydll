
# Install PhyDLL

The core of PhyDLL is written in C and conforms to MPI standards for parallelization. In addition to the C interface, It has been extended to include interfaces in Fortran and Python.

To install PhyDLL library, we proceed as follows:
- Download PhyDLL
- Compile C core and install C interface
- Install Fortran interface
- Install Python interface
- Compile with HDF5 support

## Download
```bash
git clone https://gitlab.com/cerfacs/phydll -b release/0.2
cd phydll
```

## C core/interface
<a name="phydll_compilation"></a>
```bash
export BUILD=<build directory>
export CC=<MPI-C compiler>
make CC=$CC BUILD=$BUILD
make install
```
where
+ `CC` is the MPI-C compiler,
+ `BUILD` is the installation directory.

The installation creates library and header files, which are located respectively in `$BUILD/lib/libphydll.so` and `$BUILD/include/phydll.h`.

###### Example
```bash
# Create the installation directory
mkdir ../PhyDLL
export BUILD=$(realpath ../PhyDLL)

# Load gcc/openmpi modules
export CC=mpicc

# Install the C core/interface
make CC=$CC BUILD=$BUILD
make install
```

## Fortran interface
To enable the creation of the Fortran interface, we add the option `ENABLE_FORTAN=ON` to the Make and set the MPI-Fortran compiler
```bash
export BUILD=<build directory>
export CC=<MPI-C compiler>

export FC=<MPI-Fortran compiler>

make CC=$CC FC=$FC BUILD=$BUILD ENABLE_FORTRAN=ON
make ENABLE_FORTRAN=ON install
```
It generates the library and module files: `$BUILD/lib/phydll_f.so` and `$BUILD/include/phydll_f.mod`.

## Python interface
**Requirements:** `cython`, `mpi4py`, `numpy`.

Note that `mpi4py` should be installed by using the same MPI compiler.
```bash
export BUILD=<build directory>
export CC=<MPI-C compiler>

make CC=$CC BUILD=$BUILD ENABLE_PYTHON=ON
make ENABLE_PYTHON=ON install
```

## Annex: compile with HDF5 support
In order to save exchanged fields during the coupling (for `DirectScheme` coupling), PhyDLL should be compiled with HDF5 support. To do so, an environment variable exports the installation directory of HDF5. Then PhyDLL’s compilation detects automatically the support.
```bash
export HDF5_DIR=<HDF5_INSTALLATION_DIRECTORY>
```

## Example of installation of PhyDLL with Fortan and Python interfaces:
The example below shows how to install PhyDLL with *GNU/OpenMPI* and *Python 3.9*. CWIPI and HDF5 are already installed and located in `CWIPI_DIR` and `HDF5_DIR` respectively.
```
$ pwd
/home/serhani/

$ git clone https://gitlab.com/cerfacs/phydll
$ cd phydll
$ mkdir -p ../PHYDLL
$ export BUILD=$(realpath ../PHYDLL)

$ module load gcc/11.2.0 openmpi/4.1.1
$ export CC=mpicc
$ export FC=mpifort

$ source /home/serhani/pyenvs/py39-mpi4py-cython/bin/activate

$ make CC=$CC FC=$FC BUILD=../PHYDLL ENABLE_PYTHON=ON ENABLE_FORTRAN=ON
-------------------------------------------------
Welcome to PhyDLL <Physics Deep Learning coupLer>
phydll@cerfacs.fr                      CERFACS(C)
-------------------------------------------------

(PhyDLL)... -----> INSTALLATION INFORMATION --------------------------
          Build directory: /home/serhani/PHYDLL
          Sources directory: /home/serhani/phydll/src/core)

          Enable Fortran API: ON
          Enable Python API: ON

          HDF5 support: True
          HDF5 directory: /home/serhani/HDF5

          C compiler: mpicc (/opt/openmpi/4.1.1/bin/mpicc)
          Fortran compiler: mpifort (/opt/openmpi/4.1.1/bin/mpifort)

          Python interpreter: Python 3.9.7 (/home/serhani/pyenvs/py39-mpi4py-cython/bin/python)

          PhyDLL's Library path: /home/serhani/PHYDLL/lib
          PhyDLL's Include path: /home/serhani/PHYDLL/include
          PhyDLL's Python package: /home/serhani/PHYDLL/src/python/pyphydll
------------------------------------------------------------ ...done

(PhyDLL)... -----> C COMPILING ---------------------------------------
mkdir -p /home/serhani/PHYDLL/lib /home/serhani/PHYDLL/include
mpicc -g -O2 -Wall -Wextra -std=c99 -DHDF5 -I/home/serhani/HDF5/include -L/home/serhani/HDF5/lib -lhdf5 -lhdf5_hl -fPIC -shared -I/home/serhani/phydll/src/core /home/serhani/phydll/src/core/phydll.c /home/serhani/phydll/src/core/kernel.c /home/serhani/phydll/src/core/kernel_structs.c /home/serhani/phydll/src/core/io.c /home/serhani/phydll/src/core/utils.c -o /home/serhani/PHYDLL/lib/libphydll.so
cp /home/serhani/phydll/src/core/phydll.h /home/serhani/PHYDLL/include
------------------------------------------------------------ ...done

(PhyDLL)... -----> Fortran COMPILING ---------------------------------
+ mpifort -g -O2 -cpp -Wall -Wextra -ffree-line-length-none -I/home/serhani/HDF5/include -L/home/serhani/HDF5/lib -lhdf5 -lhdf5_hl -lhdf5_fortran -lhdf5hl_fortran -fPIC -shared /home/serhani/phydll/src/fortran/phydll_cf.f90 /home/serhani/phydll/src/fortran/phydll_f.f90 -o /home/serhani/PHYDLL/lib/libphydll_f.so -L/home/serhani/PHYDLL/lib -lphydll -Wl,-rpath=/home/serhani/PHYDLL/lib
+ mv phydll_cf.mod phydll_f.mod /home/serhani/PHYDLL/include
+ set +x
------------------------------------------------------------ ...done

(PhyDLL)... -----> Python SETUP --------------------------------------
+ cd /home/serhani/phydll/src/python/pyphydll
+ PHYDLL_CYTHON_SOURCES=/home/serhani/phydll/src/python/pyphydll/cyphydll.pyx
+ PHYDLL_INCLUDE_DIR=/home/serhani/phydll/src/core
+ PHYDLL_LIBRARIES_DIR=/home/serhani/PHYDLL/lib
+ python /home/serhani/phydll/src/python/pyphydll/setup.py build_ext --build-temp=/home/serhani/phydll/src/python/pyphydll --build-lib=/home/serhani/phydll/src/python/pyphydll
Compiling /home/serhani/phydll/src/python/pyphydll/cyphydll.pyx because it changed.
[1/1] Cythonizing /home/serhani/phydll/src/python/pyphydll/cyphydll.pyx
running build_ext
building 'cyphydll' extension
mpicc -Wno-unused-result -Wsign-compare -DNDEBUG -O2 -Wall -fPIC -O2 -isystem <...>
In file included <...>
gcc -pthread -B <...>
+ cp /scratch/coop/serhani/AVBP-DL/PhyDLL/setup.cfg /scratch/coop/serhani/AVBP-DL/PhyDLL/setup.py /scratch/coop/serhani/AVBP-DL/PhyDLL/build
+ rm -rf /home/serhani/PHYDLL/src/python
+ mkdir -p /home/serhani/PHYDLL/src/python
+ cp -r /home/serhani/phydll/src/python/pyphydll /home/serhani/PHYDLL/src/python/
+ cd /scratch/coop/serhani/AVBP-DL/PhyDLL/build
+ pip install .
Processing /scratch/coop/serhani/AVBP-DL/PhyDLL/build
  Preparing metadata (setup.py) ... done
Requirement already satisfied: mpi4py in <...> (from pyphydll==0.2.0) (3.0.3)
Requirement already satisfied: numpy in <...> (from pyphydll==0.2.0) (1.19.5)
Requirement already satisfied: pyyaml in <...> (from pyphydll==0.2.0) (6.0)
Building wheels for collected packages: pyphydll
  Building wheel for pyphydll (setup.py) ... done
  Created wheel for pyphydll: <...>
  Stored in directory: <...>
Successfully built pyphydll
Installing collected packages: pyphydll
  Attempting uninstall: pyphydll
    Found existing installation: pyphydll 0.2.0
    Uninstalling pyphydll-0.2.0:
      Successfully uninstalled pyphydll-0.2.0
Successfully installed pyphydll-0.2.0

[notice] A new release of pip is available: 23.0.1 -> 23.3.1
[notice] To update, run: pip install --upgrade pip
+ set +x
------------------------------------------------------------ ...done

$ make CC=mpicc FC=mpifort ENABLE_PYTHON=ON ENABLE_FORTRAN=ON install
(PhyDLL)... -----> C/C TESTS -----------------------------------------
	Compiling/linking C test physical solver...
		Succeeded
	...done

	Compiling/linking C test DL engine...
		Succeeded
 	...done

	Running...
		Succeeded
 	...done
------------------------------------------------------------ ...done

(PhyDLL)... -----> Fortran/C TESTS -----------------------------------
	Compiling/linking Fortran test physical solver...
		Succeeded
	...done

	Running...
		Succeeded
 	...done
------------------------------------------------------------ ...done

(PhyDLL)... -----> Python/Python TESTS --------------
	Running Python/Python coupling...
		Succeeded
 	...done
------------------------------------------------------------ ...done
```
