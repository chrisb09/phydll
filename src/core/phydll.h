/******************************************************************************
 * \headerfile src/core/phydll.h
 * \brief Header file of PhyDLL’s C interface
 * \authors A. Serhani, C. Lapeyre, G. Staffelbach
 * \mainpage phydll.readthedocs.io
 * \remark phydll@cerfacs.fr
 * \date Wed, Apr 12, 2023
 * \copyright CeCILL-B FREE SOFTWARE LICENSE AGREEMENT
 * \copyright COPYRIGHT (C) [2023] [CERFACS]
******************************************************************************/
#ifndef PHYDLL_HEADER
#define PHYDLL_HEADER

#include <mpi.h>

#include <stdbool.h>


// Initialize/finalize
void phydll_init(char instance[]); //@hc , MPI_Comm *glcomm, MPI_Comm *comm);
void phydll_finalize();
MPI_Fint phydll_get_local_mpi_fcomm();
MPI_Comm phydll_get_local_mpi_comm();


// Definitions
void phydll_define_phy(int count, int size);
void phydll_define_phy_with_mesh(
    int count, int geodim, int ncell, int nnode, int ntcell, int ntnode, int nvert,
    int** connec, double** coords, int** local_cell_to_global, int** local_node_to_global
);
void phydll_define_dl(int count);


// Setters & getters
void phydll_set_field(double** field, char label[]);
void phydll_get_field(double** field, char label[]);
void phydll_get_field_size(int* size);
void phydll_get_field_counts(int* phy_count, int* dl_count);
int phydll_get_phy_ite();
int phydll_get_ite();


// Communications
void phydll_send();
void phydll_isend();
void phydll_wait_isend();
void phydll_recv();
void phydll_irecv();
void phydll_wait_irecv();


// Options
void phydll_opt_enable_cpl_loop();
void phydll_opt_set_freq(int freq);
void phydll_opt_set_output_freq(int output_freq);


// Booleans
bool phydll_is_phy_signal();
bool phydll_is_phy_instance();
bool phydll_is_dl_instance();


#endif
