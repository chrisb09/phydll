""" Copyright (c) CERFACS (all rights reserved)
@file       jobscript_generator.py
@details    SLURM's job script generator
@autor      A. Serhani
"""
import argparse
import os

parser = argparse.ArgumentParser()

# Jobscript filename
parser.add_argument("--filename", type=str, help="Jobscript filename", default="./mysubfile.sh")

# Slurm options
parser.add_argument("--jobname", "-J", type=str, help="Job name", default="jobname")
parser.add_argument("--partition", "-p", type=str, help="Partition", default="debug")
parser.add_argument("--nodes", "-n", type=int, help="Number of nodes", default=1)
parser.add_argument("--time", "-t", type=str, help="Allocation time", default="00:10:00")
parser.add_argument("--output", "-o", type=str, help="Output file", default="output")
parser.add_argument("--exclusive", "-e", action="store_true")

# Modules
parser.add_argument("--module", "--lm", action="append", help="module to load")

# Number of tasks for physical solver and deep learning engine
parser.add_argument("--phy_tasks_per_node", "--phytn", type=int, help="Number of Physical solver tasks per node", default=36)
parser.add_argument("--dl_tasks_per_node", "--dltn", type=int, help="Number of DL tasks per node", default=4)

# Run mode
parser.add_argument("--runmode", type=str, help="Run mode", default="ompi")

# Executables
parser.add_argument("--phyexec", type=str, help="Physical solver executable", default="PHYEXEC")
parser.add_argument("--dlexec", type=str, help="DL executable (eg. python dlmain.py)", default="python dlmain.py")

# Extra commands
parser.add_argument("--extra_commands", "--xcmd", action="append", help="Extra commands")

# Append to Python path
parser.add_argument("--append_pypath", action="append", help="Extra commands")

# Parse arguments
args = parser.parse_args()
filename = args.filename
jobname = args.jobname
partition = args.partition
nodes = args.nodes
time = args.time
output = args.output
excl = args.exclusive
mods = args.module
phytn = args.phy_tasks_per_node
dltn = args.dl_tasks_per_node
runmode = args.runmode
phyexec = args.phyexec
dlexec = args.dlexec
cmds = args.extra_commands
pypath = args.append_pypath

def main():
    """
    Write job script
    """
    file = filename
    with open(file, "w") as f:
        f.write("#!/bin/bash\n")

    sbatch_options(file, jobname, partition, nodes, time, output, excl)
    modules(file, mods)
    environment_variables(file, phytn, dltn)
    extra_commands(file, cmds)
    append_python_path(file, pypath)
    enable_phydll(file)
    placement_file(file, runmode, phyexec, dlexec)
    run_command(file, runmode, phyexec, dlexec)

def sbatch_options(file, jobname, partition, nodes, time, output, excl):
    """
    Set slurm options
    """
    with open(file, "a") as f:
        f.write(f"#SBATCH --job-name={jobname}\n")
        f.write(f"#SBATCH --partition={partition}\n")
        f.write(f"#SBATCH --nodes={nodes}\n")
        f.write(f"#SBATCH --time={time}\n")
        f.write(f"#SBATCH --output={output}.%j\n")
        if excl:
            f.write(f"#SBATCH --exclusive\n")
        f.write("\n")

def modules(file, mod):
    """
    Create block to load modules
    """
    with open(file, "a") as f:
        f.write(f"# LOAD MODULES {10*'#'}\n")
        f.write(f"module purge\n")
        if mod is None:
            f.write(f"\n")
        else:
            for m in mod:
                f.write(f"module load {m}\n")
        f.write(f"module list\n")
        f.write(f"{25*'#'}\n\n")

def environment_variables(file, phy_tasks_per_node, dl_tasks_per_node):
    """
    Set numbers of tasks
    """
    with open(file, "a") as f:
        f.write(f"# NUMBER OF TASKS\n")
        f.write(f"export PHY_TASKS_PER_NODE={phy_tasks_per_node}\n")
        f.write(f"export DL_TASKS_PER_NODE={dl_tasks_per_node}\n")
        f.write(f"export TASKS_PER_NODE=$(($PHY_TASKS_PER_NODE + $DL_TASKS_PER_NODE))\n")
        f.write(f"export NP_PHY=$(($SLURM_NNODES * $PHY_TASKS_PER_NODE))\n")
        f.write(f"export NP_DL=$(($SLURM_NNODES * $DL_TASKS_PER_NODE))\n")
        f.write(f"{25*'#'}\n\n")

def extra_commands(file, cmds):
    """
    Write extra commands
    """
    with open(file, "a") as f:
        f.write("# EXTRA COMMANDS ########\n")
        if cmds is None:
            f.write("\n")
        else:
            for cmd in cmds:
                f.write(f"{cmd}\n")
        f.write(f"{25*'#'}\n\n")

def append_python_path(file, pypath):
    """
    Append python path
    """
    with open(file, "a") as f:
        if pypath is not None:
            f.write("# APPEND PYTHON PATH ####\n")
            for path in pypath:
                f.write(f"export PYTHONPATH={path}:$PYTHONPATH\n")
            f.write(f"{25*'#'}\n\n")

def enable_phydll(file):
    """
    Enable PhyDLL
    """
    with open(file, "a") as f:
        f.write("# ENABLE PHYDLL #########\n")
        f.write("export ENABLE_PHYDLL=TRUE\n")
        f.write(f"{25*'#'}\n\n")

def placement_file(file, runmode, phyexec, dlexec):
    """
    Generate placement file
    """
    with open(file, "a") as f:
        f.write(f"# PLACEMENT FILE ########\n")
        f.write(f"python {os.path.dirname(__file__)}/placement4mpmd.py --Run {runmode} --NpPHY $NP_PHY --NpDL $NP_DL")

        if runmode == "srun":   f.write(f" --PHYEXE '{phyexec}' --DLEXE '{dlexec}'\nn")
        else: f.write("\n")
        f.write(f"{25*'#'}\n\n")

def run_command(file, runmode, phyexec, dlexec):
    """
    Write run command depending on the run mode
    """
    with open(file, "a") as f:
        f.write(f"# MPMD EXECUTION ########\n")
        if runmode == "srun":
            f.write("srun -l --kill-on-bad-exit -m arbitrary -w $machinefile ")
            f.write("--multi-prog ./phydll_mpmd_$SLURM_NNODES-$NP_PHY-$NP_DL.conf\n")

        else:
            if runmode == "ompi":
                placement = "--tag-output --rankfile rankfile_$SLURM_NNODES-$NP_PHY-$NP_DL"
            elif runmode == "impi":
                placement = "-l --machinefile machinefile_$SLURM_NNODES-$NP_PHY-$NP_DL"

            f.write(f"mpirun {placement} -np $NP_PHY {phyexec} : -np $NP_DL {dlexec}\n")
        f.write(f"{25*'#'}\n\n")

if __name__ == "__main__":
    main()
