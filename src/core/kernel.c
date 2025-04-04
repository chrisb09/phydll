/******************************************************************************
 * \file src/core/kernel.c
 * \brief PhyDLL’s C core code
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
#include <stdio.h>
#include <stdlib.h>

#include "params.h"
#include "kernel_structs.h"
#include "io.h"
#include "utils.h"


// Internal functions
static void _kernel_bcast_field_size(env_t* env, cpl_t* cpl);
static void _kernel_agg_field_sizes(env_t* env, cpl_t* cpl);
static void _kernel_alloc_fields(env_t* env, cpl_t* cpl);
static void _kernel_get_mesh_topology(msh_t* msh);
static void _kernel_bcast_is_with_phy_mesh(env_t* env, cpl_t* cpl);
static void _kernel_bcast_mesh_info(env_t* env, msh_t* msh);
static bool _kernel_is_cpl_ite(cpl_t* cpl);
static bool _kernel_is_output_ite(cpl_t* cpl);


/******************************************************************************
 * \brief 1. Check if PhyDLL is enabled
 * \brief 2. Split communicators
 * \brief 3. Set host/distant ranks
 * \param env_t* PhyDLL's environment struct
 * \param char Instance name: physical solver or deep learning engine
******************************************************************************/
void kernel_init(env_t* env, cpl_t* cpl, char instance[]) {
    // Initialize environment
    env_init(env);
    cpl_init(cpl);

    // Global communicator
    env->glcomm = MPI_COMM_WORLD;
    MPI_Comm_size(env->glcomm, &env->glcomm_size);
    MPI_Comm_rank(env->glcomm, &env->glcomm_rank);

    // Instance type
    int color = IINIT;
    strcpy(env->instance, instance);
    if (strcmp(env->instance, "physical") == 0 || strcmp(env->instance, "Physical") == 0 ||
        strcmp(env->instance, "phy") == 0 || strcmp(env->instance, "Phy") == 0)
    {
        color = 0;
        env->is_phy_instance = true;
    }

    else if (strcmp(env->instance, "dl") == 0 || strcmp(env->instance, "deeplearning") == 0 ||
            strcmp(env->instance, "DL") == 0 || strcmp(env->instance, "DeepLearning") == 0)
    {
        color = 1;
        env->is_dl_instance = true;
    }

    // Split communicator
    MPI_Comm_split(env->glcomm, color, env->glcomm_rank, &env->comm);
    MPI_Comm_size(env->comm, &env->comm_size);
    MPI_Comm_rank(env->comm, &env->comm_rank);

    // Host/distant ranks (physical solver)
    if (env->is_phy_instance) {
        env->host_rank = 0;
        env->dist_rank = env->glcomm_size - 1;
        env->comm_hrank = 0;

        env->phy_bcast_root = env->host_rank;
        env->dl_bcast_root = env->dist_rank;
    }

    // Host/distant ranks (dl engine)
    else if (env->is_dl_instance) {
        env->host_rank = env->glcomm_size - 1;
        env->dist_rank = 0;
        env->comm_hrank = env->comm_size - 1;

        env->phy_bcast_root = env->dist_rank;
        env->dl_bcast_root = env->host_rank;
    }

    // Distant size
    env->dist_size = env->glcomm_size - env->comm_size;
}


/******************************************************************************
 * \brief Get local communicator as Fortran integer
 * \param env_t* PhyDLL's environment struct
******************************************************************************/
MPI_Fint kernel_get_fcomm(env_t* env) {
    MPI_Fint comm_f;
    comm_f = MPI_Comm_c2f(env->comm);
    return comm_f;
}


/******************************************************************************
 * \brief Create mapping of processes for DS coupling
 * \param env_t* PhyDLL's environment struct
*****************************************************************************/
void kernel_ds_mapping(env_t* env) {
    int quo, rem;

    // if (env->comm_size >= env->dist_size) { // @hc
    if (env->is_phy_instance) {
        quo = env->comm_size / env->dist_size;
        rem = env->comm_size % env->dist_size;

        env->ndest = 1;
        env->dest = (int*) malloc(env->ndest * sizeof(int));

        if (env->comm_rank / (quo + 1) < rem) {
            *env->dest = env->comm_size + env->comm_rank / (quo + 1);
        }

        else {
            *env->dest = env->comm_size + (env->comm_rank - rem) / quo;
        }

        // @dbg
        // char msg[LL_CHAR];
        // sprintf(msg, "dest (glrank) = %d (%d)\n", *env->dest - env->comm_size, *env->dest);
        // io_log_dbg(env, msg);
    }

    // else { // @hc
    else if (env->is_dl_instance) {
        quo = env->dist_size / env->comm_size;
        rem = env->dist_size % env->comm_size;

        env->ndest = quo;
        if (env->comm_rank < rem) {
            env->ndest += 1;
        }

        int dest_tasks_per_rank_list[env->comm_size];
        MPI_Allgather(&env->ndest, 1, MPI_INT, dest_tasks_per_rank_list, 1, MPI_INT, env->comm);

        int _sum = 0;
        for (int i = 0; i < env->comm_rank; i++) {
            _sum += dest_tasks_per_rank_list[i];
        }

        env->dest = (int*) malloc(env->ndest * sizeof(int));
        for (int i = 0; i < env->ndest; i++) {
            env->dest[i] = _sum + i;
        }
    }
}


