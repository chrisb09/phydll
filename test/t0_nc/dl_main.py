"""
DATE    : 02-05-2023
"""
from pyphydll.pyphydll import PhyDLL

dll = PhyDLL()

dll.init(instance="dl")
comm = dll.get_local_mpi_comm(); comm.Get_rank(); comm.Get_size()

count = 2
dll.define_dl(count=count)

phy_count, _ = dll.get_field_counts()

phy_fields = {}
dl_fields = {}
ite = 1
while dll.is_phy_signal():

    if (ite%2 == 0):
        dll.recv(only=True)
        for i in range(dll.phy_count):
            field, label = dll.get_field()
            phy_fields[label] = field
    else: phy_fields = dll.recv()

    dl_fields["python_dl_field_0"] = phy_fields[list(phy_fields.keys())[0]] * (-10)
    dl_fields["python_dl_field_1"] = phy_fields[list(phy_fields.keys())[1]] * (-10)

    if (ite%2 == 0):
        dll.send(dl_fields)
    else:
        for label in dl_fields.keys():
            dll.set_field(dl_fields[label], label)
        dll.send()

    ite += 1

dll.finalize()
