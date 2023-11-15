# mesh=../meshes/mesh_2d_unstruc_coarse.mesh.h5

import os
import h5py
import numpy as np

mesh_file = os.getenv("mesh")
print(f"{mesh_file = }")

# Fields count
count = 2

# Mesh
# f = h5py.File(mesh_file, "r")
with h5py.File(mesh_file, "r") as f:
    _connec_ds = f["Connectivity"]
    _coords_ds = f["Coordinates"]

    geodim = len(list(_coords_ds.keys()))

    topo = list(_connec_ds.keys())[0]
    if topo == "tri->node":
        geodim = 2
        nvert = 3
    elif topo == "qua->node":
        geodim = 2
        nvert = 4
    elif topo == "tet->node":
        geodim = 3
        nvert = 4
    elif topo == "hex->node":
        geodim = 3
        nvert = 8
    ncell = len(_connec_ds[topo]) // nvert
    ntcell = ncell

    nnode = len(_coords_ds[list(_coords_ds.keys())[0]])
    ntnode = nnode

    connec = np.array(_connec_ds[topo], dtype=np.int)

    coords = np.zeros(geodim * nnode, dtype=np.float)
    for i, key in enumerate(_coords_ds.keys()):
        coords[i::geodim] = _coords_ds[key][:]

    local_cell_to_global = np.arange(1, ncell+1)
    local_node_to_global = np.arange(1, nnode+1)
# f.close()

from mpi4py import MPI
from time import sleep
from os.path import abspath, dirname
import sys
sys.path.insert(0, f"{abspath(dirname(__file__))}/../../../src/python/pyphydll")
from pyphydll import PhyDLL

niter = 1

phyl = PhyDLL()

phyl.init(instance="physical")
comm = phyl.get_local_mpi_comm()
myrank = comm.Get_rank()

phyl.define_phy_with_mesh(
    count, geodim, ncell, nnode, ntcell, ntnode, nvert, connec,
    coords, local_cell_to_global, local_node_to_global
)

phy_fields = {}
dl_fields = {}
for iter in range(niter):
    for i in range(phyl.phy_count):
        ampl = 10.
        sigx = 2./3
        sigy = 1./2
        phy_fields[f"python_phy_fields_{i}"] = (-1)**(i+1) * ampl * np.exp(-(coords[::geodim] - 3./2)**2/(2*sigx**2) - (coords[1::geodim] - 1.)**2/(2*sigy**2))

    phyl.send(phy_fields)

    sleep(2)

    dl_fields = phyl.recv()

phyl.finalize()

"""
cd /scratch/coop/serhani/AVBP-DL/PhyDLL/src/utsim/run
loadgnu
export mesh=$(realpath ../meshes/mesh_2d_unstruc_coarse.mesh.h5)
rm -rf PhyDLL_FIELDS/*; mpirun -n 1 python ../solver/main_solver_seq.py : -n 1 python ../../test/dl_main.py
"""