/******************************************************************************
 * \brief Allocate fields for physical solver
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL’s coupling struct
 * \param int Count of fields
 * \param int Size of field
******************************************************************************/
void kernel_alloc_phy_fields(env_t* env, cpl_t* cpl, int count, int size) {
    cpl->phy_count = count;
    cpl->size = size;

    _kernel_bcast_is_with_phy_mesh(env, cpl);
    _kernel_bcast_field_size(env, cpl);
    _kernel_alloc_fields(env, cpl);

    // @dbg
    char msg[LL_CHAR];
    sprintf(msg, "phy_count = %d, dl_count = %d, field_size = %d, ndest = %d, \t {%s:%d}\n\n", cpl->phy_count, cpl->dl_count, cpl->size, env->ndest,  __func__, __LINE__);
    io_log_dbg(env, msg);
}


/******************************************************************************
 * \brief Allocate fields for dl engine
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL’s coupling struct
 * \param int Count of fields
******************************************************************************/
void kernel_alloc_dl_fields(env_t* env, cpl_t* cpl, int count) {
    cpl->dl_count = count;

    _kernel_bcast_is_with_phy_mesh(env, cpl);
    _kernel_bcast_field_size(env, cpl);
    _kernel_agg_field_sizes(env, cpl);
    _kernel_alloc_fields(env, cpl);

    // @dbg
    char msg[LL_CHAR], _msg[LL_CHAR];
    sprintf(msg, "phy_count = %d, dl_count = %d, field_sizes = ", cpl->phy_count, cpl->dl_count);
    for (int i = 0; i < env->ndest; i++) {
        sprintf(_msg, "%d, ", cpl->sizes_list[i]);
        strcat(msg, _msg);
    }
    sprintf(_msg, " sum_sizes = %d, ndest = %d, is_with_phy_mesh = %d \t {%s:%d}\n\n", cpl->size, env->ndest, cpl->is_with_phy_mesh, __func__, __LINE__);
    strcat(msg, _msg);
    io_log_dbg(env, msg);
}


/******************************************************************************
 * \brief (Setter) Set field into PhyDLL’s buffer
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL’s coupling struct
 * \param double** Field to set
 * \param char[] Label of field
**************************************************************************/
void kernel_set_field(env_t* env, cpl_t* cpl, double** field, char label[]) {
    char msg[LL_CHAR];

    if (env->is_phy_instance) {
        cpl->phy_field[cpl->phy_ic].array = *field;
        strcpy(cpl->phy_field[cpl->phy_ic].label, label);
        sprintf(msg, "(PhyDLL:PHY) ----> SET... Physical field: (%d) '%s' ...done\n", cpl->phy_ic, label);

        cpl->phy_ic += 1;
    }

    else if (env->is_dl_instance) {
        if (cpl->is_with_phy_mesh) {
            cpl->dl_field[cpl->dl_ic].array_trim = *field;
        }
        else {
            cpl->dl_field[cpl->dl_ic].array = *field;
        }
        strcpy(cpl->dl_field[cpl->dl_ic].label, label);
        sprintf(msg, "(PhyDLL:DL) ----> SET... DL field: (%d) '%s' ...done\n", cpl->dl_ic, label);

        cpl->dl_ic += 1;
    }

    io_log(env, msg);
}


/******************************************************************************
 * \brief (Getter) Get field from PhyDLL’s buffer
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL’s coupling struct
 * \param double** Field
 * \param char[] Label
******************************************************************************/
void kernel_get_field(env_t* env, cpl_t* cpl, double** field, char label[]) {
    char msg[LL_CHAR];

    if (env->is_phy_instance) {
        for (int i = 0; i < cpl->size; i++) {
            (*field)[i] = cpl->dl_field[cpl->dl_ic].array[i];
        }
        strcpy(label, cpl->dl_field[cpl->dl_ic].label);

        sprintf(msg, "(PhyDLL:PHY) ----> GET... DL field: (%d) '%s' ...done\n", cpl->phy_ic, label);

        // @dbg
        // printf("cpl->phy_ic = %d, cpl->dl_field[cpl->dl_ic].label = %s, ##########################$\n", cpl->phy_ic, cpl->dl_field[cpl->dl_ic].label);

        io_log_dbg_arr(env, cpl->dl_field[cpl->dl_ic].array, cpl->size, cpl->dl_field[cpl->dl_ic].label, __func__, __LINE__);

        cpl->dl_ic += 1;
    }

    if (env->is_dl_instance) {
        // @dbg
        // printf("cpl->phy_ic = %d ##########################$\n", cpl->phy_ic);
        for (int i = 0; i < cpl->size; i++) {
            if (cpl->is_with_phy_mesh) {
                (*field)[i] = cpl->phy_field[cpl->phy_ic].array_trim[i];
            }
            else {
                (*field)[i] = cpl->phy_field[cpl->phy_ic].array[i];
            }
        }
        strcpy(label, cpl->phy_field[cpl->phy_ic].label);
        sprintf(msg, "(PhyDLL:DL) ----> GET... Physical field: (%d) '%s' ...done\n", cpl->phy_ic, label);

        io_log_dbg_arr(env, cpl->phy_field[cpl->phy_ic].array, cpl->size, cpl->phy_field[cpl->phy_ic].label, __func__, __LINE__);

        cpl->phy_ic += 1;
    }

    io_log(env, msg);
}


