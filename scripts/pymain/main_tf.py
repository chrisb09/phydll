""" Copyright (c) CERFACS (all rights reserved)
@file       main.py
@details    Main routine of deep learing instance of AVBP-DL
"""
from phydll.phydll import PhyDLL
from phydll.nn.cnntf import ConvNeuralNetTF

def main():
    """
    Main coupling routine
    """
    # Create coupling instance
    phydll = PhyDLL(coupling_scheme="InterpolationScheme",
                    mesh_type="voxgrid",
                    phy_nfields=3,
                    dl_nfields=2)

    dl = ConvNeuralNetTF()

    # Pre-processing
    phydll.pre_processing()
    dl.initialize(env=phydll.mpienv,
                io=(phydll.input, phydll.output),
                mesh=phydll.mesh,
                non_loc_mask=phydll.cplinterf.non_loc_mask
                )

    while phydll.fsignal:
        phy_fields = phydll.receive_phy_fields()
        dl_fields = dl.predict(phy_fields)
        phydll.send_dl_fields(dl_fields)

    # Finalize
    phydll.finalize()

if __name__ == "__main__":
    main()
