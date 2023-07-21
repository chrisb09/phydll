""" Copyright (c) CERFACS (all rights reserved)
@file       coupling_inference_torch.py
@details    PyTorch inference for GNN
@author     A. Serhani
"""
import os
import pickle
import itertools
import yaml
import torch
import torch_geometric as pyg
import numpy as np

class GraphNeuralNetPyg:
    """
    PyTorch inference

    Args:
        env (object): MPI environment.
        io (tuple): Tuple of input and output objects.
    """

    def __init__(self):
        self.mpienv = None
        _, self.output = None, None
        self.mesh = None

        self.cuda_device = "cpu"
        self.model = None
        self.edges = torch.tensor(0, dtype=torch.long)
        self.nvertex = 0
        self.np_edges = np.array([], dtype="int32")

        self.model_params = {}
        self.gpu_params = {}


    def initialize(self, env, io, mesh):
        """"
        Intialize PyTorch Geometric GNN object
        """
        self.mpienv = env
        _, self.output = io
        self.mesh = mesh

        self.read_nn_params()
        self.use_gpu = self.gpu_params["use_gpu"]
        self.custom_ids = self.gpu_params["custom_ids"]

        self.set_gpus()
        self.init_nn()


    def read_nn_params(self):
        """
        Read NN parameters from gnnpyg.yml
        """
        assert os.path.exists("./gnnpyg.yml"), \
                "Error gnnpyg.yml file not found in your run directory"

        with open("./gnnpyg.yml", "r", encoding="utf-8") as ymlfile:
            params = yaml.safe_load(ymlfile)

        # Init model params
        self.model_params["modelfile"] = ""
        self.model_params.update(params["Model"])

        # Init GPU params
        self.gpu_params["use_gpu"] = True
        self.gpu_params["custom_ids"] = False
        try: self.gpu_params.update(params["GPU"])
        except KeyError: pass


    def set_gpus(self):
        """
        Set gpu placements
        """
        self.output.log_hl0("GPUs setting\n", dblv=0)
        tic = self.mpienv.MPI.Wtime()
        dblv = 1
        gpuspernode = 0
        if torch.cuda.is_available() and self.use_gpu:
            gpuspernode = torch.cuda.device_count()
            if self.custom_ids:
                ids = self.gpu_params["ids_per_node"]
                GPUID = ids[self.mpienv.comm_rank % len(ids)]
            else :
                GPUID = self.mpienv.comm_rank % gpuspernode
            self.cuda_device = f"cuda:{GPUID}"
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.set_gpus = toc - tic

        if torch.cuda.is_available():
            self.output.log_hl1(f"Use GPU = {self.use_gpu}", dblv)

        if gpuspernode > 0:
            self.output.log_hl1(f"GPUs per node = {gpuspernode}", dblv)
            self.output.log_hl1("{:<15} {:<20} {:<15}".format("MPI rank", "Local GPUID", "Node"), dblv)
            self.output.log_hl1("{:<15} {:<20} {:<15}".format(self.mpienv.comm_rank, GPUID, self.mpienv.MPI.Get_processor_name()), dblv, allmpi=True)
        else:
            self.output.log_hl1("GPU not found/used -> Using CPU for NN inference", dblv)
        self.output.log_hl0(timer=self.output.timers.set_gpus, dblv=0)


    def init_nn(self):
        """
        Init neural network
        """
        self.output.log_hl0("Init neural network model\n", dblv=0)

        dblv = 1
        self.output.log_hl1(f"PyTorch = {torch.__version__}", dblv)
        self.output.log_hl1(f"PyTorch Geometric = {pyg.__version__}", dblv)

        modelfile = self.model_params["modelfile"]
        self.output.log_hl1(f"Load model ...", dblv)
        self.output.log_hl2(f"Model file: {modelfile}", dblv)
        tic = self.mpienv.MPI.Wtime()
        self.model = torch.load(modelfile, map_location=self.cuda_device)
        self.model.eval()
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.init_nn += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)

        # Create graph
        dblv = 2
        self.output.log_hl1("Create graph edges ...", dblv)
        self.edges_list = self._create_graph_edges()

        self.output.log_hl1("Create torch graph ...", dblv)
        tic = self.mpienv.MPI.Wtime()
        self.edges = torch.tensor(self.edges_list, dtype=torch.long).T - 1
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.init_nn += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)

        self.output.log_hl0(timer=self.output.timers.init_nn, dblv=0)


    def _create_graph_edges(self):
        """
        Create the graph edeges from connectivity table
        """
        try:
            edges_list_file = f"{self.mesh.phydll_mesh_rep}/edges_list-{self.mesh.global_nvertex}-{self.mesh.connec.shape[0]}-{self.mpienv.comm_size}-{self.mpienv.comm_rank}.pkl"
        except AttributeError:
            edges_list_file = f"./voxgrid_edges_list_{self.mesh.connec.shape[0]}-{self.mpienv.comm_size}-{self.mpienv.comm_rank}"
        edges_list_file_exists = os.path.exists(edges_list_file)

        dblv = 2
        if edges_list_file_exists:
            self.output.log_hl2("File exists! Load it ...", dblv)
            tic = self.mpienv.MPI.Wtime()
            with open(edges_list_file, "rb") as ed_l_f:
                edges_list = pickle.load(ed_l_f)
            toc = self.mpienv.MPI.Wtime()
            self.output.timers.init_nn += toc - tic
            self.output.log_hl2(timer=(toc-tic), dblv=dblv)

        else:
            self.output.log_hl2("Create ...", dblv)
            tic = self.mpienv.MPI.Wtime()
            edges = [list(itertools.permutations(self.mesh.connec_r[i, :], 2)) for i in range(self.mesh.nelmt)]
            flat_list = self.mesh._flatten_list(edges)
            edges_list = list(set(flat_list))
            toc = self.mpienv.MPI.Wtime()
            self.output.timers.init_nn += toc - tic
            self.output.log_hl2(timer=(toc-tic), dblv=dblv)

            self.output.log_hl2("Save ...", dblv)
            tic = self.mpienv.MPI.Wtime()
            with open(edges_list_file, "wb") as ed_l_f:
                pickle.dump(edges_list, ed_l_f)
            toc = self.mpienv.MPI.Wtime()
            self.output.timers.init_nn += toc - tic
            self.output.log_hl2(timer=(toc-tic), dblv=dblv)

        return edges_list


    def predict(self, avbp_fields):
        """
        Prediction
        """
        tic = self.mpienv.MPI.Wtime()
        avbp_fields = avbp_fields[0, :]
        data = pyg.data.Data(x=torch.tensor(avbp_fields[:, np.newaxis], dtype=torch.float), edge_index=self.edges)
        gcn = pyg.data.Batch().from_data_list(data_list=[data])
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.pred["prep"] = toc - tic

        tic = self.mpienv.MPI.Wtime()
        with torch.no_grad():
            gcn.to(self.cuda_device)
            output = self.model(gcn.x, gcn.edge_index)
        toc = self.mpienv.MPI.Wtime()

        self.output.timers.pred["run"] = toc - tic

        tic = self.mpienv.MPI.Wtime()
        dl_fields = output.cpu().detach().numpy().reshape(self.mesh.nvertex, order='F').astype(np.float64)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.pred["post"] = toc - tic

        self.output.timers.pred["full"] = sum(list(self.output.timers.pred.values())[:-1])

        return dl_fields