/******************************************************************************
 * \brief (Getter) Get field size
 * \param cpl_t* PhyDLL’s coupling struct
 * \param msh_t* PhyDLL's mesh struct
 * \param int* Size
******************************************************************************/
void kernel_get_field_size(cpl_t* cpl, msh_t* msh, int* size) {
    *size = (cpl->is_with_phy_mesh) ? msh->nnode : cpl->size;
}


/******************************************************************************
 * \brief (Getter) Get fields counts
 * \param cpl_t* PhyDLL’s coupling struct
 * \param int* phy_count
 * \param int* dl_count
******************************************************************************/
void kernel_get_field_counts(cpl_t* cpl, int* phy_count, int* dl_count) {
    *phy_count = cpl->phy_count;
    *dl_count = cpl->dl_count;
}


/******************************************************************************
 * \brief Broadcast signal to launch data exchange
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL’s coupling struct
******************************************************************************/
void kernel_bcast_signal(env_t* env, cpl_t* cpl) {
    if (env->is_phy_instance) {
        cpl->phy_ite += 1;
        cpl->is_cpl_ite = _kernel_is_cpl_ite(cpl);
    }

    MPI_Bcast(&cpl->phy_ite, 1, MPI_INT, env->phy_bcast_root, env->glcomm);

    cpl->ite += 1;

    cpl->is_phy_signal = (cpl->phy_ite >= 1) ? true : false;

    char msg[LL_CHAR], _msg[LL_CHAR];
    if (cpl->is_phy_signal) {
        if (env->is_phy_instance) sprintf(msg, "(PhyDLL:PHY) ----> ");
        else if (env->is_dl_instance) sprintf(msg, "(PhyDLL:DL) ----> ");
        sprintf(_msg, "ITE (PHY ITE) = %d (%d)\n", cpl->ite, cpl->phy_ite);
        strcat(msg, _msg);
        io_log(env, msg);
    }
}


/******************************************************************************
 * \brief Send fields
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL’s coupling struct
******************************************************************************/
void kernel_isend_field(env_t* env, cpl_t* cpl, msh_t* msh) {
    env->s_nops = IINIT;
    if (env->is_phy_instance) env->s_nops = env->ndest * cpl->phy_count;
    else if (env->is_dl_instance) env->s_nops = env->ndest * cpl->dl_count;

    env->s_requests = (MPI_Request*) malloc(env->s_nops * sizeof(MPI_Request));
    env->s_l_requests = (MPI_Request*) malloc(env->s_nops * sizeof(MPI_Request));

    if (env->is_phy_instance) {
        if (cpl->is_with_loop) {
            kernel_bcast_signal(env, cpl);
        }

        for (int i = 0; i < cpl->phy_count; i++) {
            for (int j = 0; j < env->ndest; j++) {
                MPI_Isend(cpl->phy_field[i].array + j, cpl->size, MPI_DOUBLE, env->dest[j], 1, env->glcomm, &env->s_requests[env->ndest * i + j]);
                MPI_Isend(cpl->phy_field[i].label, ML_CHAR, MPI_CHAR, env->dest[j], 2, env->glcomm, &env->s_l_requests[env->ndest * i + j]);
            }
        }
    }

    if (env->is_dl_instance) {
        for (int i = 0; i < cpl->dl_count; i++) {
            if (cpl->is_with_phy_mesh) {
                int* tmp = malloc(msh->nnode_dup * sizeof(int));
                for (int j = 0; j < msh->nnode_dup; j++) {
                    tmp[j] = msh->idx_sort[msh->idx_inverse[j]];
                    cpl->dl_field[i].array[j] = cpl->dl_field[i].array_trim[tmp[j]];
                }
                free(tmp);
            }

            int icnt = 0;
            for (int j = 0; j < env->ndest; j++) {
                icnt = (j == 0) ? 0 : icnt + cpl->sizes_list[j-1];
                MPI_Isend(cpl->dl_field[i].array + icnt, cpl->sizes_list[j], MPI_DOUBLE, env->dest[j], 1, env->glcomm, &env->s_requests[env->ndest * i + j]);
                MPI_Isend(cpl->dl_field[i].label, ML_CHAR, MPI_CHAR, env->dest[j], 2, env->glcomm, &env->s_l_requests[env->ndest * i + j]);
            }
        }
    }
}


/******************************************************************************
 * \brief Wait of non-blocking mpi send
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL's coupling struct
 * \param msh_t* PhyDLL's mesh struct
******************************************************************************/
void kernel_wait_isend(env_t* env, cpl_t* cpl, msh_t* msh) {
    MPI_Status status[env->s_nops];
    MPI_Status lstatus[env->s_nops];

    MPI_Waitall(env->s_nops, env->s_requests, &status[0]);
    MPI_Waitall(env->s_nops, env->s_l_requests, &lstatus[0]);

    free(env->s_requests);
    free(env->s_l_requests);

    char msg[LL_CHAR];
    if (env->is_phy_instance) sprintf(msg, "(PhyDLL:PHY) ----> SEND...>>>... Physical fields ...done\n");
    else if (env->is_dl_instance) sprintf(msg, "(PhyDLL:DL) ----> SEND...>>>... DL fields ...done\n");
    io_log(env, msg);

    // @dbg
    if (env->is_phy_instance) {
        for (int i = 0; i < cpl->phy_count; i++)
                io_log_dbg_arr(env, cpl->phy_field[i].array, cpl->size, cpl->phy_field[i].label, __func__, __LINE__);
    }

    // @dbg
    else if (env->is_dl_instance) {
        for (int i = 0; i < cpl->dl_count; i++)
            io_log_dbg_arr(env, cpl->dl_field[i].array, cpl->size, cpl->dl_field[i].label, __func__, __LINE__);
    }

#ifdef HDF5
    if (env->is_dl_instance && cpl->is_with_phy_mesh && _kernel_is_output_ite(cpl)) {
        io_save_fields(env, cpl, msh);
    }
#endif
}


