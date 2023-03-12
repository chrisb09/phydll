# /
import argparse
from phydll.phydll import PhyDLL
import numpy as np
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--scheme", "-s", type=str, help="Coupling scheme", default="DirectScheme")
parser.add_argument("--mesh", "-m", type=str, help="Mesh type", default="NC")
args = parser.parse_args()
scheme = args.scheme
mesh = args.mesh

def main():
    """
    Main coupling routine
    """
    phydll = PhyDLL(coupling_scheme=scheme,
                    mesh_type=mesh,
                    phy_nfields=1,
                    dl_nfields=1)

    while phydll.fsignal:
        phy_fields = phydll.receive_phy_fields()
        dl_fields = -1./(1 + phy_fields)
        phydll.send_dl_fields(dl_fields)

    # Finalize
    phydll.finalize()

if __name__ == "__main__":
    main()
