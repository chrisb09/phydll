""" Copyright (c) CERFACS (all rights reserved)
@file       io.py
@details    PhyDLL's parallel input/output module
@authors    A. Serhani, C. Lapeyre, G. Staffelbach
@email      phydll@cerfacs.fr
"""
import os
import h5py
import yaml
import numpy as np
from datetime import datetime


class Input:
    """
    Create object to read input parameters

    Args:
        mpienv  (object)    MPI environment

    Attributes:
        coupling_params (dic)   Coupling parameters.
        cwipi_params    (dic)   CWIPI parameters.
        output_params   (dic)   Output parameters.
        python_mesh     (dic)   Python mesh.
        run_params      (dic)   Run parameters (run.params).
        meshfile        (char)  Meshfile path
    """

    def __init__(self, env):
        """
        Init Input class
        """
        self.mpienv = env

        self.python_mesh = {}
        self.output_params = {}
        self.coupling_params = {}
        self.run_params = {}
        self.cwipi_params = {}

        self.meshfile = ""

        self.read_config()


    def read_config(self):
        """
        Read PhyDLL config parameters from phydll.yaml
        """
        assert os.path.exists("./phydll.yml"), \
                "Error phydll.yml file not found in your run directory"

        params = {}
        params["Output"] = {}
        params["Coupling"] = {}
        params["DLmesh"] = {}
        with open("./phydll.yml", "r", encoding="utf-8") as ymlfile:
            params.update(yaml.safe_load(ymlfile))

        # Init output params
        self.output_params["logfile"] = "./phydll.log"
        self.output_params["logfile_jid"] = True
        self.output_params["debug_level"] = 2
        self.output_params.update(params["Output"])

        # Init coupling params
        self.coupling_params["save_fields_frequency"] = 0
        self.coupling_params["coupling_frequency"] = 1
        self.coupling_params.update(params["Coupling"])

        # Init mesh params
        self.python_mesh["overlap"] = {}
        self.python_mesh["overlap"]["overlap"] = False
        self.python_mesh.update(params["DLmesh"])