/******************************************************************************
 * \brief Set physical/dl counter to zero
 * \param cpl_t* PhyDLL's coupling struct
******************************************************************************/
void kernel_zero_ic(cpl_t* cpl) {
    cpl->phy_ic = 0;
    cpl->dl_ic = 0;
}


/******************************************************************************
 * \brief Receive fields
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL’s coupling struct
******************************************************************************/
void kernel_irecv_field(env_t* env, cpl_t* cpl) {
    env->r_nops = IINIT;
    if (env->is_phy_instance) env->r_nops = env->ndest * cpl->dl_count;
    else if (env->is_dl_instance) env->r_nops = env->ndest * cpl->phy_count;

    env->r_requests = (MPI_Request*) malloc(env->r_nops * sizeof(MPI_Request));
    env->r_l_requests = (MPI_Request*) malloc(env->r_nops * sizeof(MPI_Request));

    if (env->is_phy_instance) {
        for (int i = 0; i < cpl->dl_count; i++) {
            for (int j = 0; j < env->ndest; j++) {
                MPI_Irecv(cpl->dl_field[i].array + j, cpl->size, MPI_DOUBLE, env->dest[j], 1, env->glcomm, &env->r_requests[env->ndest * i + j]);
                MPI_Irecv(cpl->dl_field[i].label, ML_CHAR, MPI_CHAR, env->dest[j], 2, env->glcomm, &env->r_l_requests[env->ndest * i + j]);
            }
        }
    }

    if (env->is_dl_instance) {
        for (int i = 0; i < cpl->phy_count; i++) {
            int jcnt = 0;
            for (int j = 0; j < env->ndest; j++) {
                jcnt = (j == 0) ? 0 : jcnt + cpl->sizes_list[j-1];
                MPI_Irecv(cpl->phy_field[i].array + jcnt, cpl->sizes_list[j], MPI_DOUBLE, env->dest[j], 1, env->glcomm, &env->r_requests[env->ndest * i + j]);
                MPI_Irecv(cpl->phy_field[i].label, ML_CHAR, MPI_CHAR, env->dest[j], 2, env->glcomm, &env->r_l_requests[env->ndest * i + j]);
            }
        }
    }
}


/******************************************************************************
 * \brief Wait for non-blocking mpi receive
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL's coupling struct
 * \param msh_t* PhyDLL's mesh struct
******************************************************************************/
void kernel_wait_irecv(env_t* env, cpl_t* cpl, msh_t* msh) {

    MPI_Status status[env->r_nops];
    MPI_Status lstatus[env->r_nops];

    MPI_Waitall(env->r_nops, env->r_requests, &status[0]);
    MPI_Waitall(env->r_nops, env->r_l_requests, &lstatus[0]);

    free(env->r_requests);
    free(env->r_l_requests);

    // @hc
    if (env->is_dl_instance && cpl->is_with_phy_mesh) {
        for (int i = 0; i < cpl->phy_count; i++) {
            for (int j = 0; j < msh->nnode; j++) {
                cpl->phy_field[i].array_trim[j] = cpl->phy_field[i].array[msh->idx_unique[j]];
            }
        }
    }

    char msg[LL_CHAR];
    if (env->is_phy_instance) sprintf(msg, "(PhyDLL:PHY) ----> RECV...<<<... DL fields ...done\n");
    else if (env->is_dl_instance) sprintf(msg, "(PhyDLL:DL) ----> RECV...<<<... Physical fields ...done\n");
    io_log(env, msg);

    // @dbg
    if (env->is_phy_instance) {
        for (int i = 0; i < cpl->dl_count; i++)
            io_log_dbg_arr(env, cpl->dl_field[i].array, cpl->size, cpl->dl_field[i].label, __func__, __LINE__);
    }

    // @dbg
    else if (env->is_dl_instance) {
       for (int i = 0; i < cpl->phy_count; i++) {
            if (cpl->is_with_phy_mesh) {
                io_log_dbg_arr(env, cpl->phy_field[i].array_trim, msh->nnode, cpl->phy_field[i].label, __func__, __LINE__);
            }
            else {
                io_log_dbg_arr(env, cpl->phy_field[i].array, cpl->size, cpl->phy_field[i].label, __func__, __LINE__);
            }
       }
    }

    // @hc
#ifdef HDF5
    if (env->is_phy_instance && cpl->is_with_phy_mesh && _kernel_is_output_ite(cpl)) {
        io_save_fields(env, cpl, msh);
    }
#endif
}


