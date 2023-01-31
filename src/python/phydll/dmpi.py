""" Copyright (c) CERFACS (all rights reserved)
@file       dmpi.py
@details    PhyDLL dMPI interface subroutines.
@authors    A. Serhani, C. Lapeyre, G, Staffelbach
@email      phydll@cerfacs.fr
"""

import numpy as np


class dMPI:
    """
    dMPI coupling object

    Args:
        env     (object)    MPI environment.
        io      (tuple)     Tuple of input and output objects.
        params  (tuple)     Coupling parameters (phy_nfields, dl_nfields and cpl_freq)

    Attributes:
        mpienv              (object)    MPI environment
        input               (object)    Input object
        output              (object)    Output object
        mesh                (object)    Mesh object
        corresp_phy_ranks   (list)      Corresponding phy ranks
        nnodes_list         (list)      List of number of mesh nodes (or field size) of corresponding Physical solver processes
        phy_fields          (np.array)  Received Physical solver fields
        dl_fields           (np.array)  DL fields sent to Physical solver
        phy_fields_msize    (float)     Memory size of Physical solver fields
        dl_fields_msize     (float)     Memory size of DL fields
        phy_nfields         (int)       Number of received fields (Physical solver fields)
        dl_nfields          (int)       Number of sent fields (DL fields)
        cpl_freq            (int)       Coupling frequency
        mesh_type           (char)      Mesh type ("NC", "phymesh")
        phy_task_per_dl     (int)       Number Physical solver MPI task per DL task
        phy_ite             (int)       Current temporal Physical solver iteration
        cpl_ite             (int)       Current coupling iteration
        save_fields_frequency    (int)  Output frequency for exchanged fields

    Notes:
        shape(phy_fields) = (phy_nfields, mesh.nvertex)
        shape(dl_fields) = (dl_nfields * mesh.nvertex_dup,)
    """
    def __init__(self, env, io, params):
        """
        Init dMPI class
        """
        self.mpienv = env
        self.input, self.output = io
        self.mesh = None

        self.corresp_phy_ranks = []
        self.nnodes_list = []

        self.phy_fields = np.array([], dtype="float64")
        self.dl_fields = np.array([], dtype="float64")
        self.phy_fields_msize = 0.
        self.dl_fields_msize = 0.
        self.phy_nfields, self.dl_nfields, self.cpl_freq, self.mesh_type = params
        self.phy_task_per_dl = 0
        self.phy_ite = 0
        self.cpl_ite = 0

        self.save_fields_frequency = self.input.coupling_params["save_fields_frequency"]


    def set_nc(self):
        """
        Set non-context aware coupling
        """
        tic = self.mpienv.MPI.Wtime()

        av_t_py_q = self.mpienv.dsize // self.mpienv.comm_size
        av_t_py_r = self.mpienv.dsize % self.mpienv.comm_size

        self.phy_task_per_dl = av_t_py_q + (self.mpienv.comm_rank < av_t_py_r)
        phy_task_per_dl_list = self.mpienv.comm.allgather(self.phy_task_per_dl)
        self.corresp_phy_ranks = range(sum(phy_task_per_dl_list[:self.mpienv.comm_rank]),
                                        sum(phy_task_per_dl_list[:self.mpienv.comm_rank+1]))

        self.nnodes_list = np.zeros((len(self.corresp_phy_ranks), 1), dtype="int32")
        requests = []
        for i in self.corresp_phy_ranks:
            j = i % self.phy_task_per_dl
            request = self.mpienv.glcomm.Irecv(buf=[self.nnodes_list[j], 1, self.mpienv.MPI.INTEGER], source=i, tag=83)
            requests.append(request)
        self.mpienv.MPI.Request.Waitall(requests)
        self.nnodes_list = list(self.nnodes_list[:].reshape(-1))

        self.phy_fields = np.zeros((self.phy_nfields, sum(self.nnodes_list)), dtype=np.float64)
        self.dl_fields = np.zeros(sum(self.nnodes_list) * self.dl_nfields, dtype=np.float64)

        toc = self.mpienv.MPI.Wtime()
        self.output.timers.create_mesh = toc - tic

        dblv = 2
        message = f"{'MPI_rank':<12} {'field size':<15} {'nfields':<10} {'(glcomm) dlrank: corresp. Phy rank':35}"
        self.output.log_hl2(message, dblv)
        phyranklist = ', '.join(map(str, self.corresp_phy_ranks))
        message = f"{self.mpienv.comm_rank:<12} {sum(self.nnodes_list):<10} {f'{self.phy_nfields}':<20} {f'{self.mpienv.glcomm_rank:3d}: {phyranklist}':35}"
        self.output.log_hl2(message, dblv, allmpi=True)
        self.output.log_hl2(" ", dblv)


    def set_python_mesh(self, mesh):
        """
        Set mesh object for dMPI coupling;
        Get Physical solver and DL processes mapping;
        Initialize Phy/DL fields

        Args:
            mesh    (object)    Mesh object
        """
        tic = self.mpienv.MPI.Wtime()

        self.mesh = mesh

        # Processes mapping
        self.phy_task_per_dl = self.mesh.phy_task_per_dl
        self.corresp_phy_ranks = self.mesh.corresp_phy_ranks
        self.nnodes_list = self.mesh.nnodes_list

        self.phy_fields = np.zeros((self.phy_nfields, self.mesh.nvertex), dtype=np.float64)
        self.dl_fields = np.zeros(self.mesh.nvertex_dup * self.dl_nfields, dtype=np.float64)

        self.phy_fields_msize = self.mesh.nvertex_dup * self.phy_nfields * self.phy_fields.itemsize / 1024**2
        self.dl_fields_msize = self.mesh.nvertex_dup * self.dl_nfields * self.dl_fields.itemsize / 1024**2

        toc = self.mpienv.MPI.Wtime()
        self.output.timers.set_mesh = toc - tic


    def receive(self, index=-1, phy_ite=0, cpl_ite=0):
        """
        Non-blocking receive of Physical solver fields + Wait();
        Reshape and remove duplicated nodes

        Args:
            phy_ite     (int)   Current Physical solver ite
            cpl_ite     (int)   Current coupling ite

        Returns:
            phy_fields (np.array)  Physical solver fields of shape: (phy_nfields, mesh.nvertex)
        """
        self.phy_ite = phy_ite
        self.cpl_ite = cpl_ite

        tic = self.mpienv.MPI.Wtime()

        if index == -1:
            phyfields_dup = np.zeros(sum(self.nnodes_list) * self.phy_nfields, dtype="float64")
        elif index >= 0:
            phyfields_dup = np.zeros(sum(self.nnodes_list), dtype="float64")

        requests = []
        for phyrank in self.corresp_phy_ranks:
            j = phyrank % self.phy_task_per_dl

            tag = 1777
            dtype = self.mpienv.MPI.DOUBLE

            if index == -1:
                ind = sum(self.nnodes_list[:j]) * self.phy_nfields
                count = self.nnodes_list[j] * self.phy_nfields

            elif index >= 0:
                ind = sum(self.nnodes_list[:j])
                count = self.nnodes_list[j]

            request = self.mpienv.glcomm.Irecv(buf=[phyfields_dup[ind:ind+count], count, dtype],
                                                source=phyrank, tag=tag)
            requests.append(request)

        toc = self.mpienv.MPI.Wtime()
        self.output.timers.recv["comm"] = toc - tic

        tic = self.mpienv.MPI.Wtime()
        self.mpienv.MPI.Request.Waitall(requests)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.recv["wait"] = toc - tic

        tic = self.mpienv.MPI.Wtime()
        self._pp_phy_fields(phyfields_dup, index)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.recv["post"] = toc - tic

        self.output.timers.recv["full"] = sum(list(self.output.timers.recv.values())[:-1])

        return self.phy_fields


    def _pp_phy_fields(self, array, index=-1):
        """
        Post-process received data (Physical solver fields);
        Remove duplicated nodes;
        Reshape Physical solver fields to (phy_nfields, mesh.nvertex)

        Args:
            array   (np.array)  Array of shape: (phy_nfields * mesh.nvertex_dup,)
        """
        if index == -1:
            for i in range(self.phy_nfields):
                if self.mesh_type == "NC":
                    self.phy_fields[i, :] = array[i::self.phy_nfields]

                elif self.mesh_type == "phymesh":
                    self.phy_fields[i, :] = array[i::self.phy_nfields][self.mesh.idx_unique]

        elif index >= 0:
            if self.mesh_type == "NC":
                self.phy_fields[index, :] = array

            elif self.mesh_type == "phymesh":
                self.phy_fields[index, :] = array[self.mesh.idx_unique]


    def _pp_dl_fields(self, array):
        """
        Pre-process sent data (DL fields);
        Add dupliacted nodes;
        Reshape DL fields to (1, dl_nfields * mesh.nvertex_dup

        Args:
            array   (np.array) Array of shape: (dl_nfields, mesh.nvertex)
        """
        if self.dl_nfields == 1:
            self.dl_fields = array.reshape((1, -1))

        else:
            for i in range(self.dl_nfields):
                if self.mesh_type == "phymesh":
                    idx_sort = self.mesh.idx_sort
                    idx_inverse = self.mesh.idx_inverse
                    self.dl_fields[i::self.dl_nfields] = array[i, :][idx_sort][idx_inverse]

                elif self.mesh_type == "NC":
                    self.dl_fields[i::self.dl_nfields] = array[i, :]


    def send(self, dl_fields, index=-1):
        """
        Non-blocking synchronous send of DL fields + Wait();
        Save exchanged fields (if enabled)

        Args:
            dl_fields   (np.array)  DL fields of shape: (dl_nfields, mesh.nvertex)
        """
        tic = self.mpienv.MPI.Wtime()
        self._pp_dl_fields(dl_fields)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.send["prep"] = toc - tic

        tic = self.mpienv.MPI.Wtime()

        requests = []
        for phyrank in self.corresp_phy_ranks:
            j = phyrank % self.phy_task_per_dl

            tag = 7111
            dtype = self.mpienv.MPI.DOUBLE
            ind = sum(self.nnodes_list[:j]) * self.dl_nfields
            count = self.nnodes_list[j] * self.dl_nfields
            buf = self.dl_fields[ind:ind+count]

            if index >= 0:
                buf = np.asfortranarray(buf[index::self.dl_nfields])
                count = self.nnodes_list[j]

            request = self.mpienv.glcomm.Issend(buf=[buf, count, dtype], dest=phyrank, tag=tag)
            requests.append(request)

        toc = self.mpienv.MPI.Wtime()
        self.output.timers.send["comm"] = toc - tic

        tic = self.mpienv.MPI.Wtime()
        self.mpienv.MPI.Request.Waitall(requests)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.send["wait"] = toc - tic

        if (self.mesh_type == "phymesh") and \
            ((self.cpl_ite - 1 + self.save_fields_frequency) % self.save_fields_frequency == 0) and \
            (index in (-1, self.phy_nfields - 1)):
            self.output.save_fields(phy_fields=self.phy_fields, dl_fields=dl_fields,
                                    mesh=self.mesh, phy_nfields=self.phy_nfields,
                                    dl_nfields=self.dl_nfields, cpl_ite=self.cpl_ite)

        self.output.timers.send["full"] = sum(list(self.output.timers.send.values())[:-1])
