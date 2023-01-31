
# PhyDLL deployment

This is a guide on the deployment of PhyDLL to couple a Physical Solver (Fortran) to a Deep Learning engine (Python).
## Physical solver (Fortran):
### Pre-processing:
The depolyment of PhyDLL in the pre-processing step of the Physical Solver is divided into two steps:
1. **Initialization:** Initialize the MPI environment.
2. **Definition:** Define the coupling context.
#### 1. Initialization
The initalization subroutine of PhyDLL `phydll_init` allows to split the global communicator and set the coupling parameters.

1. Import initialization subroutine:
```fortran
use phydll, only: phydll_init
```

2. Call `phydll_init` after `mpi_init`:
```fortran
integer :: global_comm, comm, enable_phydll
integer :: ierror

call mpi_init(ierror)

call phydll_init(global_comm, comm, enable_phydll)
```
`phydll_init` returns:
+ The global communicator `global_comm`: *Physical solver + DL engine* (`MPI_COMM_WORLD`).
+ The local communicator `comm`, it should be used for local communications inside the physical solver.
+ A status parameter `enable_phydll`, it is set to `1` if `phydll` is enabled.

#### 2. Definition
The subroutine `phydll_define` defines the coupling context. Three configurations are available:
+ **Non-context aware coupling:** Inference engine is not aware of the data topology.
+ **Physical mesh-context coupling:** Inference engine receives data topology from the Physical Solver.
+ **Different meshes-context coupling**: Inference engine has its own data topology.

##### 2.1. Non-context aware coupling
The *non-context aware coupling* is defined as follows
```fortran
use phydll, only: phydll_define

call phydll_define(field_size)
```
where
+ `integer :: field_size`: The array size of the exchanged field.

##### 2.2 Physical mesh-context coupling
In the *Physical mesh-context coupling*, we set mesh informations that are sent to the DL engine to construct/aggregate mesh partitions with respect to it dedicated number of CPU/GPUs
```fortran
use phydll, only: phydll_define

call phydll_define(
	dim=dim, &
	ncell=ncell, &
	nnode=nnode, &
	nvertex=nvert_max, &
	ntcell=ntcell, &
	ntnode=ntnode, &
	node_coords=node_coords, &
	element_to_node=element_to_node, &
	local_node_to_global=local_node_to_global, &
	local_element_to_global=local_element_to_global)
```
where
+ `integer :: ncell`: Number of mesh cells of current partition.
+ `integer :: nnode` : Number of mesh nodes of current partition.
+ `integer :: nvertex`: Number of vertices per cell. *eg.* tetrahedron mesh: `nvertex=4`; hexahedron mesh: `nvertex=8`.
+ `integer :: ntcell`: Total number of mesh cells (all partitions without dup).
+ `integer :: ntnode`: Total number fo mesh nodes (all partitions without dup).
+ `double_precision, dimension(3*nnode) :: node_coords`: 1D table of node coordinates (`[x0,y0,z0, ..., xN,yN,zN`) of shape.
+ `integer, dimension(nvertex*nnode) :: element_to_node`: 1D table of element-to-node connectivity of shape.
+ `integer, dimension(ncell) :: local_element_to_global`: 1D table of local-to-global element mapping.
+ `integer, dimension(nnode) :: local_node_to_global`: 1D table of local-to-global node mapping.

##### 2.3 Different meshes-context coupling
When DL engine has its own mesh, we define necessary variables to feed to CWIPI (to perform interpolation and communication).
```fortran
use phydll, only: phydll_define

call phydll_define(
	ncell=ncell, &
	nnode=nnode, &
	nvertex=nvertex, &
	element_to_node=element_to_node, &
	node_coords=node_coords
	)
```
To set the Physical solver's mesh for `phydll` coupling, `phydll_define` should be called in the *pre-processing* step of the physical solver. The arguments of this subroutine are:
+ `integer :: nnode` : Number of mesh nodes of current partition.
+ `integer :: ncell`: Number of mesh cells of current partition.
+ `integer :: nvertex`: Number of vertices per cell. *eg.* tetrahedron mesh: `nvertex=4`; hexahedron mesh: `nvertex=8`.
+ `integer, dimension(nvertex*nnode) :: element_to_node`: 1D table of element-to-node connectivity of shape.
+ `double_precision, dimension(3*nnode) :: node_coords`: 1D table of node coordinates (`[x0,y0,z0, ..., xN,yN,zN`) of shape.
<br>

