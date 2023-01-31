
# PhyDLL's installation

PhyDLL has two interfaces:
+ Fortran interface for the Physical solver.
+ Python interface for the DL engine.

To install PhyDLL library, we proceed as follows:
1. Download PhyDLL.
2. Compile the Fortran sources.
3. Instal the associated Python package

##### Download
```bash
git clone https://gitlab.com/cerfacs/phydll
cd phydll
```

## Fortran compilation
##### 1. Compile
<a name="phydll_compilation"></a>
```bash
mkdir ../PHYDLL
export FC=<MPI-Fortran compiler>   # eg. mpif90
make FC=$FC BUILD=../PHYDLL
```
where `$FC` is the MPI-Fortran compiler, it could be `mpifort` (*GNU*) or `mpiifort` (*Intel*). `BUILD=` is the installation directory.

##### 2. Compile with CWIPI support
To install PhyDLL with CWIPI support, It should be installed before (*cf.* <a href="#cwipi_compilation">CWIPI installation</a>), and the variable `CWIPI_DIR` should be set as the installation directory of CWIPI.
```
export CWIPI_DIR=<CWIPI_INSTALLATION_DIRECTORY>
```
Once this environment variable is set, the compilation process (<a href="#phydll_compilation">1. Compile</a>) detects automatically CWIPI support.

To create the executable of the Fortran solver, it is relevant to export PhyDLL directory as an environment variable
```bash
export PHYDLL_DIR=$(realpath ../PhyDLL)
```

#### 3. Create the executable of Fortran solver
To create the executable of the Fortran solver, the following flags should be added to the compilation and linking steps.

+ Compilation flags:
```bash
-DPHYDLL -I${PHYDLL_DIR}/include
```

+ Linking flags:
```bash
 -L${PHYDLL_DIR}/lib -Wl,-rpath=${PHYDLL_DIR}/lib -lphydll
```

+ If CWIPI support is enabled, we add to the linker
```bash
-Wl,-rpath=${CWIPI_DIR}/lib
```

## Python installation
**Requirements:** `mpi4py`, `numpy`, `pyhdf5`, `pyyaml`.

Note that `mpi4py` should be installed by using the same MPI-Fortran compiler.
```bash
cd phydll               # (sources directory)
pip install -U -e ./
```
- The Python interface could be installed from the `makefile` by adding `ENABLE_PYTHON=ON`:
```bash
make FC=$FC BUILD=../PHYDLL ENABLE_PYTHON=ON
```
- If CWIPI support is enabled, the Python API of CWIPI should be appended to `PYTHONPATH`
```bash
export PYTHONPATH=$CWIPI_DIR/lib/pythonX.X/site-packages:$PYTHONPATH
```

## Annex: CWIPI installation:
<a name="cwipi_compilation"></a>
CWIPI website: [https://w3.onera.fr/cwipi/](https://w3.onera.fr/cwipi/).
+ Download CWIPI:
We recommand the version: `0.12.0`
```bash
wget https://w3.onera.fr/cwipi/sites/w3.onera.fr.cwipi/files/u4/cwipi-0.12.0.tgz
tar -zxvf cwipi-0.12.0.tar.gz
mkdir CWIPI
cd CWIPI
```

+ Set compilers:
```bash
export CC=<MPI-C compiler>         # eg. mpicc
export CXX=<MPI-C++ compiler>      # eg. mpicxx
export FC=<MPI-Fortran compiler>   # eg. mpif90
```

+ Set python variables
```bash
export PYINTERP=<Python interpreter> # eg. ~/env/bin/python
export CYINTERP=<Cython interpreter> # eg. ~/env/bin/cython
export PYLIB=<Python library file>   # eg. ~/env/lib/libpython.so
```

+ Compilation:
```bash
CC=$CC CXX=$CXX FC=$FC cmake -DCWP_ENABLE_PYTHON_BINDINGS=ON -DCWP_ENABLE_Fortran=ON \
-DCWP_BUILD_DOCUMENTATION=OFF -DPYTHON_EXECUTABLE=$PYINTERP -DCYTHON_EXECUTABLE=$CYINTREP \
-DPYTHON_LIBRARY=$PYLIB -DCMAKE_INSTALL_PREFIX=$PWD -DCMAKE_CWP_INSTALL_PYTHON_DIR=$PWD \
../cwipi-0.12.0
```

```bash
make
```

```bash
make install
```

+ Export `CWIPI_DIR` as variable environment
```bash
export CWIPI_DIR=$PWD
```

## Example of installation of PhyDLL with CWIPI support:
The example below shows how to install PhyDLL with *Intel MPI* and *Python 3.9*. CWIPI is already installed and located in `CWIPI_DIR`.

```bash
$ pwd
/home/serhani/
$ git clone https://gitlab.com/cerfacs/phydll
$ cd phydll
$ mkdir ../PHYDLL
$ export CWIPI_DIR=/home/serhani/CWIPI
$ make FC=mpiifort BUILD=../PHYDLL
-------------------------------------------------
Welcome to PhyDLL <Physics Deep Learning coupLer>
phydll@cerfacs.fr                      CERFACS(C)
-------------------------------------------------

(PhyDLL) -----> INSTALL ...

          Build directory: /home/serhani/PhyDLL
          Sources directory: /home/serhani/phydll/src/fortran

          CWIPI support: True
          CWIPI directory: /home/serhani/CWIPI

          Fortran compiler: mpiifort (/usr/bin/mpiifort)
          Fortran flags: -O2 -g -fpp -warn all -traceback -DCWIPI -I/home/serhani/CWIPI/include -L/home/serhani/CWIPI/lib -Wl,-rpath=/home/serhani/CWIPI/lib -lcwp -lcwpf

          Compiling ...
mpiifort -O2 -g -fpp -warn all -traceback -DCWIPI -I/home/serhani/CWIPI/include -L/home/serhani/CWIPI/lib -Wl,-rpath=/home/serhani/CWIPI/lib -lcwp -lcwpf -fpic -shared ./src/fortran/mod_params.f90 ./src/fortran/mod_env.f90 ./src/fortran/mod_cpl.f90 ./src/fortran/mod_mesh.f90 ./src/fortran/mod_io.f90 ./src/fortran/mod_phydll.f90 ./src/fortran/phydll.f90 -o ./build/lib/libphydll.so -I./build/include

          PhyDLL Library path: /home/serhani/PhyDLL/lib
          PhyDLL Include path: /home/serhani/PhyDLL/include

(PhyDLL) -----> DONE

$ export PHYDLL_DIR=/home/serhani/PhyDLL

$ pip install -U -e .
```