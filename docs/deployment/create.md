
# Create Physical Solver & DL Engine instances
This is a guide on the deployment of PhyDLL to couple a Physical Solver (C/Fortran/Python) to a Deep Learning engine (C/Fortran/Python).
## Physical Solver:
The depolyment of PhyDLL in the pre-processing step of the Physical Solver is divided into two steps:
1. **Initialization:** Initialize the MPI environment.
2. **Definition:** Define the coupling context.
3. **Options:** Set coupling options.

### 1. Initialization
The initalization subroutine of PhyDLL `phydll_init` allows to split the global communicator, set the coupling parameters and map both instances processes.

#### C interface
- Include PhyDLL's header file
```c
#include "phydll.h"
```
- After MPI initialization, call PhyDLL's initialization (`phydll_init(char instance[])`) subroutine with `"physical"` as argument:
```c
// Init MPI
MPI_Init(<...>);

// Init PhyDLL
phydll_init("physical");
```
- Get the local communicator (after the split) to be used for local communications in the physical solver.
```c
// Local mpi communicator
MPI_Comm comm = phydll_get_local_mpi_comm();
```

#### Fortran interface
- Import PhyDLL's module
```fortran
use phydll_f
```
- As in C, call initialize PhyDLL after MPI. The local communicator is an "out" argument.
```fortran
integer :: ierr
character(len=16) :: instance
integer :: comm

! Init MPI
call mpi_init(ierr)

! Init PhyDLL
instance = "physical"
call phydll_init_f(instance=instance, comm=comm)
```

#### Python interface
- Import PhyDLL's class
```python
from pyphydll import PhyDLL
```

- Initialize PhyDLL and get local communicator
```python
# Init PhyDLL
phyl = PhyDLL()
phyl.init(instance="physical")

# Get MPI local communicator
comm = phyl.get_local_mpi_comm()
```

### 2. Definition
The subroutine `phydll_define` defines the coupling context. Three configurations are available:
+ **Non-context aware coupling:** Inference engine is not aware of the data topology.
+ **Physical mesh-context coupling:** Inference engine receives data topology from the Physical Solver.
+ **Different meshes-context coupling** (*Not supported yet*): Inference engine has its own data topology.

#### 2.1. Non-context aware coupling
The *non-context aware coupling* is defined as follows with two arguments:
+ `count` (*integer*): The number of Physical Fields to send to the DL engine.
+ `size` (*integer*): The array size of a single Physical Field.
##### C interface
```c
void phydll_define_phy(int count, int size);
```
##### Fortran interface
```fortran
phydll_define_phy_f(integer :: count, integer :: size)
```
##### Python interface
```python
phyl.define_phy(count: int, size: int)
```

##### 2.2 Physical mesh-context coupling
In the *Physical mesh-context coupling*, we set mesh informations that are sent to the DL engine to construct/aggregate mesh partitions with respect to it dedicated number of CPU/GPUs. This definition requires the following arguments:
+ `count` (*integr*): Number of physical fields to send.
+ `geodim` (*integer*): Geometrical dimension.
+ `ncell` (*integer*): Number of mesh cells of current partition.
+ `nnode` (*integer*) : Number of mesh nodes of current partition.
+ `ntcell` (*integer*): Total number of mesh cells (all partitions without dup).
+ `ntnode` (*integer*): Total number fo mesh nodes (all partitions without dup).
+ `nvert` (*integer*): Number of vertices per cell. *eg.* tetrahedron mesh: `nvertex=4`; hexahedron mesh: `nvertex=8`.
+ `connec` (*integer array/pointer of size `nvert*ncell`*): Table of element-to-node connectivity of shape.
+ `node_coords` (*double-precision array/pointer of size `geodim*nnode`*): Table of node coordinates (`[x0,y0,z0, ..., xN,yN,zN`) of shape.
+ `local_cell_to_global` (*integer array/pointer of size `ncell`*): Table of local-to-global element mapping.
+ `local_node_to_global` (*integer array/pointer of size `nnode`*): Table of local-to-global node mapping.
##### C interface
```c
void phydll_define_phy_with_mesh(
  int count, \
  int geodim, \
  int ncell, \
  int nnode, \
  int ntcell, \
  int ntnode, \
  int nvert, \
  int** connec, \
  double** coords, \
  int** local_cell_to_global, \
  int** local_node_to_global
)
```
##### Fortran interface
```fortran
phydll_define_phy_with_mesh_f(
  integer :: count, &
  integer :: geodim, &
  integer :: ncell, &
  integer :: nnode, &
  integer :: ntcell, &
  integer :: ntnode, &
  integer :: nvert, &
  integer, dimension(:), pointer :: connec, &
  double precision, dimension(:), pointer :: coords, &
  integer, dimension(:), pointer :: local_cell_to_global, &
  integer, dimension(:), pointer :: local_node_to_global
)
```
##### Python interface
```python
phyl.define_phy_with_mesh(
  count : int,
  geodim : int,
  ncell : int,
  nnode : int,
  ntcell : int,
  ntnode : int,
  nvert : int,
  connec : np.ndarray,
  coords : np.ndarray,
  local_cell_to_global : np.ndarray,
  local_node_to_global : np.ndarray
)
```

### 2. Options
- Enable loop mode
```c
// C interface
void phydll_opt_enable_cpl_loop();
```
```fortran
! Fortran interface
phydll_opt_enable_cpl_loop_f()
```
```python
# Python interface
phyl.opt_enable_cpl_loop()
```
- Set output frequency (save fields frequency for DirectScheme)
```c
// C interface
void phydll_opt_set_output_freq(int output_freq);
```
```fortran
! Fortran interface
phydll_opt_set_output_freq_f(integer :: output_freq)
```
```python
# Python interface
phyl.opt_set_output_freq(output_freq: int)
```

## DL Engine
To create the DL Engine instance, we follow analogically the creation of Physical Solver instance.
1. Initialization: We call `phydll_init()` function with the `"dl"` argument.
2. Definition: We call `phydll_define_dl` with the count of DL fields as argument.

##### C interface
```c
#include "phydll.h"
```
```c
// Init MPI
MPI_Init(<...>);

// Init PhyDLL
phydll_init("dl");

// Get local mpi communicator
MPI_Comm comm = phydll_get_local_mpi_comm();

// Define the instance
phydll_define_dl(count)
```

##### Fortran interface
```fortran
use phydll_f
```
```fortran
integer :: ierr
character(len=16) :: instance
integer :: comm
integer :: count

! Init MPI
call mpi_init(ierr)

! Init PhyDLL
instance = "dl"
call phydll_init_f(instance=instance, comm=comm)

! Define PhyDLL
phydll_define_dl_f(count)
```

##### Python interface
```python
from pyphydll import PhyDLL

# Init PhyDLL
dll = PhyDLL()
dll.init(instance="dl")

# Get MPI local communicator
comm = phyl.get_local_mpi_comm()

# Define
dll.define_dl(count=count)
```