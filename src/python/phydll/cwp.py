""" Copyright (c) CERFACS (all rights reserved)
@file       coupling_cwp.py
@details    PhyDLL CWIPI interface subroutines.
@authors    A. Serhani, V. Xing, C. Lapeyre, G. Staffelbach
@email      phydll@cerfacs.fr
"""
import os
from cwipi import cwipi
import numpy as np

class CWIPI:
    """
    CWIPI coupling object

    Args:
        env     (object)    MPI environment.
        io      (tuple)     Tuple of input and output objects.
        params  (tuple)     Coupling parameters (phy_nfields, dl_nfields and cpl_freq)

    Attributes:
        mpienv                  (object)    MPI environment
        input                   (object)    Input object
        output                  (object)    Output object
        mesh                    (object)    Mesh object
        cwp_coupling            (object)    CWIPI coupling object
        val_not_loc             (list)      Default values for not-located points
        phy_fields              (np.array)  Received Physical solver fields
        dl_fields               (np.array)  DL fields sent to Physical solver
        located_points          (np.array)  List of indexes of located points
        not_located_points      (np.arary)  List of indexes of not located points
        coords                  (np.array)  CWIPI mesh coordinates (it should not be desallocated)
        phy_fields_msize        (float)     Memory size of Physical solver fields
        dl_fields_msize         (float)     Memory size of DL fields
        phy_nfields             (int)       Number of received fields (Physical solver fields)
        dl_nfields              (int)       Number of sent fields (DL fields)
        cpl_freq                (int)       Coupling frequency
        phy_ite                 (int)       Current temporal Physical solver iteration
        cpl_ite                 (int)       Current coupling iteration
        n_located_points        (int)       Number of located points
        n_not_located_points    (int)       Number of not located points

    Notes:
        shape(phy_fields) = (phy_nfields, mesh.nvertex)
        shape(dl_fields) = (dl_nfields * mesh.nvertex,)
    """
    def __init__(self, env, io, params):
        """
        Init CWIPI class
        """
        self.mpienv = env
        self.input, self.output = io
        self.mesh = None
        self.cwp_coupling = None

        self.val_not_loc = []

        self.phy_fields = np.array([], dtype="float64")
        self.dl_fields = np.array([], dtype="float64")
        self.coords = np.array([], dtype="int32")
        self.located_points = np.array([], dtype="int32")
        self.not_located_points = np.array([], dtype="int32")

        self.phy_fields_msize = 0.
        self.dl_fields_msize = 0.

        self.phy_nfields, self.dl_nfields, self.cpl_freq = params
        self.phy_ite = 0
        self.cpl_ite = 0
        self.n_located_points = 0
        self.n_not_located_points = 0

        self.cwp_params = {}
        self.cwp_params["geom_tol"] = 0.0
        self.cwp_params["outfreq"] = 0
        self.cwp_params["cplname"] = ""
        self.cwp_params["appname"] = ""
        self.cwp_params["distname"] = ""
        self.cwp_params["output_fmt"] = ""
        self.cwp_params["output_fmt_opt"] = ""

        self.declare_coupling()


    def declare_coupling(self):
        """
        Init and declare CWIPI coupling
        """

        try:
            self.input.cwipi_params = self.input.coupling_params["cwipi"]
        except KeyError:
            self.input.cwipi_params = {}

        try:
            self.cwp_params["geom_tol"] = self.input.cwipi_params["geom_tol"]
        except KeyError:
            self.cwp_params["geom_tol"] = 0.05
        buff = np.array([self.cwp_params["geom_tol"]], dtype="float")
        self.mpienv.glcomm.Bcast(buf=[buff, self.mpienv.MPI.DOUBLE], root=self.mpienv.hrank)

        self.cwp_params["outfreq"] = self.input.coupling_params["save_fields_frequency"]

        buff = np.zeros(3, dtype='c')
        self.mpienv.glcomm.Bcast([buff, self.mpienv.MPI.CHAR], root=self.mpienv.drank)
        self.cwp_params["distname"] = "".join(map(bytes.decode, buff))

        self.cwp_params["appname"] = "dl"
        buff = np.array(self.cwp_params["appname"], dtype='c')
        self.mpienv.glcomm.Bcast([buff, self.mpienv.MPI.CHAR], root=self.mpienv.hrank)

        # Init cwipi
        cwipi.init(self.mpienv.glcomm, self.cwp_params["appname"])

        self.cwp_params["cplname"] = "phydll"
        self.cwp_params["output_fmt"] = b"Ensight Gold"
        self.cwp_params["output_fmt_opt"] = b"text"

        dblv = 2
        self.output.log_hl1(" ", dblv)
        self.output.log_hl1("CWIPI parameters:", dblv)
        self.output.log_hl2(f"{'CWP Geom tolerence':<20} = {self.cwp_params['geom_tol']}", dblv)
        self.output.log_hl2(f"{'CWP coupling name' :<20} = {self.cwp_params['cplname']}", dblv)
        self.output.log_hl2(f"{'CWP app name' :<20} = {self.cwp_params['appname']}", dblv)
        self.output.log_hl2(f"{'CWP dist app name' :<20} = {self.cwp_params['distname']}", dblv)
        self.output.log_hl2(f"{'CWP output fmt' :<20} = {self.cwp_params['output_fmt']}", dblv)
        self.output.log_hl2(f"{'CWP output opt fmt' :<20} = {self.cwp_params['output_fmt_opt']}", dblv)


    def set_python_mesh(self, mesh):
        """
        Wrapper to set, define and locate Python mesh object;
        Initialize Phy/DL fields

        Args:
            mesh    (object)    Mesh object
        """
        dblv = 1
        self.output.log_hl1("Define CWIPI mesh ...", dblv)
        tic = self.mpienv.MPI.Wtime()
        self._define_mesh(mesh)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.set_mesh += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)

        self.output.log_hl1("Locate CWIPI mesh ...", dblv)
        tic = self.mpienv.MPI.Wtime()
        self._locate_mesh()
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.set_mesh += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)

        self.phy_fields = np.zeros((self.phy_nfields, self.mesh.nvertex), dtype=np.float64)
        self.dl_fields = np.zeros(self.dl_nfields * self.mesh.nvertex, dtype=np.float64)

        self.phy_fields_msize = self.mesh.nvertex * self.phy_nfields * self.phy_fields.itemsize / 1024**2
        self.dl_fields_msize = self.mesh.nvertex * self.dl_nfields * self.dl_fields.itemsize / 1024**2


    def _define_mesh(self, mesh):
        """
        Set and define CWIPI mesh

        Args:
            mesh    (object)    Mesh object
        """
        self.mesh = mesh

        self.cwp_coupling = cwipi.Coupling(
            self.cwp_params["cplname"],
            cwipi.COUPLING_PARALLEL_WITH_PARTITIONING,
            self.cwp_params["distname"],
            mesh.dim,
            self.cwp_params["geom_tol"],
            cwipi.STATIC_MESH,
            cwipi.SOLVER_CELL_VERTEX,
            self.cwp_params["outfreq"],
            self.cwp_params["output_fmt"],
            self.cwp_params["output_fmt_opt"]
        )

        if self.mesh.dim == 2:
            self.coords = np.stack((self.mesh.coords[::self.mesh.dim],
                                    self.mesh.coords[1::self.mesh.dim],
                                    np.zeros(self.mesh.nvertex)),
                                    axis=1).ravel()
        elif self.mesh.dim == 3:
            self.coords = self.mesh.coords

        self.connec = 1 * self.mesh.connec

        # Reodrer connectivity
        if self.mesh.topo_type == "Tetrahedron":
            self.connec[1::self.mesh.nmeshv] = self.mesh.connec[2::self.mesh.nmeshv]
            self.connec[2::self.mesh.nmeshv] = self.mesh.connec[1::self.mesh.nmeshv]
        elif self.mesh.topo_type == "Wedge":
            self.connec[1::self.mesh.nmeshv] = self.mesh.connec[5::self.mesh.nmeshv]
            self.connec[2::self.mesh.nmeshv] = self.mesh.connec[3::self.mesh.nmeshv]
            self.connec[3::self.mesh.nmeshv] = self.mesh.connec[1::self.mesh.nmeshv]
            self.connec[5::self.mesh.nmeshv] = self.mesh.connec[2::self.mesh.nmeshv]

        self.cwp_coupling.define_mesh(
            self.mesh.nvertex,
            self.mesh.nelmt,
            self.coords,
            self.mesh.connecindex,
            self.connec
        )


    def _locate_mesh(self):
        """
        Run/load CWIPI localization
        """
        dsize = self.mpienv.dsize
        csize = self.mpienv.comm_size
        loc_file = f"phydll_cwp_locfile-{dsize}-{csize}"
        loc_file_exists = os.path.exists(loc_file)

        dblv = 2
        if loc_file_exists:
            self.output.log_hl2("Location file found! Load it ...", dblv)
            tic = self.mpienv.MPI.Wtime()
            self.cwp_coupling.open_location_file(loc_file, 'r')
            self.cwp_coupling.load_location()
            self.cwp_coupling.close_location_file()
            toc = self.mpienv.MPI.Wtime()
            self.output.log_hl2(timer=(toc-tic), dblv=dblv)

        else:
            self.output.log_hl2("Location file not found! Locate ...", dblv)
            tic = self.mpienv.MPI.Wtime()
            self.cwp_coupling.open_location_file(loc_file, 'w')
            self.cwp_coupling.locate()
            toc = self.mpienv.MPI.Wtime()
            self.output.log_hl2(timer=(toc-tic), dblv=dblv)

            self.output.log_hl2("Save location file ...", dblv)
            tic = self.mpienv.MPI.Wtime()
            self.cwp_coupling.save_location()
            self.cwp_coupling.close_location_file()
            toc = self.mpienv.MPI.Wtime()
            self.output.log_hl2(timer=(toc-tic), dblv=dblv)

        self.n_not_located_points = self.cwp_coupling.get_n_not_located_points()
        self.n_located_points = self.cwp_coupling.get_n_located_points()
        self.not_located_points = self.cwp_coupling.get_not_located_points()
        self.located_points = self.cwp_coupling.get_located_points()

        dblv = 3
        self.output.log_hl2("Localization resutls:", dblv)
        self.output.log_hl2(f"{'MPI rank':<15} {'Py Located pts':<20} {'Py NotLocated pts':<20}", dblv)
        self.output.log_hl2(f"{self.mpienv.comm_rank:<15} {self.n_located_points:<20} {self.n_not_located_points:<20}",
                            dblv=dblv, allmpi=True)

        if self.n_not_located_points > 0:
            self.val_not_loc = self.input.cwipi_params["dl_val_not_located"]
            assert len(self.val_not_loc) == self.phy_nfields, \
                f"Size of dl_val_not_located != phy_nfields ({len(self.val_not_loc)} != {self.phy_nfields})"

        buff = np.zeros(1, dtype="int32")
        self.mpienv.glcomm.Bcast(buf=[buff, self.mpienv.MPI.INTEGER], root=self.mpienv.drank)
        checknlp = buff[0]
        if checknlp > 0:
            phy_val_not_loc = self.input.cwipi_params["phy_val_not_located"]
            assert len(phy_val_not_loc) == self.dl_nfields, \
                f"Size of phy_val_not_located != dl_nfields ({len(phy_val_not_loc)} != {self.dl_nfields})"
            self.mpienv.glcomm.Bcast(buf=[np.array(phy_val_not_loc, dtype="float64"), self.dl_nfields, self.mpienv.MPI.DOUBLE],
                                    root=self.mpienv.hrank)


    def receive(self, index=-1, phy_ite=0, cpl_ite=0):
        """
        Non-blocking receive of Physical solver fields + Wait();
        Handle not-located points.

        Args:
            phy_ite     (int)   Current Physical Solver iteration
            cpl_ite     (int)   Current coupling iteration

        Returns:
            phy_fields (np.array)  Physical solver fields of shape: (phy_nfields, mesh.nvertex)
        """
        self.phy_ite = phy_ite
        self.cpl_ite = cpl_ite

        tic = self.mpienv.MPI.Wtime()

        exchname = b'phydll_r_phy'
        tag = 1777
        time_step_visu = self.phy_ite
        time_val_visu = float(self.phy_ite)

        if index == -1:
            recvfieldsname = b'phy_fields'
            stride = self.phy_nfields
            phy_fields = np.zeros(self.mesh.nvertex * stride, dtype=np.float64)

        elif index >= 0:
            recvfieldsname = f"phy_fields_{index}"
            stride = 1
            phy_fields = np.zeros(self.mesh.nvertex * stride, dtype=np.float64)


        irecv_dic = self.cwp_coupling.irecv(exchname, tag, stride,
                                            time_step_visu, time_val_visu,
                                            recvfieldsname, phy_fields)

        toc = self.mpienv.MPI.Wtime()
        self.output.timers.recv["comm"] = toc - tic

        self.cwp_coupling.wait_irecv(irecv_dic)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.recv["wait"] = toc - tic

        tic = self.mpienv.MPI.Wtime()
        if self.n_not_located_points > 0:
            phy_fields = self._handle_cwipi_notlocpts(phy_fields, index)
        self._pp_phy_fields(phy_fields, index)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.recv["post"] = toc - tic

        self.output.timers.recv["full"] = sum(list(self.output.timers.recv.values())[:-1])

        return self.phy_fields


    # @USER
    def _pp_phy_fields(self, array, index=-1):
        """
        Post-process received data (Physical solver fields);
        Reshape Physical solver fields to (phy_nfields, mesh.nvertex)

        Args:
            array   (np.array)  Array of shape: (phy_nfields * mesh.nvertex,)
        """
        if index == -1:
            for i in range(self.phy_nfields):
                self.phy_fields[i, :] = array[i::self.phy_nfields]

        elif index >= 0:
            self.phy_fields[index, :] = array


    def _pp_dl_fields(self, array):
        """
        Pre-process sent data (DL fields);
        Reshape DL fields to (dl_nfields * mesh.nvertex,)

        Args:
            array   (np.array) Array of shape: (dl_nfields, mesh.nvertex)
        """
        for i in range(self.dl_nfields):
            self.dl_fields[i::self.dl_nfields] = array[i, :]


    def send(self, dl_fields):
        """
        Non-blocking synchronous send of DL fields + Wait()

        Args:
            dl_fields   (np.array)  DL fields of shape: (dl_nfields, mesh.nvertex)
        """
        tic = self.mpienv.MPI.Wtime()
        self._pp_dl_fields(dl_fields)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.send["prep"] = toc - tic

        tic = self.mpienv.MPI.Wtime()
        exchname = b"phydll_s_dl"
        tag = 7111
        stride = self.dl_nfields
        time_step_visu = self.phy_ite
        time_val_visu = float(self.phy_ite)
        sendfieldsname = b"dl_fields"

        issend_dic = self.cwp_coupling.issend(exchname, tag, stride,
                                              time_step_visu, time_val_visu,
                                              sendfieldsname, self.dl_fields)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.send["comm"] = toc - tic

        tic = self.mpienv.MPI.Wtime()
        self.cwp_coupling.wait_issend(issend_dic)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.send["wait"] = toc - tic

        self.output.timers.send["full"] = sum(list(self.output.timers.send.values())[:-1])


    def _handle_cwipi_notlocpts(self, array, index=-1):
        """
        Set default values (val_not_loc) to not-located points

        Args:
            array           (np.array)  Array of shape: (phy_nfields * mesh.nvertex, )

        Returns
            handled_array   (np.array)  Array of shape: (phy_nfields * mesh.nvertex, )
        """
        handled_array = np.ones_like(array)

        if index == -1:
            for i in range(self.phy_nfields):
                handled_array[i::self.phy_nfields] = self.val_not_loc[i] * np.ones_like(array[i::self.phy_nfields])
                handled_array[i::self.phy_nfields][self.located_points-1] = array[i::self.phy_nfields][:self.n_located_points]

        elif index >= 0:
            handled_array[index::self.phy_nfields] = self.val_not_loc[index] * np.ones_like(array)
            handled_array[index::self.phy_nfields][self.located_points-1] = array[:self.n_located_points]

        return handled_array
