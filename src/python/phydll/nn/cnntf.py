""" Copyright (c) CERFACS (all rights reserved)
@file       coupling_inference_tensorflow.py
@details    Tensorflow inference for CNN
@authors    A. Serhani, V. Xing
"""
import os
import subprocess
import yaml
import tensorflow as tf
import numpy as np
from scipy.interpolate import griddata
tfv = int(tf.__version__[0])
if tfv == 2:
    from tensorflow.keras.models import load_model
elif tfv == 1:
    from keras.models import load_model
    from keras.backend.tensorflow_backend import set_session


class ConvNeuralNetTF:
    """
    TensorFlow CNN inference

    Args:
        env     (object)    MPI environment
        io      (tuple)     Tuple of input and output objects
        mesh    (object)    Mesh object
        tfv     (int)       TensorFlow version

    Attributes:
        mpienv          (object)    MPI environment
        input           (object)    Input object
        output          (object)    Output object
        mesh            (object)    Mesh object
        model           (object)    TF pre-trained model
        pad             (tuple)     Padding tuple ((0, padnx), (0, padny), (0, padnz))
        on_loc_mask     (np.array)  Localization mask
        modulo          (int)       Network architecture modulo
        padnx           (int)       Padding x axis
        padny           (int)       Padding y axis
        padnz           (int)       Padding z axis
        use_gpu         (bool)      Check if GPU is used (default=True)
        custom_ids      (list)      Custom GPU ids
        fill_obs        (bool)      Fill obstacles condition
        model_params
        gpu_params
        name
    """
    def __init__(self, tfv=tfv):
        self.mpienv = None
        _, self.output = None, None
        self.mesh = None
        self.tfv = tfv

        self.model_params = {}
        self.gpu_params = {}

        self.model = None
        self.pad = ()
        self.non_loc_mask = np.array([], dtype="bool")

        self.modulo = 0
        self.padnx = 0
        self.padny = 0
        self.padnz = 0


    def initialize(self, env, io, mesh, non_loc_mask):
        """"
        Intialize TF CNN object
        """
        self.mpienv = env
        _, self.output = io
        self.mesh = mesh
        self.tfv = tfv

        self.read_nn_params()

        self.use_gpu = self.gpu_params["use_gpu"]
        self.custom_ids = self.gpu_params["custom_ids"]
        try: self.fill_obs = self.model_params["fill_obs"]
        except KeyError: self.fill_obs = False

        self.set_gpus()
        self.set_non_loc_mask(non_loc_mask)
        self.init_nn()


    def read_nn_params(self):
        """
        Read NN parameters from cnntf.yml
        """
        assert os.path.exists("./cnntf.yml"), \
                "Error cnntf.yml file not found in your run directory"

        with open("./cnntf.yml", "r", encoding="utf-8") as ymlfile:
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
        Manage GPUs placement for TF2 and TF1
        """
        self.output.log_hl0("GPUs setting\n", dblv=0)
        tic = self.mpienv.MPI.Wtime()
        if self.tfv == 1:
            gpuid, gpuspernode = self.set_gpus_tf1()
        elif self.tfv == 2:
            gpuid, gpuspernode = self.set_gpus_tf2()
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.set_gpus += toc - tic

        dblv = 1
        if gpuspernode > 0:
            self.output.log_hl1(f"Use GPU = {self.use_gpu}", dblv)

        if gpuspernode > 0 and self.use_gpu:
            self.output.log_hl1(f"GPUs per node = {gpuspernode}", dblv)
            self.output.log_hl1(f"{'MPI rank':<15} {'Local GPUID':<20} {'Node':<15}", dblv)
            self.output.log_hl1(f"{self.mpienv.comm_rank:<15} {gpuid:<20} {self.mpienv.MPI.Get_processor_name():<15}", dblv, allmpi=True)
        else:
            self.output.log_hl1("GPU not found/used -> Using CPU for NN inference", dblv)
        self.output.log_hl0(timer=self.output.timers.set_gpus, dblv=0)


    def set_gpus_tf2(self):
        """"
        Set GPUs placement for TF2

        Returns:
            gpuid       (int)   GPU id
            gpuspernode (int)   Number of available GPUs per computing node
        """
        gpus = tf.config.list_physical_devices("GPU")
        cpus = tf.config.list_physical_devices("CPU")
        gpuid = None
        gpuspernode = len(gpus)

        if gpuspernode > 0 and self.use_gpu:
            if self.custom_ids:
                ids = self.gpu_params["ids_per_node"]
                gpuid = ids[self.mpienv.comm_rank % len(ids)]
            else:
                gpuid = self.mpienv.comm_rank % gpuspernode

            gpu = gpus[gpuid]
            tf.config.set_visible_devices(gpu, device_type="GPU")
            tf.config.experimental.set_memory_growth(gpu, True)

        else:
            tf.config.experimental.set_visible_devices([], "GPU")

        return gpuid, gpuspernode


    def set_gpus_tf1(self):
        """
        Set GPUs placement for TF1

        Returns:
            gpuid       (int)   GPU id
            gpuspernode (int)   Number of available GPUs per computing node
        """
        gpuid = None
        gpuspernode = str(subprocess.check_output(["nvidia-smi", "-L"])).count('UUID')
        if gpuspernode > 0 and self.use_gpu:
            if self.custom_ids:
                ids = self.gpu_params["ids_per_node"]
                gpuid = ids[self.mpienv.comm_rank % len(ids)]
            else:
                gpuid = self.mpienv.comm_rank % gpuspernode

            config = tf.ConfigProto()
            config.gpu_options.visible_device_list = str(gpuid)
            config.gpu_options.allow_growth = True
            set_session(tf.Session(config=config))

        return gpuid, gpuspernode


    def init_nn(self):
        """
        Load NN model and perform a first inference.
        """
        self.output.log_hl0("Init neural network model\n", dblv=0)

        dblv = 1
        self.output.log_hl1(f"TensorFlow version = {tf.__version__}\n", dblv)

        self.output.log_hl1("Load model ...", dblv)
        modelfile = self.model_params["modelfile"]
        tic = self.mpienv.MPI.Wtime()
        self.model = load_model(modelfile)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.init_nn += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)

        self.output.log_hl1(f"Fill obstacles = {self.fill_obs}\n", dblv)

        self.output.log_hl1("Padding ...", dblv)
        tic = self.mpienv.MPI.Wtime()
        self.padding()
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.init_nn += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)

        self.output.log_hl1("First dummy prediction ...", dblv)
        tic = self.mpienv.MPI.Wtime()
        self.predict(np.ones((1, self.mesh.nx * self.mesh.ny * self.mesh.nz), dtype="float64"))
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.init_nn += toc - tic
        self.output.log_hl1(timer=(toc-tic), dblv=dblv)

        self.output.log_hl0(timer=self.output.timers.init_nn, dblv=0)


    def predict(self, array):
        """
        Pre-process input fields (reshape + overlap + pad)
        TF CNN inference
        Post-process output fields (~reshape + ~overlap)

        Args:
            array       (np.array)  Input fields of shape (mesh.nvertex,)

        Returns:
            dl_fields   (np.array)  Output fields of shape (mesh.nvertex,)
        """
        tic = self.mpienv.MPI.Wtime()

        # Need padding because dimensions must be a multiple of self.modulo
        array = self._to_structured(array[0], self.non_loc_mask)
        array = self.mesh.create_fields_with_overlap(array)
        array = np.pad(array, pad_width=self.pad, mode='edge')

        # 5 dims for prediction: batch, dim_x, dim_y, dim_z, channel
        array = array.reshape((1,
                                self.mesh.nx+self.mesh.ol_x_n_elmts_left+self.mesh.ol_x_n_elmts_right+self.padnx,
                                self.mesh.ny+self.mesh.ol_y_n_elmts_down+self.mesh.ol_y_n_elmts_up+self.padny,
                                self.mesh.nz+self.mesh.ol_z_n_elmts_back+self.mesh.ol_z_n_elmts_front+self.padnz,
                                1))

        toc = self.mpienv.MPI.Wtime()
        self.output.timers.pred["prep"] = toc - tic

        tic = self.mpienv.MPI.Wtime()
        # Prediction function
        if self.tfv == 1:
            prediction = self.model.predict(array)
        if self.tfv == 2:
            prediction = self.model(array, training=False)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.pred["run"] = toc - tic

        tic = self.mpienv.MPI.Wtime()
        prediction = np.array(prediction[0,
                                         :prediction.shape[1]-self.padnx,
                                         :prediction.shape[2]-self.padny,
                                         :prediction.shape[3]-self.padnz,
                                         0],
                              dtype=array.dtype)
        prediction = self.mesh.get_fields_without_overlap(prediction)
        dl_fields = self._to_unstructured(prediction)
        toc = self.mpienv.MPI.Wtime()
        self.output.timers.pred["post"] = toc - tic

        self.output.timers.pred["full"] = sum(list(self.output.timers.pred.values())[:-1])

        return np.array([dl_fields, np.sin(np.cos(dl_fields))]) # return dl_fields @dbg to remove sin inference


    def padding(self):
        """"
        Create padding for CNN
        """
        self.modulo = self.model_params["CNN_params"]["shape_modulo"]
        if (self.mesh.nx+self.mesh.ol_x_n_elmts_left+self.mesh.ol_x_n_elmts_right) % self.modulo > 0:
            self.padnx = self.modulo-(self.mesh.nx+self.mesh.ol_x_n_elmts_left+self.mesh.ol_x_n_elmts_right) % self.modulo
        if (self.mesh.ny+self.mesh.ol_y_n_elmts_down+self.mesh.ol_y_n_elmts_up) % self.modulo > 0:
            self.padny = self.modulo-(self.mesh.ny+self.mesh.ol_y_n_elmts_down+self.mesh.ol_y_n_elmts_up) % self.modulo
        if (self.mesh.nz+self.mesh.ol_z_n_elmts_back+self.mesh.ol_z_n_elmts_front) % self.modulo > 0:
            self.padnz = self.modulo-(self.mesh.nz+self.mesh.ol_z_n_elmts_back+self.mesh.ol_z_n_elmts_front) % self.modulo
        self.pad = ((0, self.padnx), (0, self.padny), (0, self.padnz))


    @staticmethod
    def fill_obstacles(array, non_loc_mask):
        """
        Replace non-located values with nearest located values
        """
        h, w, d = array.shape[:3]
        xx, yy, zz = np.meshgrid(np.arange(h), np.arange(w), np.arange(d), indexing='ij')
        non_loc_mask = np.reshape(non_loc_mask, (h, w, d), order='F')

        known_x = xx[~non_loc_mask]
        known_y = yy[~non_loc_mask]
        known_z = zz[~non_loc_mask]
        known_v = array[~non_loc_mask]
        missing_x = xx[non_loc_mask]
        missing_y = yy[non_loc_mask]
        missing_z = zz[non_loc_mask]

        interp_values = griddata(
            (known_x, known_y, known_z), known_v, (missing_x, missing_y, missing_z),
            method='nearest', fill_value=0
        )

        interp_array = array.copy()
        interp_array[missing_x, missing_y, missing_z] = interp_values
        return interp_array


    def _to_structured(self, array, non_loc_mask):
        """
        Turn unstructured (nx*ny*nz) array to structured array (nx, ny, nz)
        """
        struct_arr = array.reshape((self.mesh.nx, self.mesh.ny, self.mesh.nz), order='F')

        if self.fill_obs:
            return self.fill_obstacles(struct_arr, non_loc_mask)
        else:
            return struct_arr


    def _to_unstructured(self, array):
        """
        Turn structured (nx, ny, nz) array to unstructured array (nx*ny*nz)
        """
        return array.reshape((1, self.mesh.nx * self.mesh.ny * self.mesh.nz), order='F')


    def set_non_loc_mask(self, array):
        """
        Set localization mask used to fill in the obstacles
        """
        self.non_loc_mask = array