/******************************************************************************
 * \brief 1. Broadcast signal to stop coupling
 * \brief 2. Free memory
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL’s coupling struct
******************************************************************************/
void kernel_finalize(env_t* env, cpl_t* cpl) {

    if (env->is_phy_instance && cpl->is_with_loop) {
        cpl->phy_ite = -1;
        kernel_bcast_signal(env, cpl);
    }

#ifdef HDF5
    if (cpl->is_with_phy_mesh) {
        io_close_xdmf_collec(env);
    }
#endif

    free(env->dest);
    free(cpl->phy_field);
    free(cpl->dl_field);

    char msg[LL_CHAR];
    if (env->is_phy_instance) sprintf(msg, "(PhyDLL:PHY) ----> Finalize... ...done\n");
    else if (env->is_dl_instance) sprintf(msg, "(PhyDLL:DL) ----> Finalize... ...done\n");
    io_log(env, msg);
}


/******************************************************************************
 * \brief Set physical solver mesh for the coupling
 * \param env_t* PhyDLL's environment struct
 * \param mesh_t* PhyDLL's mesh struct
 * \param int geodim: Geometric dimension
 * \param int ncell: Local number of cells/elements
 * \param int nnode: Local number of nodes
 * \param int ntcell: Total number of cells in full mesh
 * \param int ntnode: Total number of nodes in full mesh
 * \param int nvert: Number of vertices per cell/element
 * \param int** connec: Local connectivity table
 * \param double** coords: Local node coordinates [x0,y0,z0, ... ,xN,yN,zN]
 * \param int** Table of indexes of local element to global
 * \param int** Table of indexes of local node to global
******************************************************************************/
void kernel_set_phy_mesh(env_t* env, msh_t* msh, int geodim, int ncell, int nnode, \
                        int ntcell, int ntnode, int nvert, int** connec, double** coords, \
                        int** local_cell_to_global, int** local_node_to_global)
{
    int* ibuff;
    double* rbuff;

    msh->geodim = geodim;
    msh->ncell = ncell;
    msh->nnode = nnode;
    msh->ntcell = ntcell;
    msh->ntnode = ntnode;
    msh->nvert = nvert;

    ibuff = *connec;
    msh->connec = (int*) malloc(msh->nvert * msh->ncell * sizeof(int));
    for (int i = 0; i < msh->nvert * msh->ncell; i++) {
        msh->connec[i] = ibuff[i];
    }

    rbuff = *coords;
    msh->coords = (double*) malloc(msh->geodim * msh->nnode * sizeof(double));
    for (int i = 0; i < msh->geodim * msh->nnode; i++) {
        msh->coords[i] = rbuff[i];
    }

    ibuff = *local_cell_to_global;
    msh->local_cell_to_global = (int*) malloc(msh->ncell * sizeof(int));
    for (int i = 0; i < msh->ncell; i++) {
        msh->local_cell_to_global[i] = ibuff[i];
    }

    ibuff = *local_node_to_global;
    msh->local_node_to_global = (int*) malloc(msh->nnode * sizeof(int));
    for (int i = 0; i < msh->nnode; i++) {
        msh->local_node_to_global[i] = ibuff[i];
    }

    _kernel_get_mesh_topology(msh);

    // @dbg
    char msg[LL_CHAR];
    sprintf(msg, "ncell = %d, nnode = %d\n", msh->ncell, msh->nnode); io_log_dbg(env, msg);

    // sprintf(msg, "%s\n", msh->topology_type); io_log_dbg(env, msg);
    // sprintf(msg, "geodim = %d\n", msh->geodim); io_log_dbg(env, msg);
    // sprintf(msg, "ncell = %d\n", msh->ncell); io_log_dbg(env, msg);
    // sprintf(msg, "nnode = %d\n", msh->nnode); io_log_dbg(env, msg);
    // sprintf(msg, "ntcell = %d\n", msh->ntcell); io_log_dbg(env, msg);
    // sprintf(msg, "ntnode = %d\n", msh->ntnode); io_log_dbg(env, msg);
    // sprintf(msg, "nvert = %d\n", msh->nvert); io_log_dbg(env, msg);
    // if (env->comm_rank == 0) {
    //     printf("coords = [");
    //     for (int i = 0; i < msh->geodim*msh->nnode; i++) {
    //         printf("%6.3f, ", msh->coords[i]);
    //     }
    //     printf("]\n");
    // }
    // io_log_dbg_arr(env, msh->coords, msh->geodim*msh->nnode, "coords", __func__, __LINE__);
}


/******************************************************************************
 * \brief Send physical solver mesh to DL engine
 * \param env_t* PhyDLL's environment struct
 * \param msh_t* PhyDLL's mesh struct
******************************************************************************/
void kernel_send_phy_mesh(env_t* env, msh_t* msh) {

    _kernel_bcast_mesh_info(env, msh);
    const int cm_n = 4;
    MPI_Request requests[cm_n];
    MPI_Status statuses[cm_n];

    // Connectivity
    MPI_Isend(msh->connec, msh->ncell*msh->nvert, MPI_INT, *env->dest, 70, env->glcomm, &requests[0]);

    // Coordinates
    MPI_Isend(msh->coords, msh->nnode*msh->geodim, MPI_DOUBLE, *env->dest, 71, env->glcomm, &requests[1]);

    // Local cell to global
    MPI_Isend(msh->local_cell_to_global, msh->ncell, MPI_INT, *env->dest, 72, env->glcomm, &requests[2]);

    // Local node to global
    MPI_Isend(msh->local_node_to_global, msh->nnode, MPI_INT, *env->dest, 73, env->glcomm, &requests[3]);

    // Wait
    MPI_Waitall(cm_n, requests, &statuses[0]);
}


