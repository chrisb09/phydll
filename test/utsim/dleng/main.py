from mpi4py import MPI

from os.path import abspath, dirname
import sys
from pyphydll.pyphydll import PhyDLL

def main():
    dll = PhyDLL()

    dll.init(instance="dl")
    dll.define_dl(count=1)

    ite = 0
    while dll.is_phy_signal():
        ite += 1

        if ite%4 == 0:
            phy_fields = dll.recv()
        elif ite%4 == 1:
            dll.irecv()
            phy_fields = dll.wait_irecv()
        elif ite%4 == 2:
            dll.recv(only=True)
            for i in range(dll.phy_count):
                field, label = dll.get_field()
                phy_fields[label] = field
        elif ite%4 == 3:
            dll.irecv()
            dll.wait_irecv(only=True)
            for i in range(dll.phy_count):
                field, label = dll.get_field()
                phy_fields[label] = field

        dl_fields = predict(phy_fields)

        if ite%2 == 0:
            dll.send(dl_fields)
        elif ite%2 == 1:
            dll.isend(dl_fields)
            dll.wait_isend()

    dll.finalize()

def predict(phy_fields: dict) -> dict:
    dl_fields = {}
    dl_fields["python_dl_field_0"] = phy_fields[list(phy_fields.keys())[0]] * (-10)

    return dl_fields

if __name__ == "__main__":
    main()
