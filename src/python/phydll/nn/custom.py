""" Copyright (c) CERFACS (all rights reserved)
@file       coupling_inference_custom.py
@details    Custom inference
@author     A. Serhani
"""
import os
import yaml
import numpy as np

class CustomInference:
    """
    Custom inference

    Args:
        env (object): MPI environment.
        io (tuple): Tuple of input and output objects.
    """

    def __init__(self):
        self.mpienv = None
        _, self.output = None, None
        self.mesh = None

        self.device = "cpu"
        self.model = None

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
        Read NN parameters from custom.yml
        """
        assert os.path.exists("./custom.yml"), \
                "Error custom.yml file not found in your run directory"

        with open("./custom.yml", "r", encoding="utf-8") as ymlfile:
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
        self.output.log_hl1(f"Pass", dblv=1)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.set_gpus = toc - tic
        self.output.log_hl0(timer=self.output.timers.set_gpus, dblv=0)


    def init_nn(self):
        """
        Init neural network
        """
        self.output.log_hl0("Init neural network model\n", dblv=0)

        dblv = 1

        modelfile = self.model_params["modelfile"]
        self.output.log_hl1(f"Load model ...", dblv)
        self.output.log_hl2(f"Model file: {modelfile}", dblv)

        tic = self.mpienv.MPI.Wtime()
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.init_nn += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)

        self.output.log_hl1("Create graph ...", dblv)
        tic = self.mpienv.MPI.Wtime()
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.init_nn += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)

        self.output.log_hl0(timer=self.output.timers.init_nn, dblv=0)


    def predict(self, avbp_fields):
        """
        DEBUG
        """
        tic = self.mpienv.MPI.Wtime()
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.pred["prep"] = toc - tic

        tic = self.mpienv.MPI.Wtime()
        import time
        time.sleep(1/self.mpienv.comm_size / 16)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.pred["run"] = toc - tic

        tic = self.mpienv.MPI.Wtime()
        array_0 = np.cos(2 * avbp_fields[0, :] - (avbp_fields[1, :] - 100)/100 - (avbp_fields[2, :] - 1000)/1000)**2
        array_1 = np.sin(2 * abs(avbp_fields[0, :]) + 1)  / (1 + abs((avbp_fields[1, :] - 100)/100 - (avbp_fields[2, :] - 1000)/1000)) ** 2
        dl_fields = []
        dl_fields.extend((array_0, array_1))
        fields = np.array(dl_fields)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.pred["post"] = toc - tic

        self.output.timers.pred["full"] = sum(list(self.output.timers.pred.values())[:-1])

        return fields
        # return avbp_fields