void kernel_agg_phy_mesh(env_t* env, cpl_t* cpl, msh_t* msh) {
    // Geometric dimension
    _kernel_bcast_mesh_info(env, msh);

    // @dbg
    char msg[LL_CHAR];
    sprintf(msg, "msh->geodim = %d\n", msh->geodim); io_log_dbg(env, msg);
    sprintf(msg, "msh->ntcell = %d\n", msh->ntcell); io_log_dbg(env, msg);
    sprintf(msg, "msh->ntnode = %d\n", msh->ntnode); io_log_dbg(env, msg);
    sprintf(msg, "msh->nvert = %d\n", msh->nvert); io_log_dbg(env, msg);
    sprintf(msg, "msh->topology_type = %s\n", msh->topology_type); io_log_dbg(env, msg);

    int const cm_n = 4;
    MPI_Request requests[cm_n * env->ndest];
    MPI_Status statuses[cm_n * env->ndest];

    int* ncell_list;
    int** connec_list;
    ncell_list = (int*) malloc(env->ndest * sizeof(int));
    connec_list = (int**) malloc(env->ndest * sizeof(int*));

    int* nnode_list;
    double** coords_list;
    nnode_list = (int*) malloc(env->ndest * sizeof(int));
    coords_list = (double**) malloc(env->ndest * sizeof(double));

    int** local_cell_to_global_list;
    local_cell_to_global_list = (int**) malloc(env->ndest * sizeof(int*));

    int** local_node_to_global_list;
    local_node_to_global_list = (int**) malloc(env->ndest * sizeof(int*));

    for (int i = 0; i < env->ndest; i++) {
        MPI_Status _status;
        int _cnt;

        // List of connectivities
        MPI_Probe(env->dest[i], 70, env->glcomm, &_status);
        MPI_Get_count(&_status, MPI_INT, &_cnt);
        ncell_list[i] = _cnt / msh->nvert;
        connec_list[i] = (int*) malloc(_cnt * sizeof(int));
        MPI_Irecv(connec_list[i], _cnt, MPI_INT, env->dest[i], 70, env->glcomm, &requests[cm_n*i]);

        // List of tables of coordinates
        MPI_Probe(env->dest[i], 71, env->glcomm, &_status);
        MPI_Get_count(&_status, MPI_DOUBLE, &_cnt);
        nnode_list[i] = _cnt / msh->geodim;
        coords_list[i] = (double*) malloc(_cnt * sizeof(double));
        MPI_Irecv(coords_list[i], _cnt, MPI_DOUBLE, env->dest[i], 71, env->glcomm, &requests[cm_n*i + 1]);

        // List of tables local cell to global indexes
        MPI_Probe(env->dest[i], 72, env->glcomm, &_status);
        MPI_Get_count(&_status, MPI_INT, &_cnt);
        local_cell_to_global_list[i] = (int*) malloc(_cnt * sizeof(int));
        MPI_Irecv(local_cell_to_global_list[i], _cnt, MPI_INT, env->dest[i], 72, env->glcomm, &requests[cm_n*i + 2]);

        // List of tables local node to global indexes
        MPI_Probe(env->dest[i], 73, env->glcomm, &_status);
        MPI_Get_count(&_status, MPI_INT, &_cnt);
        local_node_to_global_list[i] = (int*) malloc(_cnt * sizeof(int));
        MPI_Irecv(local_node_to_global_list[i], _cnt, MPI_INT, env->dest[i], 73, env->glcomm, &requests[cm_n*i + 3]);
    }
    MPI_Waitall(cm_n * env->ndest, requests, &statuses[0]);

    // @dbg
    io_log_dbg_arr_int(env, ncell_list, env->ndest, "ncell_list", __func__, __LINE__);
    io_log_dbg_arr_int(env, nnode_list, env->ndest, "nnode_list", __func__, __LINE__);
    // for (int i = 0; i < env->ndest; i++) {
    //     char label[ML_CHAR];
    //     sprintf(label, "connec_list_%d", i);
    //     io_log_dbg_arr_int(env, connec_list[i], ncell_list[i]*msh->nvert, label, __func__, __LINE__);
    // }

    /*
    Get duplicated and unique local partition nodes in global index
    */

    // Compute the number of partition nodes with duplicated nodes.
    msh->nnode_dup = 0;
    for (int i = 0; i < env->ndest; i++) {
        msh->nnode_dup += nnode_list[i];
    }

    // Create contiguous array of local_node_to_global_list
    int* ln2g_contg_dup;
    int k = 0;
    ln2g_contg_dup = (int*) malloc(msh->nnode_dup * sizeof(int));
    for (int i = 0; i < env->ndest; i++) {
        for (int j = 0; j < nnode_list[i]; j++) {
            ln2g_contg_dup[k] = local_node_to_global_list[i][j];
            k++;
        }
    }
    //@dbg
    io_log_dbg_arr_int(env, ln2g_contg_dup, msh->nnode_dup, "ln2g_contg_dup", __func__, __LINE__);

    int* idx_get_unique = malloc(msh->nnode_dup * sizeof(int));
    msh->idx_inverse = (int*) malloc(msh->nnode_dup * sizeof(int));
    for (int i = 0; i < msh->nnode_dup; i++) {
        idx_get_unique[i] = IINIT;
        msh->idx_inverse[i] = IINIT;
    }
    utils_unique(ln2g_contg_dup, msh->nnode_dup, idx_get_unique, msh->idx_inverse);
    // @dbg
    io_log_dbg_arr_int(env, idx_get_unique, msh->nnode_dup, "idx_get_unique", __func__, __LINE__);
    io_log_dbg_arr_int(env, msh->idx_inverse, msh->nnode_dup, "idx_inverse", __func__, __LINE__);


    // Compute the number of partition nodes without duplicated nodes.
    msh->nnode = 0;
    for (int i = msh->nnode_dup - 1; i >= 0; i--) {
        if (idx_get_unique[i] >= 0) {
            msh->nnode = i + 1;
            break;
        }
    }

    msh->idx_unique = (int*) malloc(msh->nnode * sizeof(int));
    for (int i = 0; i < msh->nnode; i++) {
        msh->idx_unique[i] = idx_get_unique[i];
    }
    utils_sort(msh->idx_unique, msh->nnode);
    free(idx_get_unique);

    int* ln2g_contg = malloc(msh->nnode * sizeof(int));
    for (int i = 0; i < msh->nnode; i++) {
        ln2g_contg[i] = ln2g_contg_dup[msh->idx_unique[i]] - 1; //@hc -1 (fortran indexing)
    }

    msh->idx_sort = (int*) malloc(msh->nnode * sizeof(int));
    for (int i = 0; i < msh->nnode; i++) {
        msh->idx_sort[i] = IINIT;
    }
    utils_argsort(ln2g_contg, msh->nnode, msh->idx_sort);

    // @dbg
    io_log_dbg_arr_int(env, msh->idx_unique, msh->nnode, "idx_unique", __func__, __LINE__);
    io_log_dbg_arr_int(env, msh->idx_sort, msh->nnode, "idx_sort", __func__, __LINE__);
    io_log_dbg_arr_int(env, ln2g_contg, msh->nnode, "ln2g_contg", __func__, __LINE__);

    // Create contiguous array of local_node_to_global_list
    double** coords_xyz = malloc(msh->geodim * sizeof(double));
    for (int l = 0; l < msh->geodim; l++) {
        coords_xyz[l] = (double*) malloc(msh->nnode_dup * sizeof(double));
    }

    for (int l = 0; l < msh->geodim; l++) {
        int k = 0;
        for (int i = 0; i < env->ndest; i++) {
            for (int j = 0; j < nnode_list[i]; j++) {
                coords_xyz[l][k] = coords_list[i][l + j * msh->geodim];
                k++;
            }
        }
    }
    msh->coords = (double*) malloc(msh->geodim * msh->nnode * sizeof(double));
    for (int l = 0; l < msh->geodim; l++) {
        for (int i = 0; i < msh->nnode; i++) {
            msh->coords[l + i * msh->geodim] = coords_xyz[l][msh->idx_unique[i]];
        }
    }
    free(coords_xyz);
    // @dbg
    io_log_dbg_arr(env, msh->coords, msh->geodim*msh->nnode, "coords", __func__, __LINE__);
    /* end */


    /*
    Compute local connectivity
    */

    // Compute the number of partition cells.
    msh->ncell = 0;
    for (int i = 0; i < env->ndest; i++) {
        msh->ncell += ncell_list[i];
    }

    int* _hash = malloc(msh->nnode * sizeof(int));
    for (int i = 0; i < msh->nnode; i++) {
        _hash[i] = ln2g_contg[i] + 1; // @hc fortran indexing?
    }

    msh->connec = (int*) malloc(msh->nvert * msh->ncell * sizeof(int));
    for (int i = 0; i < msh->nvert * msh->ncell; i++) {
        msh->connec[i] = IINIT;
    }
    k = 0;
    for (int i = 0; i < env->ndest; i++) {
        for (int j = 0; j < ncell_list[i] * msh->nvert; j++) {
            for (int l = 0; l < msh->nnode; l++) {
                if (_hash[l] == local_node_to_global_list[i][connec_list[i][j] - 1]) {
                    msh->connec[k] = l + 1;
                    break;
                }
            }
            k++;
        }
    }
    // @dbg
    io_log_dbg_arr_int(env, msh->connec, msh->nvert * msh->ncell, "connec", __func__, __LINE__);
    /*
    end
    */

    for (int i = 0; i < cpl->phy_count; i++) {
        cpl->phy_field[i].array_trim = (double*) malloc(msh->nnode * sizeof(double));
    }
    for (int i = 0; i < cpl->dl_count; i++) {
        cpl->dl_field[i].array_trim = (double*) malloc(msh->nnode * sizeof(double));
    }

}