**Note:** It is relevant to use the status parameter `enable_phydll` returned by `phydll_init` to  add a condition for generalizable use `phydll`:
```fortran
if (enable_phydll == 1) then
  call phydll_define(...)
end if
```

### 2. Exchange fields:
Once PhyDLL is initialized and defined, you can start exchanging the data between the Physical Solver and the Deep Learning engine.
#### 2.1. Set and send Physical solver's fields
1. **Set fields to send**:

The subroutine `phydll_set_phy_field` allows to set the Physical fields to send to DL engine. It is done accumulatively. The arguments are
+ `double precision, dimension(nnode) :: field`: The field to send. (If non-context coupling is chosen, `nnode` becomes `field_size`.)
+ `character(len=64) :: label`: Label of the field to send.
+ `integer :: index`: Index of the field to send (default=1).

The example below shows how to set 3 fields.
```fortran
use phydll, only: phydll_set_phy_field

call phydll_set_phy_field(field=field_to_send_1, label="field_to_send_1", index=1)
call phydll_set_phy_field(field=field_to_send_2, label="field_to_send_2", index=2)
call phydll_set_phy_field(field=field_to_send_3, label="field_to_send_3", index=3)
```

2. **Send fields**

To send fields, we call `phydll_send_phy_fields` without arguments.
```fortran
use phydll, only: phydll_send_phy_fields

call phydll_send_phy_fields()
```

#### 2.2. Receive and apply DL fields:
1. **Receive DL fields**

To receive the DL fields, we call `phydll_recv_dl_fields`
```fortran
use phydll, only: phydll_recv_dl_fields

call phydll_recv_dl_fields()
```

2. **Apply DL fields**

`phydll_apply_dl_field` allows to apply DL fields on Physical solver variables. It could be  applied accumulatively as well. The arguments of the subroutine are:
+ `double precision, dimension(nnode) :: field`: The field to be applied on, If non-context coupling is chosen, `nnode` becomes `field_size`.
+ `character(len=64) :: label`: Label of the field to be applied on.
+ `integer :: index`: Index of the field to be applied on (default=1).


```fortran
use phydll, only: phydll_apply_dl_field

call phydll_apply_dl_field(field_1, label="field_1", index=1)
call phydll_apply_dl_field(field_2, label="field_2", index=2)
call phydll_apply_dl_field(field_3, label="field_3", index=3)
```

## Deep Learning engine (Python)

### 1. Pre-processing
##### Create `PhyDLL` object
1. Import `phydll` Python API.
```python
from phydll.phydll import PhyDLL
```

2. Create the python object
```python
phydll = PhyDLL(coupling_scheme,
                mesh_type,
                phy_nfields,
                dl_nfields)
```
where
+ `coupling_scheme: str` is the coupling scheme:
  + `"DS"` or `"DirectScheme"`: To use the *Direct Scheme* of PhyDLL.
  + `"IS"` or `"InterpolationScheme"`: To use the *Interpolation Scheme* of PhyDLL to exchange fields with interpolation (it requires to compile PhyDLL with CWIPI support).
+ `mesh_type: str` is the mesh type that defines the coupling context.
  + `"NC"`: Non-context aware coupling.
  + `"phymesh"`: Physical mesh-context which allows to the DL engine to receives mesh information from the Physical solver and to construct its mesh with the same topology.
  + `"voxgrid"`: DL engine contsructs its own mesh, which is, in this case, a 3D voxels grid.
+ `phy_nfields: int`: Number of Physical fields to send from Physical Solver to DL engine.
+ `dl_nfields: int`: Number of DL fields to send from DL engine to Physical Solver.