class Output:
    """
    Manage coupling outputs/logging

    Args:
        env (object)    MPI environment.
        inp (object)    inputs object.

    Attributes:
        mpienv      (object)    MPI environment
        input       (object)    Input object
        timers      (object)    Timers object
        loglines    (list)      Log lines
        fields_dir  (char)  Outputted fields directory
    """
    def __init__(self, env, inp):
        """
        Init Output class
        """
        self.mpienv = env
        self.input = inp
        self.timers = Timers(env=self.mpienv)

        self.loglines = []
        self.logfile = self.input.output_params["logfile"]
        if self.input.output_params["logfile_jid"]:
            if self.input.output_params["logfile"] == "./phydll.log":
                self.logfile = f"./phydll-{os.environ.get('SLURM_JOB_ID')}.log"
            else:
                self.logfile += "." + os.environ.get('SLURM_JOB_ID')

        self.dblv = self.input.output_params["debug_level"]
        self.hl0 = "(PhyDLL) ----> "
        self.indent = 4
        self.checkmark = "\u2713"

        self.fields_dir = "./PhyDLL_FIELDS"

        jobid = os.environ.get("SLURM_JOB_ID")
        jobidstr = "" if jobid is None else jobid

        if self.mpienv.is_commhrank:
            with open(self.logfile, "w", encoding="utf-8") as file:
                file.write(datetime.now().strftime("%d/%m/%Y - %H:%M:%S") + f"\t JOBID={jobidstr}")

        self.xdmf_collec = f"""<?xml version="1.0" ?>
<!DOCTYPE Xdmf SYSTEM "Xdmf.dtd" []>
<Xdmf xmlns:xi="http://www.w3.org/2001/XInclude" Version="2.0">
    <Domain>
        <Grid Name="phydll_fields" GridType="Collection" CollectionType="Temporal">
        </Grid>
    </Domain>
</Xdmf>"""
        self.xdmf_collec_phy = f"{self.xdmf_collec}"

        self.create_logfile()


    def log(self, message):
        """
        Master process writes into logfile
        """
        if self.mpienv.is_commhrank:
            self.loglines.append(message)
            self.loglines.append('\n')
        self._dumplog()


    def logall(self, message):
        """
        All process write into logfile
        """
        self.mpienv.comm.Barrier()
        self.loglines.append(message)
        self.loglines.append('\n')
        self._dumplog()
        self.mpienv.comm.Barrier()


    def _dumplog(self):
        """ Dump log file """
        if self.loglines is not None:
            with open(self.logfile, 'a', encoding="utf-8") as logfile:
                logfile.writelines(self.loglines)
        self.loglines = []


    def make_saves_dirs(self):
        """
        Create directory for coupling timers and fields
        """
        save_fields_frequency = self.input.coupling_params["save_fields_frequency"]
        if save_fields_frequency > 0 and self.mpienv.is_commhrank:
            if not os.path.isdir(self.fields_dir):
                os.makedirs(self.fields_dir)
            if not os.path.isdir(f"{self.fields_dir}/FILES"):
                os.makedirs(f"{self.fields_dir}/FILES")


    def create_logfile(self):
        """
        Create logfiles
        """
        self.make_saves_dirs()

        self.log(r"""
 _______________________________________
|    _____         ____  __    __       |
|   |  __ \       | __ \ | |   | |      |
|   | |__) |      | | \ \| |   | |      |
|   |  ___/|      | |  | | |   | |      |
|   | |    |__\  /| |_/ /| |__ | |__    |
|   |_|    |  |\/ |____/ |____||____|   |
|              /                        |
|             /                         |
|  << Physics Deep Learning coupLer >>  |
|  phydll@cerfacs.fr       CERFACS(C)   |
|_______________________________________|
          """)
        self.log(f"Distant MPI communicator (Phy) = {self.mpienv.dsize}")
        self.log(f"Local MPI communicator (DL) = {self.mpienv.comm_size}")

    def log_db(self, message, allmpi=False):
        """
        Log debugging message
        """
        if not allmpi:
            self.log(r"/!\ /!\ /!\ " + message + "\n")
        else:
            self.logall(r"/!\ /!\ /!\ " + f"g_rk={self.mpienv.glcomm_rank}, l_rk={self.mpienv.comm_rank}\t" + message)
            self.log("\n")


    def log_hl0(self, message=None, dblv=0, timer=None):
        """
        Log 1st header level message
        """
        if dblv <= self.dblv:
            if timer is None:
                self.log("\n")
                self.log(self.hl0 + message)
            else:
                self.log(f"{4*self.checkmark} {self.timers.rd_timer(timer):8.6f} s")
            self._dumplog()


    def log_hl1(self, message=None, dblv=1, timer=None, allmpi=False):
        """
        Log 2nd header level message
        """
        indent = (len(self.hl0)+self.indent) * " "
        if dblv <= self.dblv:
            if allmpi:
                self.logall(indent + message)
            else:
                if timer is None:
                    self.log(indent + message)
                else:
                    self.log(indent + f"{self.checkmark} {self.timers.rd_timer(timer):8.6f} s\n")
            self._dumplog()


    def log_hl2(self, message=None, dblv=2, timer=None, allmpi=False):
        """
        Log 3rd header level message
        """
        indent = (len(self.hl0)+self.indent*2) * " "
        if dblv <= self.dblv:
            if allmpi:
                self.logall(indent + message)
            else:
                if timer is None:
                    self.log(indent + message)
                else:
                    self.log(indent  + f"{self.checkmark} {self.timers.rd_timer(timer):8.6f} s\n")
            self._dumplog()


    def log_hl3(self, message=None, dblv=3, timer=None, allmpi=False):
        """
        Log 4th header level message
        """
        indent = (len(self.hl0)+self.indent*3) * " "
        if dblv <= self.dblv:
            if allmpi:
                self.logall(indent + message)
            else:
                if timer is None:
                    self.log(indent + message)
                else:
                    self.log(indent  + f"{self.checkmark} {self.timers.rd_timer(timer):8.6f} s\n")
            self._dumplog()


    def dump_temporal_table(self, msizes, fform="%8.6f s"):
        """
        Dump timers of temporal routines
        """
        self.timers.temporal_ite += self.timers.recv["full"]
        self.timers.temporal_ite += self.timers.pred["full"]
        self.timers.temporal_ite += self.timers.send["full"]

        ff = lambda x: fform % x
        rd = self.timers.rd_timer
        mpirk = self.mpienv.comm_rank

        recv = self.timers.recv
        pred = self.timers.pred
        send = self.timers.send

        dblv = 2
        self.log_hl2(" ", dblv=dblv)

        if self.dblv == 2:
            dblv = self.dblv
            self.log_hl2(f"{'recv':<10} {'predict':<15} {'send':<15}", dblv=dblv)
            if self.mpienv.comm_size > 1:
                self.log_hl2(f"{ff(rd(recv['full'])):<10} {ff(rd(pred['full'])):<15} {ff(rd(send['full'])):<15}", dblv=dblv)

        if self.dblv == 3:
            dblv = self.dblv
            self.log_hl2(f"{'MPI_rank':<10} {'recv':<15} {'predict':<15} {'send':<15}", dblv=dblv)
            self.log_hl2(f"{mpirk:<10} {ff(recv['full']):<15} {ff(pred['full']):<15} {ff(send['full']):<15}", dblv=dblv, allmpi=True)
            if self.mpienv.comm_size > 1:
                self.log_hl2(f"{'rd_max':<10} {ff(rd(recv['full'])):<15} {ff(rd(pred['full'])):<15} {ff(rd(send['full'])):<15}", dblv=dblv)

        if self.dblv >= 4:
            dblv = self.dblv
            mess1 = "{:<10} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15}".format \
                ("MPI_rank", "recv_size", "recv_comm", "recv_wait", "recv_post", "pred_prep", "pred", "pred_post", "send_prep", "send_comm", "send_wait", "send_size")
            self.log_hl2(mess1, dblv=dblv)

            mess2 = "{:<10} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15}".format \
                (mpirk, f"{msizes[0]:8.3f} MB".strip(), ff(recv['comm']), ff(recv['wait']), ff(recv['post']), ff(pred['prep']), ff(pred['run']), ff(pred['post']), ff(send['prep']), ff(send['comm']), ff(send['wait']), f"{msizes[1]:8.3f} MB".strip())
            self.log_hl2(mess2, dblv=dblv, allmpi=True)

            if self.mpienv.comm_size > 1:
                mess3 = "{:<10} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15} {:<15}".format \
                ("rd_max", f"{rd(msizes[0]):8.3f} MB".strip(), ff(rd(recv['comm'])), ff(rd(recv['wait'])), ff(rd(recv['post'])), ff(rd(pred['prep'])), ff(rd(pred['run'])), ff(rd(pred['post'])), ff(rd(send['prep'])), ff(rd(send['comm'])), ff(rd(send['wait'])), f"{rd(msizes[1]):8.3f} MB".strip())
                self.log_hl2(mess3, dblv=dblv)

        dblv = 2
        self.log_hl2(" ", dblv=dblv)



    # def print_fields_dir(self):
    #     if self.input.coupling_params["save_fields_frequency"] > 0:
    #         self.log_hl1(f"Fields saved in {self.output.fields_dir}, Visualization: {self.output.fields_dir}/phydll_dl_fields.xmf", dblv=3)


    def save_fields(self, phy_fields, dl_fields, mesh, phy_nfields, dl_nfields, cpl_ite):
        """"
        Save local mesh and exchanged fields
        """
        self.log_hl2("Save fields ...", dblv=3)
        self.save_hdf5_files(phy_fields, dl_fields, mesh, phy_nfields, dl_nfields, cpl_ite)
        self.write_xdmf_files(mesh, phy_nfields, dl_nfields, cpl_ite)
        self.write_xdmf_collec_file(cpl_ite)


    def save_hdf5_files(self, phy_fields, dl_fields, mesh, phy_nfields, dl_nfields, cpl_ite):
        """
        Save hdf5 files
        """
        meshfile = f"{self.fields_dir}/FILES/fields_dl_{cpl_ite}_{self.mpienv.comm_rank}-{self.mpienv.comm_size-1}.h5"
        with h5py.File(meshfile, "w") as file:
            file["connec"] = mesh.connec
            file["x"] = mesh.coords[::mesh.dim]
            file["y"] = mesh.coords[1::mesh.dim]
            if mesh.dim == 3: file["z"] = mesh.coords[2::mesh.dim]
            file["mpi_rank"] = int(self.mpienv.comm_rank) * np.ones(mesh.nvertex, dtype="int")

            for i in range(phy_nfields):
                file[f"phy_fields_{i}"] = phy_fields[i, :]

            dl_fields = dl_fields.reshape((dl_nfields, mesh.nvertex))
            for i in range(dl_nfields):
                file[f"dl_fields_{i}"] = dl_fields[i, :]


    def write_xdmf_files(self, mesh, phy_nfields, dl_nfields, cpl_ite):
        """
        Write xdmf files
        """
        geometry_type = "X_Y"
        if mesh.dim == 3: geometry_type += "_Z"

        worder = '>'
        if mesh.topo_type == "Wedge": worder = ' Order="0 5 3 1 4 2">'

        xdmf = f"""<?xml version="1.0" ?>
<!DOCTYPE Xdmf SYSTEM "Xdmf.dtd" []>
<Xdmf Version="2.0" xmlns:xi="http://www.w3.org/2001/XInclude">
    <Domain>
        <Grid Collection="PhyDLL" Name="exch_fields_dl">
            <Time Value="{cpl_ite}" />
            <Topology Type="{mesh.topo_type}" NumberOfElements="{mesh.nelmt}"{worder}
                <DataItem ItemType="Function" Dimensions="{mesh.connec.shape[0]}" Function="$0 - 1">
                    <DataItem Format="HDF" DataType="Int" Dimensions="{mesh.connec.shape[0]}">
                        ./FILES/fields_dl_{cpl_ite}_{self.mpienv.comm_rank}-{self.mpienv.comm_size-1}.h5:/connec
                    </DataItem>
                </DataItem>
            </Topology>
            <Geometry Type="{geometry_type}">
                <DataItem Format="HDF" ItemType="Uniform" Precision="8" NumberType="Float" Dimensions="{mesh.nvertex}">
                    ./FILES/fields_dl_{cpl_ite}_{self.mpienv.comm_rank}-{self.mpienv.comm_size-1}.h5:/x
                </DataItem>
                <DataItem Format="HDF" ItemType="Uniform" Precision="8" NumberType="Float" Dimensions="{mesh.nvertex}">
                    ./FILES/fields_dl_{cpl_ite}_{self.mpienv.comm_rank}-{self.mpienv.comm_size-1}.h5:/y
                </DataItem>"""
        if mesh.dim == 3:
            xdmf += f"""
                <DataItem Format="HDF" ItemType="Uniform" Precision="8" NumberType="Float" Dimensions="{mesh.nvertex}">
                    ./FILES/fields_dl_{cpl_ite}_{self.mpienv.comm_rank}-{self.mpienv.comm_size-1}.h5:/z
                </DataItem>"""
        xdmf += f"""
            </Geometry>
            <Attribute Name="mpi_rank" Center="Node" AttributeType="Scalar">
                <DataItem Format="HDF" DataType="Int" Dimensions="{mesh.nvertex}">
                    ./FILES/fields_dl_{cpl_ite}_{self.mpienv.comm_rank}-{self.mpienv.comm_size-1}.h5:/mpi_rank
                </DataItem>
            </Attribute>"""

        for i in range(phy_nfields):
            xdmf += f"""
            <Attribute Name="phy_fields_{i}" Center="Node" AttributeType="Scalar">
                <DataItem Format="HDF" ItemType="Uniform" Precision="8" NumberType="Float" Dimensions="{mesh.nvertex}">
                    ./FILES/fields_dl_{cpl_ite}_{self.mpienv.comm_rank}-{self.mpienv.comm_size-1}.h5:/phy_fields_{i}
                </DataItem>
            </Attribute>"""

        for i in range(dl_nfields):
            xdmf += f"""
            <Attribute Name="dl_fields_{i}" Center="Node" AttributeType="Scalar">
                <DataItem Format="HDF" ItemType="Uniform" Precision="8" NumberType="Float" Dimensions="{mesh.nvertex}">
                    ./FILES/fields_dl_{cpl_ite}_{self.mpienv.comm_rank}-{self.mpienv.comm_size-1}.h5:/dl_fields_{i}
                </DataItem>
            </Attribute>"""

        xdmf += """</Grid>
    </Domain>
</Xdmf>"""
        xdmf_file = f"{self.fields_dir}/FILES/fields_dl_{cpl_ite}_{self.mpienv.comm_rank}-{self.mpienv.comm_size-1}.xmf"
        with open(xdmf_file, "w") as file:
            file.write(xdmf)


    def write_xdmf_collec_file(self, cpl_ite):
        """
        Write xdmf collection file (DL)
        """
        if self.mpienv.is_commhrank:
            # DL XDMF COLLEC
            fields_file = f"{self.fields_dir}/phydll_dl_fields.xmf"
            self.xdmf_collec = self.xdmf_collec[:-38] + f"""
            <Grid Name="./phydll_dl_fields_{cpl_ite}" GridType="Collection" CollectionType="Spatial">"""
            for i in range(self.mpienv.comm_size):
                self.xdmf_collec += f"""
                <xi:include href="./FILES/fields_dl_{cpl_ite}_{i}-{self.mpienv.comm_size-1}.xmf" xpointer="xpointer(//Xdmf/Domain/Grid)"/>"""
            self.xdmf_collec += """
            </Grid>"""
            self.xdmf_collec += """
        </Grid>
    </Domain>
</Xdmf>"""
            with open(fields_file, "w") as file:
                file.write(self.xdmf_collec)

            # PHY XDMF COLLEC
            fields_file = f"{self.fields_dir}/phydll_phy_fields.xmf"
            self.xdmf_collec_phy = self.xdmf_collec_phy[:-38] + f"""
            <Grid Name="./phydll_phy_fields_{cpl_ite}" GridType="Collection" CollectionType="Spatial">"""
            for i in range(self.mpienv.dsize):
                self.xdmf_collec_phy += f"""
                <xi:include href="./FILES/fields_phy_{cpl_ite}_{i}-{self.mpienv.dsize-1}.xmf" xpointer="xpointer(//Xdmf/Domain/Grid)"/>"""
            self.xdmf_collec_phy += """
            </Grid>"""
            self.xdmf_collec_phy += """
        </Grid>
    </Domain>
</Xdmf>"""
            with open(fields_file, "w") as file:
                file.write(self.xdmf_collec_phy)
