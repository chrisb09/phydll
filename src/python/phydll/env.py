""" Copyright (c) CERFACS (all rights reserved)
file        env.py
@details    PhyDLL MPI environment
@authors    A. Serhani, C. Lapeyre, G. Staffelbach
@email      phydll@cerfacs.fr
"""
import sys

from mpi4py import rc as mpirc

mpirc.initialize = False
mpirc.finalize = False
from mpi4py import MPI


class Environment:
    """
    PhyDLL's MPI environment

    Attributes:
        MPI         (object)    MPI object.
        glcomm      (object)    Global communicator (Physical solver app + DL app).
        glcomm_size (int)       Size of global communicator `glcomm`.
        glcomm_rank (int)       Current MPI rank in global communicator `glcomm`.
        comm        (object)    Local communicator (DL app).
        comm_size   (int)       Size of local communicator `comm`.
        comm_rank   (int)       Current MPI rank in local communicator `comm`.
        comm_hrank  (int)       Host rank in local communicator `comm`.
        drank       (int)       Distant rank (host rank of Physical solver app) in global communicator `glcomm`.
        hrank       (int)       Host rank of DL app in global communicator `glcomm`.
        dsize       (int)       Size of distant communicator (Physical app comm).
    """
    def __init__(self):
        self.MPI = MPI
        self.mpi_init()


    def mpi_init(self):
        """
        Initialise PhyDLL MPI, create MPI global and local communicator, and get parameters
        as comm sizes, ranks, ...
        """
        self.MPI.Init()

        self.glcomm = self.MPI.COMM_WORLD
        self.glcomm_size = self.glcomm.Get_size()
        self.glcomm_rank = self.glcomm.Get_rank()

        color = 124
        self.comm = self.glcomm.Split(color, 0)
        self.comm_size = self.comm.Get_size()
        self.comm_rank = self.comm.Get_rank()

        self.comm_hrank = 0
        self.drank = 0
        self.hrank = self.glcomm_size - self.comm_size
        self.dsize = self.glcomm_size - self.comm_size


    def finalize(self):
        """
        Finalize PhyDLL
        """
        self.MPI.Finalize()
        sys.exit()


    @property
    def is_commhrank(self):
        """
        Check if the current mpi procces is the host
        """
        return True if self.comm_rank == self.comm_hrank else False
