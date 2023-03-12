"""
@file       ds_nc/main.py
@details    Example of DL engine for Direct-Scheme Non-context aware coupling
@authors    A. Serhani, C. Lapeyre, G, Staffelbach
@email      phydll@cerfacs.fr
"""
from phydll.phydll import PhyDLL

def main():
    """
    Main coupling routine
    """
    phydll = PhyDLL(coupling_scheme="DS",
                    mesh_type="NC",
                    phy_nfields=2,
                    dl_nfields=1)

    while phydll.fsignal:
        # Recv Phy fields
        phy_fields = phydll.receive_phy_fields()

        # Inference
        dl_fields = your_predict_fct(phy_fields)

        # Send DL fields
        phydll.send_dl_fields(dl_fields)

    # Finalize
    phydll.finalize()

def your_predict_fct(fields):
    """
    Dummy inference function
    """
    return - (fields[0, :] + fields[1, :]) / 2.

if __name__ == "__main__":
    main()