class Timers:
    """
    Coupling timers

    Args:
        env     (object)    MPI environment

    Attributes:
        create_cpl      (float)     Create coupling timer
        create_mesh     (float)     Create mesh timer
        set_mesh        (float)     Set mesh, for coupling, timer
        set_gpus        (float)     Set gpus timer
        init_nn         (float)     Init neural network timer
        temporal_ite    (float)     Temporal iteration timer
        temporal        (float)     Temporal loop timer
        recv            (dic)       Recv routines timer: comm, wait, postproc, full op
        send            (dic)       Send routines timer: comm, wait, preproc, full op
        pred            (dic)       Prediction routines timer: run, preproc, postproc, full op
        table           (np.array)
        table_cpl_timers(np.array)
    """
    def __init__(self, env):
        """
        Init Timers class
        """
        self.mpienv = env

        self.create_cpl = 0.0
        self.create_mesh = 0.0
        self.set_mesh = 0.0
        self.set_gpus = 0.0
        self.init_nn  = 0.0

        self.temporal_ite = 0.0
        self.temporal = 0.0

        self.recv = {"comm": 0.0, "wait": 0.0, "post": 0.0, "full": 0.0}
        self.send = {"comm": 0.0, "wait": 0.0, "prep": 0.0, "full": 0.0}
        self.pred = {"run": 0.0, "prep": 0.0, "post": 0.0, "full": 0.0}

        self.table = np.array([], dtype="float64")
        self.table_cpl_timers = np.array([], dtype="float64")


    def rd_timer(self, timer: float) -> float:
        """
        Reduce timers to master process with max op
        """
        return self.mpienv.comm.allreduce(np.array([timer]), op=self.mpienv.MPI.MAX)[0]
