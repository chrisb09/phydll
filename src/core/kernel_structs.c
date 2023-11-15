/******************************************************************************
 * \file src/core/kernel_structs.c
 * \brief PhyDLL’s kernel structures
 * \authors A. Serhani, C. Lapeyre, G. Staffelbach
 * \mainpage phydll.readthedocs.io
 * \remark phydll@cerfacs.fr
 * \date Tue, Apr 11, 2023
 * \copyright CeCILL-B FREE SOFTWARE LICENSE AGREEMENT
 * \copyright COPYRIGHT (C) [2023] [CERFACS]
******************************************************************************/
#include <mpi.h>
#include <string.h>
#include <stdbool.h>

#include "params.h"
#include "kernel_structs.h"


/******************************************************************************
 * \brief Initialize the environment structure (constructor)
 * \param env_t* PhyDLL's environment struct
******************************************************************************/
void env_init(env_t* env) {
    strcpy(env->instance, CINIT);
    env->is_phy_instance = false;
    env->is_dl_instance = false;

    env->glcomm = MPI_COMM_NULL;
    env->glcomm_size = IINIT;
    env->glcomm_rank = IINIT;

    env->comm = MPI_COMM_NULL;
    env->comm_size = IINIT;
    env->comm_rank = IINIT;

    env->host_rank = IINIT;
    env->comm_hrank = IINIT;

    env->dist_rank = IINIT;
    env->dist_size = IINIT;

    env->ndest = IINIT;
}


/******************************************************************************
 * \brief Initialize the mesh structure (constructor)
 * \param env_t* PhyDLL's mesh struct
******************************************************************************/
void msh_init(msh_t* msh) {
    msh->geodim = IINIT;
    msh->ncell = IINIT;
    msh->nnode = IINIT;
    msh->ntcell = IINIT;
    msh->ntnode = IINIT;
    msh->nvert = IINIT;
    strcpy(msh->topology_type, CINIT);
}


/******************************************************************************
 * \brief Initialize the coupling structure (constructor)
 * \param env_t* PhyDLL's coupling struct
******************************************************************************/
void cpl_init(cpl_t* cpl) {
    cpl->size = IINIT;
    cpl->phy_count = IINIT;
    cpl->dl_count = IINIT;
    cpl->phy_ite = IINIT;
    cpl->ite = IINIT;
    cpl->phy_ic = IINIT;
    cpl->dl_ic = IINIT;
    cpl->freq = 1;
    cpl->is_cpl_ite = true;
    cpl->is_with_loop = false;
    cpl->output_freq = 1;
}
