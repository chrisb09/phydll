""" Copyright (c) CERFACS (all rights reserved)
@file       main.py
@details    Generic main routine of deep learing instance of AVBP-DL
@autor      A. Serhani
"""
import argparse
import os
import sys 
from phydll.phydll import PhyDLL

parser = argparse.ArgumentParser()
parser.add_argument("--dl_lib", "-l", type=str, help="DL library", default="tf")
parser.add_argument("--scheme", "-s", type=str, help="Coupling scheme", default="DirectScheme")
parser.add_argument("--mesh", "-m", type=str, help="Mesh type", default="NC")
args = parser.parse_args()
dl_lib = args.dl_lib
scheme = args.scheme
mesh = args.mesh

def main():
    """
    Main coupling routine
    """
    PHYDLL_DIR = os.getenv('PHYDLL_DIR')
    sys.path.append(f"{PHYDLL_DIR}/scripts/nn")

    phydll = PhyDLL(coupling_scheme=scheme,
                    mesh_type=mesh,
                    phy_nfields=1,
                    dl_nfields=1)

    if dl_lib == "tf":
        from cnntf import ConvNeuralNetTF
        dl = ConvNeuralNetTF()
    elif dl_lib == "torch":
        from gnnpyg import GraphNeuralNetPyg
        dl = GraphNeuralNetPyg()
    elif dl_lib == "custom":
        from custom import CustomInference
        dl = CustomInference()

    # Pre-processing
    dl.initialize(env=phydll.mpienv, io=(phydll.input, phydll.output), mesh=phydll.mesh)

    # Temporal
    phydll.mpienv.glcomm.Barrier()
    use_temporal_loop = True
    if use_temporal_loop:
        phydll.set_predict_func(dl.predict)
        phydll.temporal()
    else:
        while phydll.fsignal:
            phy_fields = phydll.receive_phy_fields()
            dl_fields = dl.predict(phy_fields)
            phydll.send_dl_fields(dl_fields)

    # for i in range(5):
    #     phy_fields = phydll.receive_phy_fields()
    #     dl_fields = dl.predict(phy_fields)
    #     phydll.send_dl_fields(dl_fields)

    # Finalize
    phydll.finalize()

if __name__ == "__main__":
    main()
