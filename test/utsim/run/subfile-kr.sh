#!/bin/bash
#SBATCH -J myjob
#SBATCH -p prod
#SBATCH -N 1
#SBATCH -t 01:00:00
#SBATCH -n 36
#SBATCH --exclusive

# COMPILER (INTEL/GNU)###
module purge
export COMPILER="INTEL"
#########################

# LOAD MODULES ##########
if [[ $COMPILER == "GNU" ]]; then
    module load avbpdl_gnu
    source $SCRATCH/pyenvs/pytf26-gcc/bin/activate
    export FC=mpifort
    export RUNMODE=ompi
    export MPIFLAG="--tag-output --rankfile rankfile_"
elif [[ $COMPILER == "INTEL" ]]; then
    module load avbpdl_intel
    module load python/tf2.6-cuda11.2-py39
    export FC=mpiifort
    export RUNMODE=impi
    export MPIFLAG="-l --machinefile machinefile_"
fi
module load tools/ddt
module list
#########################

# FORTRAN SOLVER COMPIL #
function solcompil() {
    set -x; \cd ../solver; make FC=$FC; \cd -; set +x
}
solcompil
#########################

# NUMBER OF TASKS #######
export PHY_TASKS_PER_NODE=28
export DL_TASKS_PER_NODE=4
export TASKS_PER_NODE=$(($PHY_TASKS_PER_NODE + $DL_TASKS_PER_NODE))
export NP_PHY=$(($SLURM_NNODES * $PHY_TASKS_PER_NODE))
export NP_DL=$(($SLURM_NNODES * $DL_TASKS_PER_NODE))
#########################

# # SUPRESSION ############
mkdir -p ./OUTPUTED_MESH_PARTITIONS
mkdir -p ./HASH_TABLES
rm -rf ./PhyDLL_FIELDS
rm -rf ./PhyDLL_MESH/*
rm -rf ./cwipi/*
rm -f ./OUTPUTED_MESH_PARTITIONS/*
rm -f ./phydll_cwp_locfile*
# rm -f el2part_$NP_PHY.h5
# #########################

# MESHFILE ##############
# mesh_label=mesh_2d_struc_coarse.mesh.h5
# mesh_label=mesh_2d_unstruc_coarse.mesh.h5
mesh_label=mesh_3d_unstruc_mid.mesh.h5
# mesh_label=mesh_3d_struc_coarse.mesh.h5
# mesh_label=mesh_3d_prism_mid.mesh.h5
# mesh_label=mesh_3d_prism_coarse.mesh.h5
mesh=../mesh/$mesh_label
#########################

# # PARTITIONING ##########
echo "  Partitioning ..."
set -x
if [[ $COMPILER == "GNU" ]]; then
    ./partitioning.sh -m $mesh -n $NP_PHY &> partitioning.log
    cp el2part_$NP_PHY.h5 el2part_${mesh_label}_$NP_PHY.h5
fi
set +x
# #########################

# ELEMENT TOPOLOGY ######
cp el2part_${mesh_label}_$NP_PHY.h5 el2part_$NP_PHY.h5
export EL2PART_ELEMENT_TYPE=$(h5ls el2part_$NP_PHY.h5/part0000001 | grep -e "->" | awk '{ print $1}')
#########################

# PLACEMENT FILE ########
python ../../../scripts/placement4mpmd.py --Run $RUNMODE --NpPHY $NP_PHY --NpDL $NP_DL
#########################

# MPMD EXECUTION ########
set -x
mpirun $MPIFLAG$SLURM_NNODES-$NP_PHY-$NP_DL -np $NP_PHY ../solver/solver.exe : -np $NP_DL python ../dleng/main.py
set +x
#########################
