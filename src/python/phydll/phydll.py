""" Copyright (c) CERFACS (all rights reserved)
@file       phydll.py
@details    PhyDLL Python interface.
@authors    A. Serhani, C. Lapeyre, G. Staffelbach
@email      phydll@cerfacs.fr
"""
import numpy as np
from phydll.env import Environment
from phydll.io import Input, Output

class PhyDLL:
    """
    PhyDLL class

    Args:
        coupling_scheme (char)  Coupling scheme
        mesh_type       (char)  Mesh type
        n_phy_fields    (int)   Number of Physical solver fields
        n_dl_fields     (int)   Number of DL fields

    Attributes:
        mpienv          (object)    MPI environment
        input           (object)    Input object
        output          (object)    Output object
        cplinterf       (object)    Coupling interface ("IS", "DS")
        mesh            (object)    Mesh object ("NC", "voxgrid", "phymesh")
        predict         (callable)  Prediction function (to set from DL object)
        phy_fields      (np.array)  Received fields from Physical solver
        dl_fields       (np.array)  Fields computed by the inference (to send to Physical solver)
        phy_ite         (int)       Current Physical solver temporal-iteration
        cpl_ite         (int)       Current coupling iteration
        coupling_scheme (char)      Coupling scheme
        mesh_type       (char)      Mesh type (voxgrid, phymesh)
        phy_nfields     (int)       Number of Physical fields
        dl_nfields      (int)       Number of DL fields

    Notes :
        This object manages PhyDLL subroutitens and API.
    """
    def __init__(self, coupling_scheme="DS", mesh_type="NC", phy_nfields=1, dl_nfields=1):
        """
        Init PhyDLL class
        """
        self.mpienv = Environment()
        self.input = Input(env=self.mpienv)
        self.output = Output(env=self.mpienv, inp=self.input)
        self.cplinterf = None
        self.mesh = None
        self.predict = None

        self.phy_fields = np.array([], dtype="float64")
        self.dl_fields = np.array([], dtype="float64")

        self.phy_ite = 0
        self.cpl_ite = 0

        self.coupling_scheme = coupling_scheme
        self.mesh_type = mesh_type
        self.phy_nfields = phy_nfields
        self.dl_nfields = dl_nfields

        self.set_coupling_interface()
        self.set_mesh_object()
        self.pre_processing()


    def set_coupling_interface(self):
        """
        Set coupling interface
        """
        tic = self.mpienv.MPI.Wtime()
        self.output.log(f"Coupling scheme = {self.coupling_scheme}")

        buff = np.zeros(64, dtype="c"); buff[:] = " "
        buff[:len(self.coupling_scheme)] = self.coupling_scheme
        self.mpienv.glcomm.Bcast(buf=[buff, self.mpienv.MPI.CHARACTER], root=self.mpienv.hrank)

        buff = np.array([self.phy_nfields], dtype="i")
        self.mpienv.glcomm.Bcast(buf=[buff, self.mpienv.MPI.INTEGER], root=self.mpienv.hrank)

        buff = np.array([self.dl_nfields], dtype="i")
        self.mpienv.glcomm.Bcast(buf=[buff, self.mpienv.MPI.INTEGER], root=self.mpienv.hrank)

        self.cpl_freq = self.input.coupling_params["coupling_frequency"]
        buff = np.array([self.cpl_freq], dtype="i")
        self.mpienv.glcomm.Bcast(buf=[buff, self.mpienv.MPI.INTEGER], root=self.mpienv.hrank)

        buff = np.zeros(16, dtype="c"); buff[:] = " "
        buff[:len(self.mesh_type)] = self.mesh_type
        self.mpienv.glcomm.Bcast(buf=[buff, self.mpienv.MPI.CHARACTER], root=self.mpienv.hrank)

        self.save_fields_frequency = self.input.coupling_params["save_fields_frequency"]
        buff = np.array([self.save_fields_frequency], dtype="i")
        self.mpienv.glcomm.Bcast(buf=[buff, self.mpienv.MPI.INTEGER], root=self.mpienv.hrank)

        buff = np.zeros(256, dtype="c"); buff[:] = " "
        buff[:len(self.output.fields_dir)] = self.output.fields_dir
        self.mpienv.glcomm.Bcast(buf=[buff, self.mpienv.MPI.CHARACTER], root=self.mpienv.hrank)

        toc = self.mpienv.MPI.Wtime()
        self.output.timers.create_cpl += toc - tic


    def set_mesh_object(self):
        """
        Set mesh object (voxgrid or phymesh)
        """
        assert self.mesh_type in ("voxgrid", "phymesh", "NC"), \
            f"mesh_type (={self.mesh_type}) should be 'voxgrid', 'phymesh' or 'NC'."

        if self.mesh_type == "voxgrid":
            from phydll.mesh import VoxGrid
            self.mesh = VoxGrid(env=self.mpienv, io=(self.input, self.output))

        elif self.mesh_type == "phymesh":
            from phydll.mesh import PhyMesh
            self.mesh = PhyMesh(env=self.mpienv, io=(self.input, self.output))


    def pre_processing(self):
        """
        PhyDLL pre-processing: Initialize coupling interface, create DL mesh
        """
        tic = self.mpienv.MPI.Wtime()

        self.output.log_hl0(f"Create {self.coupling_scheme} coupling\n", dblv=0)
        dblv = 1
        self.output.log_hl1(f"{'Mesh type' :<21} = {self.mesh_type}", dblv)
        self.output.log_hl1(f"{'Coupling frequency' :<21} = {self.cpl_freq}", dblv)
        self.output.log_hl1(f"{'Number of Phy fields' :<21} = {self.phy_nfields}", dblv)
        self.output.log_hl1(f"{'Number of DL fields' :<21} = {self.dl_nfields}", dblv)
        if not self.mesh_type == "NC":
            self.output.log_hl1(f"{'Save fields frequency' :<21} = {self.save_fields_frequency}", dblv)

        if self.coupling_scheme in ("IS", "InterpolationScheme"):
            from phydll.cwp import CWIPI
            self.cplinterf = CWIPI(env=self.mpienv, io=(self.input, self.output),
                                params=(self.phy_nfields, self.dl_nfields, self.cpl_freq))

        elif self.coupling_scheme in ("DS", "DirectScheme"):
            from phydll.dmpi import dMPI
            self.cplinterf = dMPI(env=self.mpienv, io=(self.input, self.output),
                                params=(self.phy_nfields, self.dl_nfields, self.cpl_freq, self.mesh_type))

        toc = self.mpienv.MPI.Wtime()
        self.output.timers.create_cpl += toc - tic
        self.output.log_hl0(timer=self.output.timers.create_cpl, dblv=0)

        if self.coupling_scheme in ("DS", "DirectScheme") and self.mesh_type == "NC":
            self.cplinterf.set_nc()
            self.output.log_hl0(timer=self.output.timers.create_mesh, dblv=0)

        elif self.mesh_type in ("voxgrid", "phymesh"):
            self.output.log_hl0("Create DL mesh \n", dblv=0)
            self.mesh.create_python_mesh()
            self.output.log_hl0(timer=self.output.timers.create_mesh, dblv=0)

            self.output.log_hl0(f"Set DL mesh for {self.coupling_scheme} coupling\n", dblv=0)
            self.cplinterf.set_python_mesh(self.mesh)
            self.output.log_hl0(timer=self.output.timers.set_mesh, dblv=0)


    def set_predict_func(self, predict):
        """
        Set prediction function for the temporal loop
        """
        self.predict = predict


    @property
    def fsignal(self):
        """
        Check if Physical solver is ready to exchange
        """
        buff = np.zeros(1, dtype='i')
        self.mpienv.glcomm.Bcast(buff, root=self.mpienv.drank)
        self.phy_ite = buff[0]

        if buff >= 1:
            is_running = True
        elif buff == -1:
            is_running = False

        return is_running


    def temporal(self):
        """
        Temporal loop: Receive Physical fields + predict + send DL fields
        """
        self.output.log_hl0("Temporal \n", dblv=0)
        self.output.timers.temporal = self.mpienv.MPI.Wtime()
        while self.fsignal:
            self.output.log_hl1(f"Coupling iteration (Phy ite) = {self.cpl_ite} ({self.phy_ite}) ...", dblv=1)

            # Receive field
            self.phy_fields = self.receive_phy_fields()

            # Prediction
            self.output.log_hl2("Predict ...", dblv=3)
            self.dl_fields = self.predict(self.phy_fields)

            # Send field
            self.send_dl_fields(self.dl_fields)


    def receive_phy_fields(self):
        """
        Wrapper to receive Physical solver fields

        Returns:
            phy_fields  (np.array)  Physical solver fields
        """
        self.cpl_ite += 1

        if self.phy_ite in (0, 1):
            self.output.log_hl0("Temporal \n", dblv=0)
            self.output.log_hl1(f"Coupling iteration = {self.cpl_ite} ...", dblv=1)
            self.output.timers.temporal = self.mpienv.MPI.Wtime()

        self.output.log_hl2("Receive Physical solver fields ...", dblv=3)
        self.phy_fields = self.cplinterf.receive(phy_ite=self.phy_ite, cpl_ite=self.cpl_ite)
        return self.phy_fields


    def send_dl_fields(self, dl_fields):
        """
        Wrapper to send deep learning fields

        Args:
            dl_fields   (np.array) Deep learning fields
        """
        self.output.log_hl2("Send DL fields ...", dblv=3)

        self.dl_fields = dl_fields
        self.cplinterf.send(self.dl_fields)

        self.output.dump_temporal_table(msizes=(self.cplinterf.phy_fields_msize, self.cplinterf.dl_fields_msize))
        self.output.log_hl1(timer=self.output.timers.temporal_ite, dblv=1)

        self.output.timers.temporal_ite = 0.0


    def finalize(self):
        """
        Finalize PhyDLL
        """
        self.output.timers.temporal = self.mpienv.MPI.Wtime() - self.output.timers.temporal
        self.output.log_hl0(timer=self.output.timers.temporal, dblv=0)
        self.output.log_hl0("Finalize \n", dblv=0)
        self.mpienv.finalize()
