"""
@file src/python/cyphydll.pyx
@brief PhyDLL's cython interface of the C core code to the python interface
@authors A. Serhani, C. Lapeyre, G. Staffelbach
@mainpage phydll.readthedocs.io
@email phydll@cerfacs.fr
@date Sun, Apr 30, 2023
@copyright CeCILL-B FREE SOFTWARE LICENSE AGREEMENT
@copyright COPYRIGHT (C) [2023] [CERFACS]
"""

# Import libraries
import numpy as np
cimport numpy as np
from libcpp cimport bool as cbool
from mpi4py.MPI cimport Comm
from mpi4py.libmpi cimport MPI_Comm


# Import C code parameters
cdef extern from "params.h":
    cdef extern const int IINIT
    cdef const double DINIT
    cdef const char* CINIT
    cdef const int ML_CHAR
pyIINIT: int = IINIT
pyDINIT: float = DINIT
pyCINIT: str = str(CINIT, encoding='utf-8')
pyML_CHAR: int = ML_CHAR


# Import C interface functions
cdef extern from "phydll.h":
    # Initialize/finalize
    void phydll_init(char instance[])
    void phydll_finalize()

    # Definitions
    void phydll_define_phy(int count, int size)
    void phydll_define_phy_with_mesh(int count, int geodim, int ncell, int nnode, int ntcell, \
                                    int ntnode, int nvert, int** connec, double** coords, \
                                    int** local_cell_to_global, int** local_node_to_global)
    void phydll_define_dl(int count)

    # Communications
    void phydll_send()
    void phydll_isend()
    void phydll_wait_isend()
    void phydll_recv()
    void phydll_irecv()
    void phydll_wait_irecv()

    # Getters/setters
    void phydll_get_field(double** field, char label[])
    void phydll_get_field_size(int* size)
    void phydll_get_field_counts(int* phy_count, int* dl_count)
    void phydll_set_field(double** field, char label[])
    MPI_Comm phydll_get_local_mpi_comm()
    int phydll_get_dist_rank()
    int phydll_get_dist_size()
    int* phydll_get_dest()
    int phydll_get_ndest()

    # Boolean status
    cbool phydll_is_phy_signal()
    cbool phydll_is_phy_instance()
    cbool phydll_is_dl_instance()

    # Options
    void phydll_opt_set_freq(int freq)
    void phydll_opt_set_output_freq(int output_freq)
    void phydll_opt_enable_cpl_loop()
#


"""
@brief Intiliaze PhyDLL
@param str Instance type
"""
def pyphydll_init(instance: str) -> None:
    phydll_init(instance.encode('utf-8'))
#


"""
@brief Finalize PhyDLL
"""
def pyphydll_finalize() -> None:
    phydll_finalize()
#


"""
@brief Define physical solver instance (non-context aware)
@param int Physical fields count
@param int Size/length of the field
"""
def pyphydll_define_phy(count: int, size: int) -> None:
    phydll_define_phy(count, size)
#


"""
@brief Define physical solver with mesh support (DS)
@param int Number of Physical fields to send
@param int Geometric dimension
@param int Number of local mesh cells
@param int Number of local mesh nodes
@param int Number of global (full) mesh cells
@param int Number of global (full) mesh nodes (without duplication)
@param int Number of nodes per element (eg. quad=4, tetra=4, hexa=8, prism=6, ...)
@param np.ndarray[np.int] Local connectivity table (element to node), len=nvert*ncell
@param np.ndarray[np.double] Local coordinates table, len=geodim*nnode
@param np.ndarray[np.int] Table of local to global cell numerotation, len=ncell
@param np.ndarray[np.int] Table of local to global node numerotation, len=nnode
"""
def pyphydll_define_phy_with_mesh(
    count: int,
    geodim: int,
    ncell: int,
    nnode: int,
    ntcell: int,
    ntnode: int,
    nvert: int,
    connec: np.ndarray[np.int],
    coords: np.ndarray[np.double],
    local_cell_to_global: np.ndarray[np.int],
    local_node_to_global: np.ndarray[np.int]
    ) -> None:

    cdef int* _connec = <int*> np.PyArray_DATA(connec)
    cdef double* _coords = <double*> np.PyArray_DATA(coords)
    cdef int* _local_cell_to_global = <int*> np.PyArray_DATA(local_cell_to_global)
    cdef int* _local_node_to_global = <int*> np.PyArray_DATA(local_node_to_global)

    phydll_define_phy_with_mesh(
        count, geodim, ncell, nnode, ntcell, ntnode, nvert,
        &_connec, &_coords, &_local_cell_to_global, &_local_node_to_global
    )
