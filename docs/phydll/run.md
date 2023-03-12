

# Run the coupling with PhyDLL

The *Multiple Program Multiple Data* (*MPMD*) execution enables to run in a parallel environment the coupling of the Physical Solver to Deep Learning inference with PhyDLL.  A `slurm` job generator, written in Python, is provided with PhyDLL library ([`./scripts/jobscript_generator.py`](https://gitlab.com/cerfacs/phydll/-/blob/master/scripts/jobscript_generator.py)). It allows to generate a job script to submit with `sbatch`. Furthermore, it generates the correct placement for the MPI tasks. Indeed the placement generator ([`./scripts/placement4mpmd.py`](https://gitlab.com/cerfacs/phydll/-/blob/master/scripts/placement4mpmd.py)) should be located in the same directory as job script generator. The arguments parse by the job script generator are described below.

### Job script generator
- **Job script file nime**
    + `--filename`: Job script file name. <br><br>

- **Slurm options**
	+ `--jobname`, `-J`: Slurm’s job name.
	+ `--partition`, `-p`: Slurm’s partition name.
	+ `--nodes`, `-n`: Number of Slurm’s computing nodes.
	+ `--time`, `-t`: Slurm’s limit of run time.
	+ `--output`, `-o`: Slurm’s redirected stdout and stderr.
	+ `--exclusive`, `-e`: Slurm’s exclusive mode. <br><br>

- **Load modules**
	+ `--module`, `--lm`: Modules to load (with append). <br><br>

- **Extra commands to add**
	+ `--extra_commands`, `--xcmd`: Extra linux commands to add, eg. activate a Python environment. <br><br>

- **Tasks**
	+ `--phy_tasks_per_node`, `--phytn`:  Number of MPI tasks for the Physical Solver.
	+ `--dl_tasks_per_node`, `--dltn`:  Number of MPI tasks for the Deep Learning engine. <br><br>

- **Append Python Path**
	+ `--append_pypath`: Path to pre-append to `PYTHONPATH`. <br><br>

- **Run mode**
	- `--runmode`: Run mode provides three options: `--runmode=ompi` corresponds to `mpirun` of *OpenMPI*; `--runmode=impi` corresponds to `mpirun` of *Intel MPI*; `--runmode=srun` corresponds to Slurm’s `srun` (does not depend on the MPI implementation). This discrepancy comes from the MPI placement configuration. <br><br>

- **Executables**
	- `--phyexec`: Physical solver executable.
	- `--dlexec`: Python "executable". <br><br>

### Example
- Generate the script
```bash
python jobscript_generator.py \
--filename jobscript.sh \
--jobname myjob --partition gpudev --nodes 4 --time 00:30:00 --output output --exclusive \
--module MPImodule --module CUDAmodule \
--xcmd "source ./myenv/bin/activate" \
--phytn 32 --dltn 4  \
--runmode srun \
--phyexec "./FortranSolver.exe" --dlexec "python DLengine.py" \
```

- It generates the following file
```bash
$ cat jobscript.sh
#!/bin/bash
#SBATCH --job-name=myjob
#SBATCH --partition=gpudev
#SBATCH --nodes=4
#SBATCH --time=00:30:00
#SBATCH --output=output.%j
#SBATCH --exclusive

# LOAD MODULES ##########
module purge
module load MPImodule
module load CUDAmodule
module list
#########################

# NUMBER OF TASKS #######
export PHY_TASKS_PER_NODE=32
export DL_TASKS_PER_NODE=4
export TASKS_PER_NODE=$(($PHY_TASKS_PER_NODE + $DL_TASKS_PER_NODE))
export NP_PHY=$(($SLURM_NNODES * $PHY_TASKS_PER_NODE))
export NP_DL=$(($SLURM_NNODES * $DL_TASKS_PER_NODE))
#########################

# EXTRA COMMANDS ########
source ./myenv/bin/activate
#########################

# ENABLE PHYDLL #########
export ENABLE_PHYDLL=TRUE
#########################

# PLACEMENT FILE ########
python ./placement4mpmd.py --Run srun --NpPHY $NP_PHY --NpDL $NP_DL --PHYEXE './FortranSolver.exe' --DLEXE 'python DLengine.py'
#########################

# MPMD EXECUTION ########
srun -l --kill-on-bad-exit -m arbitrary -w $machinefile --multi-prog ./phydll_mpmd_$SLURM_NNODES-$NP_PHY-$NP_DL.conf
#########################
```

- To submit the job
```bash
sbatch jobscript.sh
```