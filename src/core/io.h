/******************************************************************************
 * \headerfile src/core/io.h
 * \brief Header file of PhyDLL’s IO struct and functions
 * \authors A. Serhani, C. Lapeyre, G. Staffelbach
 * \mainpage phydll.readthedocs.io
 * \remark phydll@cerfacs.fr
 * \date Tue, Apr 11, 2023
 * \copyright CeCILL-B FREE SOFTWARE LICENSE AGREEMENT
 * \copyright COPYRIGHT (C) [2023] [CERFACS]
******************************************************************************/
#include "kernel_structs.h"


// IO structure
typedef struct io {
    FILE* logfile;
    char logfile_name[ML_CHAR];
} io_t;


// Log coupling information
void io_create_logfile(env_t* env, cpl_t* cpl, io_t* io);
void io_log_mesh_info(env_t* env, msh_t* msh, io_t* io);


// Low level log functions
void io_log(env_t* env, char msg[]);
void io_logall(env_t* env, char msg[]);
void io_log_dbg(env_t* env, char msg[]);
void io_log_dbg_arr(env_t* env, double* array, int size, char label[], const char func[], int line);
void io_log_dbg_arr_int(env_t* env, int* array, int size, char label[], const char func[], int line);


// Functions to write mesh and fields
#ifdef HDF5
void io_save_fields(env_t* env, cpl_t* cpl, msh_t* msh);
void io_close_xdmf_collec(env_t* env);
#endif
