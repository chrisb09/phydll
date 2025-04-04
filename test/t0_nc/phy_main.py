"""
Date 14-07-2023
"""
import numpy as np
from pyphydll.pyphydll import PhyDLL
from time import sleep

def main():
    size = 7
    count = 2
    niter = 10

    phyl = PhyDLL()

    phyl.init(instance="physical")
    comm = phyl.get_local_mpi_comm()
    myrank = comm.Get_rank()

    phyl.opt_enable_cpl_loop()
    phyl.opt_set_freq(2)
    phyl.opt_set_output_freq(3)

    phyl.define_phy(count=count, size=size)

    phy_fields = {}
    dl_fields = {}
    for iter in range(niter):
        for i in range(phyl.phy_count):
            phy_fields[f"python_phy_fields_{i}"] = (1 * myrank + 10. * i + 100 * iter) * np.ones(size)

        phyl.send(phy_fields)

        sleep(0.1)

        dl_fields = phyl.recv()

    phyl.finalize()

if __name__ == "__main__":
    main()
