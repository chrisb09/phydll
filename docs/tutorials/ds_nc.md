
# Non-context aware coupling
**Note:** In this tutorial, `$PHYDLL_HOME` stands for PhyDLL repository cloned from Gitlab.


This tutorial shows how to couple a physical solver (`Fortran`) to a deep learning engine (`Python`). PhyDLL performs a non-context aware coupling. It means that exchanged data does not have a topology structure. Hence, the definition of the coupling does require any mesh information. 
![Non-context aware coupling](../images/tutorial_ds_nc.png)



This tutorial is available in [`$PHYDLL_HOME/test/ds_nc/`](https://gitlab.com/cerfacs/phydll/-/tree/release/0.1/test/ds_nc) and it contains
+ [`main.f90`](https://gitlab.com/cerfacs/phydll/-/tree/release/0.1/test/ds_nc/main.f90) which represents the physical solver. It can be compiled using the `Makefile`.
+ [`main.py`](https://gitlab.com/cerfacs/phydll/-/tree/release/0.1/test/ds_nc/main.py) which is a DL engine with dummy prediction. 
+ [`phydll.yml`](https://gitlab.com/cerfacs/phydll/-/tree/release/0.1/test/ds_nc/phydll.yml) which is the input file of PhyDLL.

### Running steps:
#### 1. Compile PhyDLL
PhyDLL should be installed as described in [PhyDLL#install](https://gitlab.com/cerfacs/phydll/-/tree/release/0.1/doc/phydll/install.md). For this tutorial, CWIPI and HDF5 support are not required. 

#### 2. Compile tutorial
`main.f90` should be compiled as well. If the [`Makefile`](https://gitlab.com/cerfacs/phydll/-/tree/release/0.1/test/ds_nc/Makefile) is used, it generates the binary file `main.exec`.

#### 3. Generate jobscript and run
The job script generator [`$PHYDLL_HOME/scripts/jobscript_generator.py`](https://gitlab.com/cerfacs/phydll/-/tree/release/0.1/scripts/jobscript_generator.py) is highly recommended to create a slurm script to run the coupling. After the script is generated, the job could be submitted with `sbatch`.


The description of the subroutines used in this tutorial is available in [PhyDLL#deployment](./tutorial.md).