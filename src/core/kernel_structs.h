/******************************************************************************
 * \headerfile src/core/kernel_structs.h
 * \brief Header file of PhyDLL's kernel structures
 * \authors A. Serhani, C. Lapeyre, G. Staffelbach
 * \mainpage phydll.readthedocs.io
 * \remark phydll@cerfacs.fr
 * \date Tue, Apr 11, 2023
 * \copyright CeCILL-B FREE SOFTWARE LICENSE AGREEMENT
 * \copyright COPYRIGHT (C) [2023] [CERFACS]
******************************************************************************/
#ifndef KERNEL_STRUCTS_HEADER
#define KERNEL_STRUCTS_HEADER

#include <mpi.h>
#include <stdbool.h>

#include "params.h"


/******************************************************************************
 * \brief PhyDLL’s environment struct
******************************************************************************/
typedef struct env {
    char instance[ML_CHAR];     // Instance type (physical or dl)
    bool is_phy_instance;       // Check if the current instance is the physical solver
    bool is_dl_instance;        // Check if the current instance is the dl engine

    MPI_Comm glcomm;            // Global communicator (Phy+DL) = MPI_COMM_WORLD
    int glcomm_size;            // Size of global communicator (glcomm)
    int glcomm_rank;            // Rank in global communicator (glcomm)

    MPI_Comm comm;              // Local communicator (Physical solver only)
    int comm_size;              // Size of local communicator (comm)
    int comm_rank;              // Rank in local communicator (comm)

    int host_rank;              // Host rank in glcomm
    int comm_hrank;             // Host rank in comm

    int dist_rank;              // Distant host rank (DL master rank)
    int dist_size;              // Distant size (Size of DL comm)
    int* dest;                  // Corresponding destination ranks
    int ndest;                  // Number of corresponding destination ranks

    int s_nops;                 // Number of sending communications
    MPI_Request *s_requests;    // MPI requests of arrays-sending communications
    MPI_Request *s_l_requests;  // MPI requests of labels-sending communications

    int r_nops;                 // Number of receiving communications
    MPI_Request *r_requests;    // MPI requests of arrays-receiving communications
    MPI_Request *r_l_requests;  // MPI requests of labels-receiving communications

    int phy_bcast_root;         // Root rank of broadcasting from physical solver
    int dl_bcast_root;          // Root rank of broadcasting from dl engine
} env_t;

// env_t initialization signature
void env_init(env_t* env);


/******************************************************************************
 * \brief PhyDLL’s kernel field struct
******************************************************************************/
typedef struct field {
    double* array;          // Double precision array of single field
    double* array_trim;     // Double precision array of single field (without duplicated nodes for coupling with physical mesh)
    char label[ML_CHAR];    // Label of the field
} field_t;


/******************************************************************************
 * \brief PhyDLL’s kernel coupling struct
******************************************************************************/
typedef struct cpl {
    field_t* phy_field;     // PhyDLL’s physical fields
    field_t* dl_field;      // PhyDLL’s dl fields
    int size;               // Size of field
    int* sizes_list;        // Size list for DL engine (when aggregated)
    int phy_count;          // Physical fields count
    int dl_count;           // DL fields count

    int phy_ite;            // Current physical solver iteration
    int ite;                // Current coupling iteration
    bool is_phy_signal;     // Signal of physical solver

    int phy_ic;             // Counter of physical fields
    int dl_ic;              // Counter of dl fields

    int freq;               // Coupling frequency
    bool is_cpl_ite;        // Check if it is a coupling iteration (if loop mode is enabled)
    int output_freq;        // Output exchanged fields frequency

    bool is_with_loop;      // Is the coupling with loop
    bool is_with_phy_mesh;  // Is the coupling will be based on physical mesh
} cpl_t;

// cpl_t initialization signature
void cpl_init(cpl_t* cpl);


/******************************************************************************
 * \brief PhyDLL’s kernel mesh struct
******************************************************************************/
typedef struct msh {
    int geodim;                     // Geometric dimension
    int ncell;                      // Local number of cells/elements
    int nnode;                      // Local number of nodes
    int ntcell;                     // Total number of cells in full mesh
    int ntnode;                     // Total number of nodes in full mesh

    int nvert;                      // Number of vertices per cell
    char topology_type[SL_CHAR];    // Mesh element topology type}

    int* connec;                    // Local connectivity
    int* connecindex;               // Table of local connectivity indexes
    double* coords;                 // Local nodes coordinates

    int* local_cell_to_global;      // Table of local element to global
    int* local_node_to_global;      // Table of local node to global

    int nnode_dup;                  // AGGMESH: Number of nodes with duplicated ones.
    int* idx_unique;                // AGGMESH
    int* idx_inverse;               // AGGMESH
    int* idx_sort;                  // AGGMESH

} msh_t;

// msh_t initialization signature
void msh_init(msh_t* mesh);


#endif