#


"""
@brief Define DL instance
@param int DL fields count
"""
def pyphydll_define_dl(count: int) -> None:
    phydll_define_dl(count)
#


"""
@brief Send fields from PhyDLL's buffer
"""
def pyphydll_send() -> None:
    phydll_send()
#


"""
@brief Non-blocking send of fields
"""
def pyphydll_isend() -> None:
    phydll_isend()
#


"""
@brief Waiting barrier for the non-blocking send
"""
def pyphydll_wait_isend() -> None:
    phydll_wait_isend()
#


"""
@brief Recv fields into PhyDLL's buffer
"""
def pyphydll_recv() -> None:
    phydll_recv()


"""
@brief Non-blocking receive
"""
def pyphydll_irecv() -> None:
    phydll_irecv()
#


"""
@brief Waiting barrier for the non-blocking receive
"""
def pyphydll_wait_irecv() -> None:
    phydll_wait_irecv()
#


"""
@brief Get physical field size
@return int the size
"""
def pyphydll_get_field_size() -> int:
    cdef int size
    phydll_get_field_size(&size)
    return size
#


"""
@brief Get physical/dl fields count
@return int physical count
@return int dl count
"""
def pyphydll_get_field_counts() -> (int, int):
    cdef int phy_count
    cdef int dl_count
    phydll_get_field_counts(&phy_count, &dl_count)
    return phy_count, dl_count
#


"""
@brief Get the received field (copy from buffer)
@return np.ndarray[np.double] The field (dp array)
@return str Label of the field
"""
def pyphydll_get_field() -> (np.ndarray[np.double], str):
    cdef double* field
    cdef char label[ML_CHAR]
    size = pyphydll_get_field_size()
    cdef np.ndarray[np.double_t, ndim=1] pyfield = np.zeros(size, dtype=np.double)
    phydll_get_field(&field, label)
    pyfield[:] = <np.double_t[:size]> field
    return pyfield, str(label, encoding='utf-8')
#


"""
@brief Set field to send (copy to buffer)
@param np.ndarray[np.double] The field (dp array)
@param str Label of the field
"""
def pyphydll_set_field(field: np.ndarray[np.double], label: str) -> None:
    cdef double *cfield = <double*> np.PyArray_DATA(field)
    phydll_set_field(&cfield, label.encode('utf-8'))
#


def pyphydll_get_distribution_info() -> dict:
    cdef int i, ndest
    cdef int* dest_ptr

    dist_rank = phydll_get_dist_rank()
    dist_size = phydll_get_dist_size()
    dest_ptr = phydll_get_dest()
    ndest = phydll_get_ndest()

    if dest_ptr == NULL or ndest == 0:
        dest_list = []
    else:
        dest_list = [dest_ptr[i] for i in range(ndest)]

    return {
        "dist_rank": dist_rank,
        "dist_size": dist_size,
        "ndest": ndest,
        "dest": dest_list
    }
#

"""
@brief Physical signal to send data
@return bool Status
"""
def pyphydll_is_phy_signal() -> bool:
    return phydll_is_phy_signal()
#


"""
@brief Current instance is the physical solver one?
@return bool Status
"""
def pyphydll_is_phy_instance() -> bool:
    return phydll_is_phy_instance()
#


"""
@brief Current instance is the DL one?
@return bool status
"""
def pyphydll_is_dl_instance() -> bool:
    return phydll_is_dl_instance()
#


"""
@brief Get local mpi communicator
@return MPI.Comm Local mpi communicator
"""
def pyphydll_get_local_mpi_comm() -> Comm:
    cdef MPI_Comm _comm = phydll_get_local_mpi_comm()
    comm = Comm()
    comm.ob_mpi = _comm
    return comm
#


"""
@brief Optionally enable loop mode
"""
def pyphydll_opt_enable_cpl_loop() -> None:
    phydll_opt_enable_cpl_loop()
#


"""
@brief Optionally set coupling frequency
@brief Default value = 1
"""
def pyphydll_opt_set_freq(freq: int) -> None:
    phydll_opt_set_freq(freq)
#


"""
@brief Optionally set output frequency
@brief Default value = 1
"""
def pyphydll_opt_set_output_freq(output_freq: int) -> None:
    phydll_opt_set_output_freq(output_freq)
#
