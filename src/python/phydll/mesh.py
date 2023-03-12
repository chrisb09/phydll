""" Copyright (c) CERFACS (all rights reserved)
@file       mesh.py
@details    PhyDLL meshes
@authors    A. Serhani, V. Xing, P. Mohanamuraly, C. Lapeyre, G. Staffelbach
@email      phydll@cerfacs.fr
"""
import os
import numpy as np
from math import ceil


class PhyMesh:
    """
    dMPI coupling object

    Args:
        env     (object)    MPI environment.
        io      (tuple)     Tuple of input and output objects.

    Attributes:
        mpienv                  (object)    MPI environment
        input                   (object)    Input object
        output                  (object)    Output object
        corresp_phy_ranks       (range)     Range of corresponding Physical solver ranks
        nnodes_list             (list)      List of number of mesh nodes of corresponding Physical solver processes
        coords                  (np.array)  Coordinates of local python mesh partition [x0,y0,z0, ..., xN,yN,zN]
        idx_inverse             (np.array)  Map local python partition to Physical solver partitions
        idx_unique              (np.array)  Map Physical solver partitions to local python partition
        idx_sort                (np.array)  Map Physical solver partitions to local python partition
        connec                  (np.array)  Local partition: connectivity table
        connec_r                (np.array)  Local partition: reshaped connectivity table -> (nelmt, nmeshv)
        connecindex             (np.array)  Local partition: connectivity indexes (for CWIPI)
        dim                     (int)       Geometric dimension
        global_nvertex          (int)       Full mesh: number of vertices
        global_nelmt            (int)       Full mesh: number of elements
        nmeshv                  (int)       Number of vertices per element
        phy_task_per_dl         (int)       Number of Physical solver MPI task per python task
        nvertex                 (int)       Local partition: number of vertices
        nelmt                   (int)       Local partition: number of elements
        nvertex_dup             (int)       Local partition: number of veritices with duplicated nodes
        dmpi_saves_rep          (char)      Repository to save/load partitionning data
        topo_type               (char)      Topology type of mesh elements
    """
    def __init__(self, env, io):
        """
        Init PhyMesh class
        """
        self.mpienv = env
        self.input, self.output = io

        self.corresp_phy_ranks = range(0)

        self.nnodes_list = []

        self.coords = np.array([], dtype="float64")
        self.idx_inverse = np.array([], dtype="int32")
        self.idx_unique = np.array([], dtype="int32")
        self.idx_sort = np.array([], dtype="int32")
        self.connec = np.array([], dtype="int32")
        self.connec_r = np.array([], dtype="int32")
        self.connecindex = np.array([], dtype="int32")

        self.dim = 0
        self.global_nvertex = 0
        self.global_nelmt = 0
        self.nmeshv = 0
        self.phy_task_per_dl = 0
        self.nvertex = 0
        self.nelmt = 0
        self.nvertex_dup = 0

        self.phydll_mesh_rep = "./PhyDLL_MESH"


    def create_python_mesh(self):
        """
        Create python local mesh
        """
        dblv = 1
        self.output.log_hl1(f"Mesh type = {self.__class__.__name__}", dblv)

        buf = np.zeros(1, dtype="i")
        self.mpienv.glcomm.Bcast(buf=[buf, 1, self.mpienv.MPI.INTEGER], root=self.mpienv.drank)
        self.dim = buf[0]
        self.output.log_hl1(f"Mesh dimension = {self.dim}D\n")

        self.output.log_hl1("Retrieve Physical solver partitions ...", dblv)
        tic = self.mpienv.MPI.Wtime()
        connec, coords, lnode2g, lelm2g = self._recv_phy_partitioning()
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.create_mesh += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)

        self.output.log_hl1("Aggregate partitions ...", dblv)
        tic = self.mpienv.MPI.Wtime()
        self._aggregate_phy_partitions(connec, coords, lnode2g, lelm2g)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.create_mesh += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)


    def _recv_phy_partitioning(self):
        """
        Probe and receive Physical solver mesh partitions (connec, LocalToGlobal, ...)

        Returns:
            connec      (tuple)     Tuple of list of corresponding Physical solver connectivities, and list of associated sizes
            coords      (tuple)     Tuple of list of corresponding Physical solver coordinates, and list of associated sizes
            lnode2g     (tuple)     Tuple of list of corresponding Physical solver tables of 'local node to global', and list of associated sizes
            lelm2g      (tuple)     Tuple of list of corresponding Physical solver tables of 'local element to global', and list of associated sizes
        """
        av_t_py_q = self.mpienv.dsize // self.mpienv.comm_size
        av_t_py_r = self.mpienv.dsize % self.mpienv.comm_size

        self.phy_task_per_dl = av_t_py_q + (self.mpienv.comm_rank < av_t_py_r)
        phy_task_per_dl_list = self.mpienv.comm.allgather(self.phy_task_per_dl)
        self.corresp_phy_ranks = range(sum(phy_task_per_dl_list[:self.mpienv.comm_rank]),
                                        sum(phy_task_per_dl_list[:self.mpienv.comm_rank+1]))

        connec_list = [None] * self.phy_task_per_dl
        node_coords_list = [None] * self.phy_task_per_dl
        local_node_to_global_list = [None] * self.phy_task_per_dl
        local_element_to_global_list = [None] * self.phy_task_per_dl

        cm_n = 4
        requests = [[] for _ in range(cm_n)]
        count = [[[] for _ in range(self.phy_task_per_dl)] for _ in range(cm_n)]
        statuses = [self.mpienv.MPI.Status()] * cm_n

        for i in self.corresp_phy_ranks:
            j = i % self.phy_task_per_dl

            tag = 1
            self.mpienv.glcomm.Probe(source=i, tag=tag, status=statuses[0])
            count[0][j] = statuses[0].Get_count(self.mpienv.MPI.INTEGER)
            connec_list[j] = np.zeros(count[0][j], dtype="i")
            request = self.mpienv.glcomm.Irecv(buf=[connec_list[j], count[0][j], self.mpienv.MPI.INTEGER], source=i, tag=tag)
            requests[0].append(request)

            tag = 2
            self.mpienv.glcomm.Probe(source=i, tag=tag, status=statuses[1])
            count[1][j] = statuses[1].Get_count(self.mpienv.MPI.DOUBLE)
            node_coords_list[j] = np.zeros(count[1][j], dtype="float64")
            request = self.mpienv.glcomm.Irecv(buf=[node_coords_list[j], count[1][j], self.mpienv.MPI.DOUBLE], source=i, tag=tag)
            requests[1].append(request)

            tag = 3
            self.mpienv.glcomm.Probe(source=i, tag=tag, status=statuses[2])
            count[2][j] = statuses[2].Get_count(self.mpienv.MPI.INTEGER)
            local_node_to_global_list[j] = np.zeros(count[2][j], dtype="i")
            request = self.mpienv.glcomm.Irecv(buf=[local_node_to_global_list[j], count[2][j], self.mpienv.MPI.INTEGER], source=i, tag=tag)
            requests[2].append(request)

            tag = 4
            self.mpienv.glcomm.Probe(source=i, tag=tag, status=statuses[3])
            count[3][j] = statuses[3].Get_count(self.mpienv.MPI.INTEGER)
            local_element_to_global_list[j] = np.zeros(count[3][j], dtype="i")
            request = self.mpienv.glcomm.Irecv(buf=[local_element_to_global_list[j], count[3][j], self.mpienv.MPI.INTEGER], source=i, tag=tag)
            requests[3].append(request)

        requests = self._flatten_list(requests)
        self.mpienv.MPI.Request.Waitall(requests)

        buf = np.zeros(1, dtype="i")
        self.mpienv.glcomm.Bcast(buf=[buf, 1, self.mpienv.MPI.INTEGER], root=self.mpienv.drank)
        self.global_nvertex = buf[0]

        buf = np.zeros(1, dtype="i")
        self.mpienv.glcomm.Bcast(buf=[buf, 1, self.mpienv.MPI.INTEGER], root=self.mpienv.drank)
        self.global_nelmt = buf[0]

        buf = np.zeros(1, dtype="i")
        self.mpienv.glcomm.Bcast(buf=[buf, 1, self.mpienv.MPI.INTEGER], root=self.mpienv.drank)
        self.nmeshv = buf[0]

        return (connec_list, count[0]), (node_coords_list, count[1]), (local_node_to_global_list, count[2]), (local_element_to_global_list, count[3])


    def _aggregate_phy_partitions(self, connec, coords, lnode2g, lelm2g):
        """
        Aggregate Physical solver partitions into corresponding python partition

        Args:
            connec      (tuple)     Tuple of list of corresponding Physical solver connectivities, and list of associated sizes
            coords      (tuple)     Tuple of list of corresponding Physical solver coordinates, and list of associated sizes
            lnode2g     (tuple)     Tuple of list of corresponding Physical solver tables of 'local node to global', and list of associated sizes
            lelm2g      (tuple)     Tuple of list of corresponding Physical solver tables of 'local element to global', and list of associated sizes
        """
        # Get python (dup and unique) partition nnodes in global index
        dblv = 2

        self.output.log_hl2("Nodes agg ... ", dblv)
        tic = self.mpienv.MPI.Wtime()

        local_node_to_global_list, self.nnodes_list = lnode2g
        self.nvertex_dup = sum(self.nnodes_list)
        ln2g_flatarr_dup = np.array(self._flatten_list(local_node_to_global_list))
        _, idx_get_unique, self.idx_inverse = np.unique(ln2g_flatarr_dup, return_index=True, return_inverse=True)
        self.idx_unique = np.sort(idx_get_unique)
        ln2g_flatarr = ln2g_flatarr_dup[self.idx_unique] - 1
        self.idx_sort = np.argsort(ln2g_flatarr)

        # Python partition node coordinates
        coords_list, _ = coords
        coords_list = np.array(self._flatten_list(coords_list))
        self.coords = np.stack(tuple(coords_list[i::self.dim][self.idx_unique] for i in range(self.dim)), axis=1).ravel()
        self.nvertex = ln2g_flatarr.shape[0]

        toc = self.mpienv.MPI.Wtime()
        self.output.log_hl2(timer=(toc-tic), dblv=dblv)

        self.output.log_hl2("Connectivity agg ... ", dblv)
        tic = self.mpienv.MPI.Wtime()

        _, nelmt_list = lelm2g
        self.nelmt = sum(nelmt_list)

        if self.mpienv.is_commhrank and not os.path.isdir(self.phydll_mesh_rep):
            os.mkdir(self.phydll_mesh_rep)

        connec_file = f"{self.phydll_mesh_rep}/connec_file-{self.global_nvertex}-{self.mpienv.dsize}-{self.mpienv.comm_size}-{self.mpienv.comm_rank}.npy"
        if os.path.exists(connec_file):
            self.output.log_hl3(f"Connectivity table exists! Load it ... (file={connec_file})", dblv)
            self.connec = np.load(connec_file)

        else:
            # Hash table
            ln2g_flatarr_dic = {}
            for i in range(self.nvertex):
                ln2g_flatarr_dic[ln2g_flatarr[i]+1] = i

            # Python partition connectivity
            connec_list, _ = connec
            self.connec = np.zeros((self.nelmt * self.nmeshv), dtype="i")
            k = 0
            for i in range(self.phy_task_per_dl):
                for j in connec_list[i]:
                    self.connec[k] = ln2g_flatarr_dic[local_node_to_global_list[i][j-1]] + 1
                    k += 1
            np.save(connec_file, self.connec)

        self.connec_r = self.connec.reshape((self.nelmt, self.nmeshv))
        self.connecindex = np.array([i*self.nmeshv for i in np.arange(self.nelmt+1)], dtype="int32")

        toc = self.mpienv.MPI.Wtime()
        self.output.log_hl2(timer=(toc-tic), dblv=dblv)

        self.output.log_hl2(f"global nvertex = {self.global_nvertex}", dblv)
        self.output.log_hl2(f"global nelmt = {self.global_nelmt}\n", dblv)
        self.output.log_hl2(f"nvertex per elm = {self.nmeshv}", dblv)

        if self.nmeshv == 3: self.topo_type = "Triangle"
        elif self.nmeshv == 4 and self.dim == 2: self.topo_type = "Quadrilateral"
        elif self.nmeshv == 4 and self.dim == 3: self.topo_type = "Tetrahedron"
        elif self.nmeshv == 6: self.topo_type = "Wedge"
        elif self.nmeshv == 8: self.topo_type = "Hexahedron"
        self.output.log_hl2(f"Element topology = {self.topo_type}\n", dblv)

        message = f"{'MPI_rank':<12} {'nvertex':<15} {'connecsize':<20} {'(glcomm) dlrank: corresp. Phy rank':35}"
        self.output.log_hl2(message, dblv)

        phyranklist = ', '.join(map(str, self.corresp_phy_ranks))
        message = f"{self.mpienv.comm_rank:<12} {self.nvertex:<15} {f'{self.connec_r.shape}':<20} {f'{self.mpienv.glcomm_rank:3d}: {phyranklist}':35}"
        self.output.log_hl2(message, dblv, allmpi=True)
        self.output.log_hl2(" ", dblv)


    @staticmethod
    def _flatten_list(lst):
        """
        Flatten a list
        """
        return [i for sub in lst for i in sub]