/******************************************************************************
 * \brief PRIVATE: Broadcast field size between instances
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL’s coupling struct
******************************************************************************/
static void _kernel_bcast_field_size(env_t* env, cpl_t* cpl) {
    MPI_Request request[env->ndest];
    MPI_Status status[env->ndest];

    // Send field size (if physical solver)
    if (env->is_phy_instance) {
        for (int i = 0; i < env->ndest; i++)
            MPI_Isend(&cpl->size, 1, MPI_INT, env->dest[i], 0, env->glcomm, &request[i]);
    }

    // Recv field size (if dl engine)
    else if (env->is_dl_instance) {
        cpl->sizes_list = (int*) malloc(env->ndest * sizeof(int));
        for (int i = 0; i < env->ndest; i++)
            MPI_Irecv(cpl->sizes_list + i, 1, MPI_INT, env->dest[i], 0, env->glcomm, &request[i]);
    }

    MPI_Waitall(env->ndest, request, &status[0]);
}


/******************************************************************************
 * \brief PRIVATE: Broadcast boolean to check if the coupling is based on physical mesh
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL's coupling struct
******************************************************************************/
static void _kernel_bcast_is_with_phy_mesh(env_t* env, cpl_t* cpl) {
    MPI_Bcast(&cpl->is_with_phy_mesh, 1, MPI_C_BOOL, env->phy_bcast_root, env->glcomm);
}