##### Pre-process `PhyDLL`
It constructs the coupling environment, the I/O objects and local mesh for the DL engine.
```python
phydll.pre_processing()
```
Once the pre-processing is done, `phydll` provides:
+ `phydll.mpienv`: MPI environment of the coupling.
+ `phydll.input`, `phydll.output`: Input/output object created by `phydll`.
+ `phydll.mesh`: The coupling mesh object.
Initialize then the deep learning object `dl_obj`.

##### Initialize DL engine `DeepLearningEngine`
You could initialze the Deep Learning engine `DeepLearningEngine` with the object provided by `phydll`
```python
dlengine = DeepLearningEngine(env=phydll.mpienv,
                              io=(phydll.input, phydll.output),
                              mesh=phydll.mesh)
```
### 2. Exchange fields
1. **Receive Physical solver fields**

The Physical solver fields are received as follows:
```python
phy_fields = phydll.receive_phy_fields()
```
`phy_fields`:
  + Type: `numpy.array`
  + Precision: `"np.float64"`
  + Shape: `(phydll.phy_nfields, phydll.mesh.nnode)`

2. **Call prediction**

Call the prediction function of the Deep Learing engine `dlengine`.
```python
dl_fields = dlengine.predict(phy_fields)
```
`dl_fields` should be:
  + Type: `numpy.array`
  + Precision: `"np.float64"`
  + Shape: `(phydll.dl_nfields, phydll.mesh.nnode)`

3. **Send DL fields**
```python
phydll.send_dl_fields(dl_fields)
```


## Exchange in loop mode
Data exchange can be performed in temporal loop mode with a given frequency. The frequency is set 1 by default, but it can be changed in the input file (`phydll.yml`). This loop mode allows the Physical solver to send a signal to DL engine to indicate when it’s a coupling iteration. To do so
```fortran
call phydll_send_phy_fields(loop=.true.)
```
In the DL engine a temporal loop could be created as follows
```python
while phydll.fsignal:
    phy_fields = phydll.receive_phy_fields()
    dl_fields = dlengine.predict(phy_fields)
    phydll.send_dl_fields(dl_fields)
```

## Input file:
The input file should be located in the run application's directory and named `phydll.yml`.

#### Coupling interface
```yaml
# Coupling interface parameters
Coupling:
  coupling_frequency : 1              # (optional, default=1) Coupling frequency
  save_fields_frequency : 1           # (optional, default=0) Frequency to save exchanged fields in ./PhyDLL_FIELDS/cwipi
```
Additional options should be set if the `InterpolationScheme` coupling is chosen.
```yaml
# Coupling interface parameters
Coupling:
  # CWIPI parameters (optional)
  cwipi:
    geom_tol : 0.025                  # (optional, default=0.05) Geometric tolerence for CWIPI Localization
    dl_val_not_located : [0.0]        # (mandatory*, shape=phy_nfields) Default values of not located points (*if exist)
    phy_val_not_located : [0.0]       # (mandatory*, shape=dl_nfields) Default values of not located points (*if exist)
```

#### Mesh
If `voxgrid` is set as `mesh_type` the following block is mandatory to define the bounds and the refinement of the voxels grid.
```yaml
# Python mesh parameters
PythonMesh :
  xmin : 4.0e-3                       # (mandatory)
  ymin : 3.0e-3                       # (mandatory)
  zmin : 0.0                          # (mandatory)
  dx : 8.0e-5                         # (mandatory)
  nx : 176                            # (mandatory)
  ny : 46                             # (mandatory)
  nz : 65                             # (mandatory)
  # Overlap options (optional)
  overlap :
    overlap : True                    # (optional, default=False) Overlap activation
    x_n_elmts : 12                    # (optional, default=0) X-axis: elements number
    y_n_elmts : 10                    # (optional, default=0) Y-axis: elements number
    z_n_elmts : 8                     # (optional, default=0) Z-axis: elements number
```


#### Output
Output options
```yaml
# Output parameters (optional)
Output:
  logfile : "phydll.log"              # (optional, default="phydll.log") Log file
  logfile_jid : True                  # (optional, default=True) Append slurm job id to logfile name
  debug_level : 4                     # (optional, default=2) Debug level (verbosity) [0, 1, 2, 3, 4]
```