class VoxGrid:
    """
    Create voxel grid (esp. for CNN inference)

    Args:
        env     (object)    MPI environment.
        io      (tuple)     Tuple of input and output objects.
        params  (tuple)     Input parameters (phy_nfields, dl_nfields and cpl_freq)

    Attributes:
        mpienv                  (object)    Mpi environment
        input                   (object)    Input object
        output                  (object)    Output object
        coords                  (np.array)  Coordinates in local mesh partition
        connecindex             (np.array)  Connectivity indexes in local mesh partition
        connec                  (np.array)  Connectivity in local mesh partition
        cpl_ite                 (int)       Current coupling iteration
        nvertex                 (int)       Number of vertices in local mesh partition
        nelmt                   (int)       Number of elements in local mesh partition
        n_located_points        (int)       Number of located points
        located_points          (np.array)  List of indexes of located points
        n_not_located_points    (int)       Number of not located points
        not_located_points      (np.arary)  List of indexes of not located points
        phy_ite                 (int)       Current temporal Physical solver iteration
        nmeshv
        voxgrid_nx              (int)       Number of x-axis cells
        voxgrid_ny              (int)       Number of y-axis cells
        voxgrid_nz              (int)       Number of z-axis celss
    """
    def __init__(self, env, io):
        """
        Init VoxGrid class
        """
        self.mpienv = env
        self.input, self.output = io

        self.voxgrid_dic = {}

        self.voxgrid_nx = 0
        self.voxgrid_ny = 0
        self.voxgrid_nz = 0

        self.dx = 0.0
        self.nx = 0
        self.ny = 0
        self.nz = 0
        self.xmin = 0.0
        self.xmax = 0.0
        self.zmin = 0.0
        self.zmax = 0.0
        self.ymin = 0.0
        self.ymax = 0.0
        self.nelmt = 0
        self.coords = np.array([], dtype="float64")
        self.connecindex = np.array([], dtype="int32")
        self.connec = np.array([], dtype="int32")
        self.connec_r = np.array([], dtype="int32")

        self.dim = 3
        self.nvertex = 0
        self.nmeshv = 8
        self.topo_type = "Hexahedron"

        # Overlap
        self.ol_x_n_elmts = 0
        self.ol_x_n_elmts_left = 0
        self.ol_x_n_elmts_right = 0
        self.ol_y_n_elmts = 0
        self.ol_y_n_elmts_down = 0
        self.ol_y_n_elmts_up = 0
        self.ol_z_n_elmts = 0
        self.ol_z_n_elmts_back = 0
        self.ol_z_n_elmts_front = 0
        self.with_overlap = self.input.python_mesh["overlap"]["overlap"]
        self.cartesian3d = None
        self.coord3d = []
        self.proc_neighb_left = self.mpienv.MPI.PROC_NULL
        self.proc_neighb_right = self.mpienv.MPI.PROC_NULL
        self.proc_neighb_down = self.mpienv.MPI.PROC_NULL
        self.proc_neighb_up = self.mpienv.MPI.PROC_NULL
        self.proc_neighb_back = self.mpienv.MPI.PROC_NULL
        self.proc_neighb_front = self.mpienv.MPI.PROC_NULL


    def create_python_mesh(self):
        """
        Wrapper: Create and partitionate voxgrid
        """
        dblv = 1
        self.output.log_hl1(f"Mesh type = {self.__class__.__name__}", dblv)
        self.output.log_hl1(f"Mesh dimension = {self.dim}D\n")


        self.output.log_hl1("Get mesh bounds ...", dblv)
        tic = self.mpienv.MPI.Wtime()
        rt0 = self._get_voxgrid_bound()
        toc = self.mpienv.MPI.Wtime()
        self.voxgrid_nx, self.voxgrid_ny, self.voxgrid_nz, self.dx = rt0
        self.output.timers.create_mesh += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)

        self.output.log_hl1("Partitionate mesh ...", dblv)
        tic = self.mpienv.MPI.Wtime()
        rt1 = self._partitionate_voxgrid(*rt0)
        toc = self.mpienv.MPI.Wtime()
        self.xmin, self.xmax, self.nx, self.ymin, self.ymax, self.ny, self.zmin, self.zmax, self.nz = rt1
        self.output.timers.create_mesh += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)

        self.output.log_hl1("Create voxgrid for each MPI process ...", dblv)
        tic = self.mpienv.MPI.Wtime()
        rt2 = self._create_voxgrid(*rt1)
        toc = self.mpienv.MPI.Wtime()
        self.nvertex, self.nelmt, self.coords, self.connecindex, self.connec = rt2
        self.output.timers.create_mesh += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)

        if self.with_overlap:
            self.output.log_hl1("Create overlap setting ...", dblv)
            tic = self.mpienv.MPI.Wtime()
            self.get_overlap_params()
            toc = self.mpienv.MPI.Wtime()
            self.output.timers.create_mesh += toc - tic
            self.output.log_hl1(timer=(toc-tic), dblv=dblv)


    def _get_voxgrid_bound(self):
        """
        Get grid bounds
        """
        self.voxgrid_dic = self.input.python_mesh

        voxgrid_xmin = self.voxgrid_dic['xmin']
        voxgrid_ymin = self.voxgrid_dic['ymin']
        voxgrid_zmin = self.voxgrid_dic['zmin']

        dx = self.voxgrid_dic['dx']
        voxgrid_nx = self.voxgrid_dic['nx']
        voxgrid_ny = self.voxgrid_dic['ny']
        voxgrid_nz = self.voxgrid_dic['nz']

        voxgrid_xmax = voxgrid_xmin + (voxgrid_nx - 1) * dx
        voxgrid_ymax = voxgrid_ymin + (voxgrid_ny - 1) * dx
        voxgrid_zmax = voxgrid_zmin + (voxgrid_nz - 1) * dx

        dblv = 2
        self.output.log_hl2(f"{'xmin':<8} = {voxgrid_xmin:10.6e}, {'':<4} xmax = {voxgrid_xmax:10.6e}", dblv)
        self.output.log_hl2(f"{'ymin':<8} = {voxgrid_ymin:10.6e}, {'':<4} ymax = {voxgrid_ymax:10.6e}", dblv)
        self.output.log_hl2(f"{'zmin':<8} = {voxgrid_zmin:10.6e}, {'':<4} zmax = {voxgrid_zmax:10.6e}", dblv)
        self.output.log_hl2(f"{'dx':<8} = {dx:10.6e}", dblv)
        self.output.log_hl2(f"{'nvertex':<8} = {voxgrid_nx * voxgrid_ny * voxgrid_nz}", dblv)
        self.output.log_hl2(f"{'nelmts':<8} = {(voxgrid_nx - 1) * (voxgrid_ny - 1) * (voxgrid_nz - 1)}")

        return voxgrid_nx, voxgrid_ny, voxgrid_nz, dx


    def _partitionate_voxgrid(self, voxgrid_nx, voxgrid_ny, voxgrid_nz, dx):
        """
        Partitionate voxel grId using recursive coordinate bisection
        """
        blocks, mpipg = self.recursive_coordinate_bisection(((0, voxgrid_nx - 1),
                                                            (0, voxgrid_ny - 1),
                                                            (0, voxgrid_nz - 1)),
                                                            self.mpienv.comm_size)
        (imin, imax), (jmin, jmax), (kmin, kmax) = blocks[self.mpienv.comm_rank]
        nx = imax - imin + 1
        ny = jmax - jmin + 1
        nz = kmax - kmin + 1

        xmin = self.voxgrid_dic['xmin'] + imin * dx
        ymin = self.voxgrid_dic['ymin'] + jmin * dx
        zmin = self.voxgrid_dic['zmin'] + kmin * dx
        xmax = self.voxgrid_dic['xmin'] + imax * dx
        ymax = self.voxgrid_dic['ymin'] + jmax * dx
        zmax = self.voxgrid_dic['zmin'] + kmax * dx

        dblv = 2
        self.output.log_hl2(f"Partitioning grid = {list(np.max(np.array(mpipg), axis=0) + 1)}", dblv)

        self.output.log_hl2(f"{'MPI rank':<10} {'xmin':<15} {'xmax':<15} {'ymin':<15} {'ymax':<15} {'zmin':<15} {'zmax':<15}", dblv)
        self.output.log_hl2(f"{self.mpienv.comm_rank:<10} {'%10.6e'%xmin:<15} {'%10.6e'%xmax:<15} {'%10.6e'%ymin:<15} {'%10.6e'%ymax:<15} {'%10.6e'%zmin:<15} {'%10.6e'%zmax:<15}", dblv, allmpi=True)
        self.output.log_hl2(f" ", dblv)

        self.output.log_hl2(f"{'MPI rank':<10} {'nx':<10} {'ny':<10} {'nz':<10}", dblv)
        self.output.log_hl2(f"{self.mpienv.comm_rank:<10} {nx:<10} {ny:<10} {nz:<10}", dblv, allmpi=True)
        self.output.log_hl2(f" ", dblv)

        dblv = 4
        self.output.log_hl2(f"{'MPI rank':<10} {'imin':<10} {'imax':<10} {'jmin':<10} {'jmax':<10} {'kmin':<10} {'kmax':<10}", dblv)
        self.output.log_hl2(f"{self.mpienv.comm_rank:<10} {imin:<10} {imax:<10} {jmin:<10} {jmax:<10} {kmin:<10} {kmax:<10}", dblv, allmpi=True)

        return xmin, xmax, nx, ymin, ymax, ny, zmin, zmax, nz


    def _create_voxgrid(self, xmin, xmax, nx, ymin, ymax, ny, zmin, zmax, nz):
        """
        Get voxgrid parameters to create CWIPI mesh
        """
        nvertex = nx * ny * nz
        nelmt = (nx - 1) * (ny - 1) * (nz - 1)
        coords = np.zeros(3 * nvertex, dtype="float64")
        coords[::3] = (xmin + (xmax-xmin)/(nx-1) * np.tile(np.arange(nx), nz*ny))
        coords[1::3] = (ymin + (ymax-ymin)/(ny-1) * np.tile(np.repeat(np.arange(ny), nx), nz))
        coords[2::3] = (zmin + (zmax-zmin)/(nz-1) * np.repeat(np.arange(nz), nx*ny))

        connecindex = np.array([i*self.nmeshv for i in np.arange(nelmt+1)], dtype="int32")

        connec = np.zeros(self.nmeshv * nelmt, dtype="int32")
        array_i = np.tile(np.arange(nx-1), (nz-1)*(ny-1))
        array_j = np.tile(np.repeat(np.arange(ny-1), nx-1), nz-1)
        array_k = np.repeat(np.arange(nz-1), (nx-1)*(ny-1))
        connec[::self.nmeshv] = array_i + 1 + array_j*nx + array_k*nx*ny
        connec[1::self.nmeshv] = array_i + 2 + array_j*nx + array_k*nx*ny
        connec[2::self.nmeshv] = array_i + 2 + (array_j+1)*nx + array_k*nx*ny
        connec[3::self.nmeshv] = array_i + 1 + (array_j+1)*nx + array_k*nx*ny
        connec[4::self.nmeshv] = array_i + 1 + array_j*nx + (array_k+1)*nx*ny
        connec[5::self.nmeshv] = array_i + 2 + array_j*nx + (array_k+1)*nx*ny
        connec[6::self.nmeshv] = array_i + 2 + (array_j+1)*nx + (array_k+1)*nx*ny
        connec[7::self.nmeshv] = array_i + 1 + (array_j+1)*nx + (array_k+1)*nx*ny

        self.connec_r = connec.reshape((nelmt, self.nmeshv))

        return nvertex, nelmt, coords, connecindex, connec


    def get_overlap_params(self):
        """
        Get overlap params
        """
        rdnx = self.mpienv.comm.allreduce(np.array([self.nx-1]), op=self.mpienv.MPI.MIN)
        rdny = self.mpienv.comm.allreduce(np.array([self.ny-1]), op=self.mpienv.MPI.MIN)
        rdnz = self.mpienv.comm.allreduce(np.array([self.nz-1]), op=self.mpienv.MPI.MIN)

        dimpart = [int(self.voxgrid_nx/rdnx), int(self.voxgrid_ny/rdny), int(self.voxgrid_nz/rdnz)]
        self.cartesian3d = self.mpienv.comm.Create_cart(dims=dimpart, periods =[False,False,False], reorder=False)
        self.proc_neighb_left, self.proc_neighb_right = self.cartesian3d.Shift(direction=0, disp=1)
        self.proc_neighb_down, self.proc_neighb_up = self.cartesian3d.Shift(direction=1, disp=1)
        self.proc_neighb_back, self.proc_neighb_front = self.cartesian3d.Shift(direction=2, disp=1)
        self.coord3d = self.cartesian3d.Get_coords(self.mpienv.comm_rank)

        try: self.ol_x_n_elmts = self.input.python_mesh["overlap"]["x_n_elmts"]
        except KeyError: pass

        try: self.ol_y_n_elmts = self.input.python_mesh["overlap"]["y_n_elmts"]
        except KeyError: pass

        try: self.ol_z_n_elmts = self.input.python_mesh["overlap"]["z_n_elmts"]
        except KeyError: pass

        self.ol_x_n_elmts_left = max(np.sign(self.proc_neighb_left+1), 0) * self.ol_x_n_elmts
        self.ol_x_n_elmts_right = max(np.sign(self.proc_neighb_right+1), 0) * self.ol_x_n_elmts

        self.ol_y_n_elmts_down = max(np.sign(self.proc_neighb_down+1), 0) * self.ol_y_n_elmts
        self.ol_y_n_elmts_up = max(np.sign(self.proc_neighb_up+1), 0) * self.ol_y_n_elmts

        self.ol_z_n_elmts_back = max(np.sign(self.proc_neighb_back+1), 0) * self.ol_z_n_elmts
        self.ol_z_n_elmts_front = max(np.sign(self.proc_neighb_front+1), 0) * self.ol_z_n_elmts

        dblv = 2
        self.output.log_hl2(f"X-axis: nb elmts = {self.ol_x_n_elmts}", dblv)
        self.output.log_hl2(f"Y-axis: nb elmts = {self.ol_y_n_elmts}", dblv)
        self.output.log_hl2(f"Z-axis: nb elmts = {self.ol_z_n_elmts}", dblv)

        dblv = 3
        self.output.log_hl2(f"MPI Cart dim = {dimpart}", dblv)
        self.output.log_hl2(f"MPI proc null := {self.mpienv.MPI.PROC_NULL}", dblv)
        self.output.log_hl2(f"MPI Grid: Coordinates and neighbours ranks", dblv)
        self.output.log_hl3(f"{'MPI rank':<10} {'Coords':<15} {'Left':<10} {'Right':<10} {'Down':<10} {'Up':<10} {'Back':<10} {'Front':<10}", dblv)
        self.output.log_hl3(f"{self.mpienv.comm_rank:<10} {str(self.coord3d):<15} {self.proc_neighb_left:<10} {self.proc_neighb_right:<10} {self.proc_neighb_down:<10} {self.proc_neighb_up:<10} {self.proc_neighb_back:<10} {self.proc_neighb_front:<10}", dblv, allmpi=True)


    def create_fields_with_overlap(self, array):
        """
        Create fields with overlap
        """
        if not self.with_overlap:
            return array

        nx = self.nx
        ny = self.ny
        nz = self.nz

        ol_l = self.ol_x_n_elmts_left
        ol_r = self.ol_x_n_elmts_right
        ol_d = self.ol_y_n_elmts_down
        ol_u = self.ol_y_n_elmts_up
        ol_b = self.ol_z_n_elmts_back
        ol_f = self.ol_z_n_elmts_front

        procnull = self.mpienv.MPI.PROC_NULL

        fields_wol = 100*np.ones((nx + ol_l + ol_r, ny + ol_d + ol_u, nz + ol_b + ol_f), dtype="float64")
        fields_wol[ol_l: nx+ol_l, ol_d: ny+ol_d, ol_b: nz+ol_b] = array


        # Shift to avoid shared nodes on interfaces
        shift = 1

        # left --> right (comm 1) (x-1D)
        sendbuf = np.ascontiguousarray(array[nx-ol_r-shift:-shift, :, :])
        recvbuf = np.zeros((ol_l, ny, nz), dtype="float64")
        dest = self.proc_neighb_right
        source = self.proc_neighb_left
        tag = 0
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag
            )
        fields_wol[:ol_l, ol_d:ny+ol_d, ol_b:nz+ol_b] = recvbuf

        # right --> left (comm 2) (x-1D)
        sendbuf = np.ascontiguousarray(array[shift:ol_l+shift, :, :])
        recvbuf = np.zeros((ol_r, ny, nz), dtype="float64")
        dest = self.proc_neighb_left
        source = self.proc_neighb_right
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag
            )
        fields_wol[nx+ol_l:, ol_d:ny+ol_d, ol_b:nz+ol_b] = recvbuf

        # down --> up (comm 3) (y-1D)
        sendbuf = np.ascontiguousarray(array[:, ny-ol_u-shift:-shift, :])
        recvbuf = np.zeros((nx, ol_d, nz), dtype="float64")
        dest = self.proc_neighb_up
        source = self.proc_neighb_down
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
            )
        fields_wol[ol_l:nx+ol_l, :ol_d, ol_b:nz+ol_b] = recvbuf

        # up --> down (comm 4) (y-1D)
        sendbuf = np.ascontiguousarray(array[:, shift:ol_d+shift, :])
        recvbuf = np.zeros((nx, ol_u, nz), dtype="float64")
        dest = self.proc_neighb_down
        source = self.proc_neighb_up
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
            )
        fields_wol[ol_l:nx+ol_l, ny+ol_d:, ol_b:nz+ol_b] = recvbuf

        # back --> front (comm 5) (z-1D)
        sendbuf = np.ascontiguousarray(array[:, :, nz-ol_f-shift:-shift])
        recvbuf = np.zeros((nx, ny, ol_b), dtype="float64")
        dest = self.proc_neighb_front
        source = self.proc_neighb_back
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag
            )
        fields_wol[ol_l:nx+ol_l, ol_d:ny+ol_d, :ol_b] = recvbuf

        # front --> back (comm 6) (z-1D)
        sendbuf = np.ascontiguousarray(array[:, :, shift:ol_b+shift])
        recvbuf = np.zeros((nx, ny, ol_f), dtype="float64")
        dest = self.proc_neighb_back
        source = self.proc_neighb_front
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag
            )
        fields_wol[ol_l:nx+ol_l, ol_d:ny+ol_d, nz+ol_b:] = recvbuf

        # left down --> right up (comm 7) (xy-2D)
        sendbuf = np.ascontiguousarray(array[nx-ol_r-shift:-shift, ny-ol_u-shift:-shift, :])
        recvbuf = np.zeros((ol_l, ol_d, nz), dtype="float64")
        dest = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_up == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1]+1, self.coord3d[2]])
        source = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_down == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1]-1, self.coord3d[2]])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
        )
        fields_wol[:ol_l, :ol_d, ol_b:nz+ol_b] = recvbuf

        # left up --> right down (comm 8) (xy-2D)
        sendbuf = np.ascontiguousarray(array[nx-ol_r-shift:-shift, shift:ol_d+shift, :])
        recvbuf = np.zeros((ol_l, ol_u, nz), dtype="float64")
        dest = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_down == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1]-1, self.coord3d[2]])
        source = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_up == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1]+1, self.coord3d[2]])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
            )
        fields_wol[:ol_l, ny+ol_d:, ol_b:nz+ol_b] = recvbuf

        # right down --> left up (comm 9) (xy-2D)
        sendbuf = np.ascontiguousarray(array[shift:ol_l+shift, ny-ol_u-shift:-shift, :])
        recvbuf = np.zeros((ol_r, ol_d, nz), dtype="float64")
        dest = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_up == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1]+1, self.coord3d[2]])
        source = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_down == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1]-1, self.coord3d[2]])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
            )
        fields_wol[nx+ol_l:, :ol_d, ol_b:nz+ol_b] = recvbuf

        # right up --> left down (comm 10) (xy-2D)
        sendbuf = np.ascontiguousarray(array[shift:ol_l+shift, shift:ol_d+shift, :])
        recvbuf = np.zeros((ol_r, ol_u, nz), dtype="float64")
        dest = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_down == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1]-1, self.coord3d[2]])
        source = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_up == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1]+1, self.coord3d[2]])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
            )
        fields_wol[nx+ol_l:, ny+ol_d:, ol_b:nz+ol_b] = recvbuf

        # left back --> right front (comm 11) (xz-2D)
        sendbuf = np.ascontiguousarray(array[nx-ol_r-shift:-shift, :, nz-ol_f-shift:-shift])
        recvbuf = np.zeros((ol_l, ny, ol_b), dtype="float64")
        dest = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_front == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1], self.coord3d[2]+1])
        source = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_back == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1], self.coord3d[2]-1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
        )
        fields_wol[:ol_l, ol_d:ny+ol_d, :ol_b] = recvbuf

        # left front --> right back (comm 12) (xz-2D)
        sendbuf = np.ascontiguousarray(array[nx-ol_r-shift:-shift, :, shift:ol_b+shift])
        recvbuf = np.zeros((ol_l, ny, ol_f), dtype="float64")
        dest = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_back == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1], self.coord3d[2]-1])
        source = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_front == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1], self.coord3d[2]+1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
            )
        fields_wol[:ol_l, ol_d:ny+ol_d, nz+ol_b:] = recvbuf

        # right back --> left front (comm 13) (xz-2D)
        sendbuf = np.ascontiguousarray(array[shift:ol_l+shift, :, nz-ol_f-shift:-shift])
        recvbuf = np.zeros((ol_r, ny, ol_b), dtype="float64")
        dest = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_front == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1], self.coord3d[2]+1])
        source = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_back == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1], self.coord3d[2]-1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
            )
        fields_wol[nx+ol_l:, ol_d:ny+ol_d, :ol_b] = recvbuf

        # right front --> left back (comm 14) (xz-2D)
        sendbuf = np.ascontiguousarray(array[shift:ol_l+shift, :, shift:ol_b+shift])
        recvbuf = np.zeros((ol_r, ny, ol_f), dtype="float64")
        dest = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_back == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1], self.coord3d[2]-1])
        source = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_front == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1], self.coord3d[2]+1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
            )
        fields_wol[nx+ol_l:, ol_d:ny+ol_d, nz+ol_b:] = recvbuf

        # down back --> up front (comm 15) (yz-2D)
        sendbuf = np.ascontiguousarray(array[:, ny-ol_u-shift:-shift, nz-ol_f-shift:-shift])
        recvbuf = np.zeros((nx, ol_d, ol_b), dtype="float64")
        dest = procnull if (self.proc_neighb_up == procnull or self.proc_neighb_front == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0], self.coord3d[1]+1, self.coord3d[2]+1])
        source = procnull if (self.proc_neighb_down == procnull or self.proc_neighb_back == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0], self.coord3d[1]-1, self.coord3d[2]-1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
        )
        fields_wol[ol_l:nx+ol_l, :ol_d, :ol_b] = recvbuf

        # down front --> up back (comm 16) (yz-2D)
        sendbuf = np.ascontiguousarray(array[:, ny-ol_u-shift:-shift, shift:ol_b+shift])
        recvbuf = np.zeros((nx  , ol_d, ol_f), dtype="float64")
        dest = procnull if (self.proc_neighb_up == procnull or self.proc_neighb_back == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0], self.coord3d[1]+1, self.coord3d[2]-1])
        source = procnull if (self.proc_neighb_down == procnull or self.proc_neighb_front == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0], self.coord3d[1]-1, self.coord3d[2]+1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
            )
        fields_wol[ol_l:nx+ol_l, :ol_d, nz+ol_b:] = recvbuf

        # up back --> down front (comm 17) (yz-2D)
        sendbuf = np.ascontiguousarray(array[:, shift:ol_d+shift, nz-ol_f-shift:-shift])
        recvbuf = np.zeros((nx, ol_u, ol_b), dtype="float64")
        dest = procnull if (self.proc_neighb_down == procnull or self.proc_neighb_front == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0], self.coord3d[1]-1, self.coord3d[2]+1])
        source = procnull if (self.proc_neighb_up == procnull or self.proc_neighb_back == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0], self.coord3d[1]+1, self.coord3d[2]-1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
            )
        fields_wol[ol_l:nx+ol_l, ny+ol_d:, :ol_b] = recvbuf

        # up front --> up back (comm 18) (yz-2D)
        sendbuf = np.ascontiguousarray(array[:, shift:ol_d+shift, shift:ol_b+shift])
        recvbuf = np.zeros((nx, ol_u, ol_f), dtype="float64")
        dest = procnull if (self.proc_neighb_down == procnull or self.proc_neighb_back == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0], self.coord3d[1]-1, self.coord3d[2]-1])
        source = procnull if (self.proc_neighb_up == procnull or self.proc_neighb_front == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0], self.coord3d[1]+1, self.coord3d[2]+1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
            )
        fields_wol[ol_l:nx+ol_l, ny+ol_d:, nz+ol_b:] = recvbuf

        # left down back --> right up front (comm 19) (xyz-3D)
        sendbuf = np.ascontiguousarray(array[nx-ol_r-shift:-shift, ny-ol_u-shift:-shift, nz-ol_f-shift:-shift])
        recvbuf = np.zeros((ol_l, ol_d, ol_b), dtype="float64")
        dest = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_up == procnull or self.proc_neighb_front == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1]+1, self.coord3d[2]+1])
        source = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_down == procnull or self.proc_neighb_back) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1]-1, self.coord3d[2]-1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
        )
        fields_wol[:ol_l, :ol_d, :ol_b] = recvbuf

        # left down front --> right up back (comm 20) (xyz-3D)
        sendbuf = np.ascontiguousarray(array[nx-ol_r-shift:-shift, ny-ol_u-shift:-shift, shift:ol_b+shift])
        recvbuf = np.zeros((ol_l, ol_d, ol_f), dtype="float64")
        dest = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_up == procnull or self.proc_neighb_back == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1]+1, self.coord3d[2]-1])
        source = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_down == procnull or self.proc_neighb_front) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1]-1, self.coord3d[2]+1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
        )
        fields_wol[:ol_l, :ol_d, nz+ol_b:] = recvbuf

        # left up back --> right down front (comm 21) (xyz-3D)
        sendbuf = np.ascontiguousarray(array[nx-ol_r-shift:-shift, shift:ol_d+shift, nz-ol_f-shift:-shift])
        recvbuf = np.zeros((ol_l, ol_u, ol_b), dtype="float64")
        dest = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_down == procnull or self.proc_neighb_front == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1]-1, self.coord3d[2]+1])
        source = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_up == procnull or self.proc_neighb_back) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1]+1, self.coord3d[2]-1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
        )
        fields_wol[:ol_l, ny+ol_d:, :ol_b] = recvbuf

        # left up front --> right up back (comm 22) (xyz-3D)
        sendbuf = np.ascontiguousarray(array[nx-ol_r-shift:-shift, shift:ol_d+shift, shift:ol_b+shift])
        recvbuf = np.zeros((ol_l, ol_u, ol_f), dtype="float64")
        dest = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_down == procnull or self.proc_neighb_back == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1]-1, self.coord3d[2]-1])
        source = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_up == procnull or self.proc_neighb_front) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1]+1, self.coord3d[2]+1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
        )
        fields_wol[:ol_l, ny+ol_d:, nz+ol_b:] = recvbuf

        # right down back --> left up front (comm 23) (xyz-3D)
        sendbuf = np.ascontiguousarray(array[shift:ol_l+shift, ny-ol_u-shift:-shift, nz-ol_f-shift:-shift])
        recvbuf = np.zeros((ol_r, ol_d, ol_b), dtype="float64")
        dest = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_up == procnull or self.proc_neighb_front == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1]+1, self.coord3d[2]+1])
        source = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_down == procnull or self.proc_neighb_back) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1]-1, self.coord3d[2]-1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
        )
        fields_wol[nx+ol_l:, :ol_d, :ol_b] = recvbuf

        # right down front --> left up back (comm 24) (xyz-3D)
        sendbuf = np.ascontiguousarray(array[shift:ol_l+shift, ny-ol_u-shift:-shift, shift:ol_b+shift])
        recvbuf = np.zeros((ol_r, ol_d, ol_f), dtype="float64")
        dest = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_up == procnull or self.proc_neighb_back == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1]+1, self.coord3d[2]-1])
        source = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_down == procnull or self.proc_neighb_front) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1]-1, self.coord3d[2]+1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
        )
        fields_wol[nx+ol_l:, :ol_d, nz+ol_b:] = recvbuf

        # right up back --> left down front (comm 25) (xyz-3D)
        sendbuf = np.ascontiguousarray(array[shift:ol_l+shift, shift:ol_d+shift, nz-ol_f-shift:-shift])
        recvbuf = np.zeros((ol_r, ol_u, ol_b), dtype="float64")
        dest = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_down == procnull or self.proc_neighb_front == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1]-1, self.coord3d[2]+1])
        source = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_up == procnull or self.proc_neighb_back) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1]+1, self.coord3d[2]-1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
        )
        fields_wol[nx+ol_l:, ny+ol_d:, :ol_b] = recvbuf

        # right up front --> left up back (comm 26) (xyz-3D)
        sendbuf = np.ascontiguousarray(array[shift:ol_l+shift, shift:ol_d+shift, shift:ol_b+shift])
        recvbuf = np.zeros((ol_r, ol_u, ol_f), dtype="float64")
        dest = procnull if (self.proc_neighb_left == procnull or self.proc_neighb_down == procnull or self.proc_neighb_back == procnull) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]-1, self.coord3d[1]-1, self.coord3d[2]-1])
        source = procnull if (self.proc_neighb_right == procnull or self.proc_neighb_up == procnull or self.proc_neighb_front) \
            else self.cartesian3d.Get_cart_rank([self.coord3d[0]+1, self.coord3d[1]+1, self.coord3d[2]+1])
        tag += 1
        self.cartesian3d.Sendrecv(
            sendbuf=sendbuf, dest=dest, sendtag=tag,
            recvbuf=recvbuf, source=source, recvtag=tag,
        )
        fields_wol[nx+ol_l:, ny+ol_d:, nz+ol_b:] = recvbuf

        return np.asfortranarray(fields_wol)


    def get_fields_without_overlap(self, array):
        """
        Get back fields without overlap
        """
        if not self.with_overlap:
            return array

        return  array[
                    self.ol_x_n_elmts_left: self.nx+self.ol_x_n_elmts_left,
                    self.ol_y_n_elmts_down: self.ny+self.ol_y_n_elmts_down,
                    self.ol_z_n_elmts_back: self.nz+self.ol_z_n_elmts_back
                    ]


    @staticmethod
    def recursive_coordinate_bisection(coords, nblocks):
        """
        Split coords into nblocks coor should be of shape: ((imin, imax),
                                                           (jmin, jmax),
                                                           (kmin, kmax),)
        """
        def _split_one(coor):
            """Split a single coordinate (min, max) in 2
            Favor the first half:
                (5, 7) becomes (5, 6), (6, 7)
                (5, 8) becomes (5, 7), (7, 8)
            """
            coor_min, coor_max = coor
            if coor_max - coor_min < 2:
                raise ValueError("Trying to bisect a direction with less than 3 nodes")
            middle = coor_min + ceil((coor_max - coor_min) / 2)
            return ((coor_min, middle), (middle, coor_max))

        def _split_bisect(coords):
            """
            Split coords in 2 along longest direction
            """
            sizes = [end - start for start, end in coords]
            longest_axis = sizes.index(max(sizes))
            icoor, jcoor, kcoor = coords
            if longest_axis == 0:
                left, right = _split_one(icoor)
                return ((left, jcoor, kcoor), (right, jcoor, kcoor)), [1,0,0]
            if longest_axis == 1:
                left, right = _split_one(jcoor)
                return ((icoor, left, kcoor), (icoor, right, kcoor)), [0,1,0]
            if longest_axis == 2:
                left, right = _split_one(kcoor)
                return ((icoor, jcoor, left), (icoor, jcoor, right)), [0,0,1]

        mpicart = [(0,0,0)]
        blocks = [coords]
        while len(blocks) < nblocks:
            sizes = [(imax - imin + 1) * (jmax - jmin + 1) * (kmax - kmin + 1) for ((imin, imax), (jmin, jmax), (kmin, kmax)) in blocks]
            largest = sizes.index(max(sizes))
            (left, right), mpicoord = _split_bisect(blocks[largest])
            if len(blocks) == 1:
                blocks = [left, right]
                mpicart.append(tuple(sum(i) for i in zip(mpicart[0], mpicoord)))
            else:
                blocks = blocks[:largest] + [left, right] + blocks[largest + 1:]
                newcoordmpi = [tuple(sum(i) for i in zip(mpicart[largest], mpicoord))]
                for i in range(3):
                    if mpicoord[i] == 1:
                        for j in range(len(mpicart)):
                            if mpicart[j][i] >= newcoordmpi[0][i] \
                                    and mpicart[j][(i+1)%3] == newcoordmpi[0][(i+1)%3] \
                                        and mpicart[j][(i+2)%3] == newcoordmpi[0][(i+2)%3]:
                                aslist = list(mpicart[j])
                                aslist[i] += 1
                                mpicart[j] = tuple(aslist)
                mpicart = mpicart[:largest+1] + [tuple(sum(i) for i in zip(mpicart[largest], mpicoord))] + mpicart[largest + 1:]

        ind = np.lexsort((np.array(mpicart)[:,1], np.array(mpicart)[:,0])).tolist()

        mpicart = np.array(mpicart)[ind].tolist()

        blocks_ord = []
        for i in range(len(blocks)):
            blocks_ord.append(blocks[ind[i]])

        return blocks_ord, mpicart
