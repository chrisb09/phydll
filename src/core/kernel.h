/******************************************************************************
 * \headerfile src/core/kernel.h
 * \brief Header file of PhyDLL's C core
 * \authors A. Serhani, C. Lapeyre, G. Staffelbach
 * \mainpage phydll.readthedocs.io
 * \remark phydll@cerfacs.fr
 * \date Tue, Apr 11, 2023
 * \copyright CeCILL-B FREE SOFTWARE LICENSE AGREEMENT
 * \copyright COPYRIGHT (C) [2023] [CERFACS]
******************************************************************************/
#ifndef KERNEL_HEADER
#define KERNEL_HEADER

#include <mpi.h>

#include "kernel_structs.h"


// Initialize/Finalize
void kernel_init(env_t* env, cpl_t* cpl, char instance[]);
void kernel_finalize(env_t* env, cpl_t* cpl);
MPI_Fint kernel_get_fcomm(env_t* env);


// Processes mapping
void kernel_ds_mapping(env_t* env);


// Allocate fields
void kernel_alloc_phy_fields(env_t* env, cpl_t* cpl, int count, int size);
void kernel_alloc_dl_fields(env_t* env, cpl_t* cpl, int count);


// Mesh
void kernel_set_phy_mesh(
    env_t* env, msh_t* msh, int geodim, int ncell, int nnode, int ntcell, int ntnode, int nvert, \
    int** connec, double** coords, int** local_cell_to_global, int** local_node_to_global
);
void kernel_send_phy_mesh(env_t* env, msh_t* msh);
void kernel_agg_phy_mesh(env_t* env, cpl_t* cpl, msh_t* msh);


// Setter/getter
void kernel_set_field(env_t* env, cpl_t* cpl, double** field, char label[]);
void kernel_get_field(env_t* env, cpl_t* cpl, double** field, char label[]);
void kernel_get_field_size(cpl_t* cpl, msh_t* msh, int* size);
void kernel_get_field_counts(cpl_t* cpl, int* phy_count, int* dl_count);


// Send/recv
void kernel_isend_field(env_t* env, cpl_t* cpl, msh_t* msh);
void kernel_wait_isend(env_t* env, cpl_t* cpl, msh_t* msh);
void kernel_irecv_field(env_t* env, cpl_t* cpl);
void kernel_wait_irecv(env_t* env, cpl_t* cpl, msh_t* msh);


// Counters
void kernel_zero_ic(cpl_t* cpl);


// Bcast signal
void kernel_bcast_signal(env_t* env, cpl_t* cpl);

#endif