/******************************************************************************
 * \brief PRIVATE: Aggregate field sizes for DL instance
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL’s coupling struct
******************************************************************************/
static void _kernel_agg_field_sizes(env_t* env, cpl_t* cpl) {
    cpl->size = 0;
    for (int i = 0; i < env->ndest; i++) {
        cpl->size += cpl->sizes_list[i];
    }
}


/******************************************************************************
 * \brief PRIVATE: Broadcast mesh information from phy_root
 * \param env_t* PhyDLL's environment struct
 * \param msh_t* PhyDLL's mesh struct
******************************************************************************/
static void _kernel_bcast_mesh_info(env_t* env, msh_t* msh) {
    // Geometric dimension
    MPI_Bcast(&msh->geodim, 1, MPI_INT, env->phy_bcast_root, env->glcomm);

    // Total number of cells
    MPI_Bcast(&msh->ntcell, 1, MPI_INT, env->phy_bcast_root, env->glcomm);

    // Total number of nodes
    MPI_Bcast(&msh->ntnode, 1, MPI_INT, env->phy_bcast_root, env->glcomm);

    // Number of vertices
    MPI_Bcast(&msh->nvert, 1, MPI_INT, env->phy_bcast_root, env->glcomm);

    // Topology type
    MPI_Bcast(&msh->topology_type, SL_CHAR, MPI_CHAR, env->phy_bcast_root, env->glcomm);
}


/******************************************************************************
 * \brief PRIVATE: Allocate buffers for send/recv
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL’s coupling struct
******************************************************************************/
static void _kernel_alloc_fields(env_t* env, cpl_t* cpl) {
    // Broadcast phy_count
    MPI_Bcast(&cpl->phy_count, 1, MPI_INT, env->phy_bcast_root, env->glcomm);

    // Broadcast dl_count
    MPI_Bcast(&cpl->dl_count, 1, MPI_INT, env->dl_bcast_root, env->glcomm);

    // Broadcast output_frequency
    MPI_Bcast(&cpl->output_freq, 1, MPI_INT, env->phy_bcast_root, env->glcomm);

    // Allocate buffers
    cpl->phy_field = (field_t *) malloc(cpl->phy_count * sizeof(field_t));
    cpl->dl_field = (field_t *) malloc(cpl->dl_count * sizeof(field_t));

    // Initialize buffers for physical fields
    for (int i = 0; i < cpl->phy_count; i++) {
        cpl->phy_field[i].array = (double*) malloc(cpl->size * sizeof(double));
        for (int j = 0; j < cpl->size; j++) {
            cpl->phy_field[i].array[j] = DINIT;
        }
        strcpy(cpl->phy_field[i].label, CINIT);
    }

    // Initialize buffers for dl fields
    for (int i = 0; i < cpl->dl_count; i++) {
        cpl->dl_field[i].array = (double*) malloc(cpl->size * sizeof(double));
        for (int j = 0; j < cpl->size; j++) {
            cpl->dl_field[i].array[j] = DINIT;
        }
        strcpy(cpl->dl_field[i].label, CINIT);
    }

    // Initialize counters
    cpl->phy_ic = 0;
    cpl->dl_ic = 0;

    // Initialize iteration numbers
    cpl->phy_ite = 0;
    cpl->ite = 0;
}


/******************************************************************************
 * \brief PRIVATE: Get mesh topology
 * \param msh_t* PhyDLL's mesh struct
******************************************************************************/
static void _kernel_get_mesh_topology(msh_t* msh) {
    if (msh->nvert == 3) {
        strcpy(msh->topology_type, "Triangle");
    }

    else if (msh->nvert == 4 && msh->geodim == 2) {
        strcpy(msh->topology_type, "Quadrilateral");
    }

    else if (msh->nvert == 4 && msh->geodim == 3) {
        strcpy(msh->topology_type, "Tetrahedron");
    }

    else if (msh->nvert == 6) {
        strcpy(msh->topology_type, "Wedge");
    }

    else if (msh->nvert == 8) {
        strcpy(msh->topology_type, "Hexahedron");
    }
}


/******************************************************************************
 * \brief Check if it's a coupling iteration
 * \param cpl_t* PhyDLL's coupling struct
******************************************************************************/
static bool _kernel_is_cpl_ite(cpl_t* cpl) {
    bool check = false;
    if (cpl->freq > 0 && (cpl->freq + cpl->phy_ite - 1) % (cpl->freq) == 0) {
        check = true;
    }
    return check;
}


/******************************************************************************
 * \brief Check if it's an output iteration
 * \param cpl_t* PhyDLL's coupling struct
******************************************************************************/
static bool _kernel_is_output_ite(cpl_t* cpl) {
    bool check = false;
    if (cpl->output_freq > 0 && (cpl->output_freq + cpl->ite - 1) % (cpl->output_freq) == 0) {
        check = true;
    }
    return check;
}
