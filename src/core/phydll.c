/******************************************************************************
 * \file src/core/phydll.c
 * \brief PhyDLL’s C interface
 * \authors A. Serhani, C. Lapeyre, G. Staffelbach
 * \mainpage phydll.readthedocs.io
 * \remark phydll@cerfacs.fr
 * \date Wed, Apr 12, 2023
 * \copyright CeCILL-B FREE SOFTWARE LICENSE AGREEMENT
 * \copyright COPYRIGHT (C) [2023] [CERFACS]
******************************************************************************/
#include <mpi.h>
#include <stdio.h>

#include "kernel.h"
#include "io.h"

// PhyDLL’s data structures
env_t env;
cpl_t cpl;
msh_t msh;
io_t io;


/******************************************************************************
 * \brief Initiliaze PhyDLL
 * \param char Instance ("physical", "Physical", "phy", "Phy", "dl", "deeplearning", "DL", "DeepLearning")
 * \param MPI_Comm* MPI global communicator
 * \param MPI_Comm* MPI local communicator
******************************************************************************/
void phydll_init(char instance[]) { //@hc , MPI_Comm *glcomm, MPI_Comm *comm) {
    // Kernel initialization
    kernel_init(&env, &cpl, instance);
    fprintf(stderr, "[PHYDLL:CORE] phydll_init instance=%s kernel_init complete gl_rank=%d gl_size=%d comm_rank=%d comm_size=%d\n",
            instance, env.glcomm_rank, env.glcomm_size, env.comm_rank, env.comm_size);
    fflush(stderr);

    // Print welcome message in STDOUT
    io_log(&env, "*******************************************************************************\n");
    io_log(&env, "************************** <<< Welcome to PhyDLL >>> **************************\n");
    io_log(&env, "*******************************************************************************\n");

    // Create logfile
    io_create_logfile(&env, &cpl, &io);
    fprintf(stderr, "[PHYDLL:CORE] phydll_init instance=%s logfile complete\n", instance);
    fflush(stderr);

    // Create processes mapping for DS
    kernel_ds_mapping(&env);
    fprintf(stderr, "[PHYDLL:CORE] phydll_init instance=%s mapping complete ndest=%d\n", instance, env.ndest);
    fflush(stderr);
}


/******************************************************************************
 * \brief Get MPI communicator as Fortran Integer
******************************************************************************/
MPI_Fint phydll_get_local_mpi_fcomm() {
    MPI_Fint comm_f;
    comm_f = kernel_get_fcomm(&env);
    return comm_f;
}


/******************************************************************************
 * \brief Get local MPI communicator
******************************************************************************/
MPI_Comm phydll_get_local_mpi_comm() {
    MPI_Comm comm = MPI_COMM_NULL;
    MPI_Comm_dup(env.comm, &comm);
    return comm;
}


/******************************************************************************
 * \brief Finalize PhyDLL
******************************************************************************/
void phydll_finalize() {
    kernel_finalize(&env, &cpl);
}


/******************************************************************************
 * \brief Define PhyDLL’s physical solver instance
 * \param int Number of Physical fields to send
 * \param int Length of Physical field (or number of mesh nodes)
******************************************************************************/
void phydll_define_phy(int count, int size) {
    cpl.is_with_phy_mesh = false;
    kernel_alloc_phy_fields(&env, &cpl, count, size);
}


/******************************************************************************
 * \brief Define PhyDLL’s coupling with physical solver mesh
 * \param int Number of Physical fields to send
 * \param int Geometric dimension
 * \param int Number of local mesh cells
 * \param int Number of local mesh nodes
 * \param int Number of global (full) mesh cells
 * \param int Number of global (full) mesh nodes (without duplication)
 * \param int Number of nodes per element (eg. quad=4, tetra=4, hexa=8, prism=6, ...)
 * \param int** Local connectivity table (element to node), len=nvert*ncell
 * \param double** Local coordinates table, len=geodim*nnode
 * \param int** Table of local to global cell numerotation, len=ncell
 * \param int** Table of local to global node numerotation, len=nnode
******************************************************************************/
void phydll_define_phy_with_mesh(int count, int geodim, int ncell, int nnode, int ntcell, \
                                int ntnode, int nvert, int** connec, double** coords, \
                                int** local_cell_to_global, int** local_node_to_global)
{
    cpl.is_with_phy_mesh = true;
    kernel_alloc_phy_fields(&env, &cpl, count, nnode);

    kernel_set_phy_mesh(&env, &msh, geodim, ncell, nnode, ntcell, ntnode, nvert, \
                        connec, coords, local_cell_to_global, local_node_to_global);

    kernel_send_phy_mesh(&env, &msh);
}


/******************************************************************************
 * \brief Define PhyDLL’s DL instance
 * \param int Number of DL fields to send
******************************************************************************/
void phydll_define_dl(int count) {
    kernel_alloc_dl_fields(&env, &cpl, count);

    if (cpl.is_with_phy_mesh) {
        kernel_agg_phy_mesh(&env, &cpl, &msh);
        io_log_mesh_info(&env, &msh, &io);
    }
}


/******************************************************************************
 * \brief Non-blocking send fields (from PhyDLL’s buffer)
******************************************************************************/
void phydll_isend() {
    kernel_isend_field(&env, &cpl, &msh);
}


/******************************************************************************
 * \brief Waiting for non-blocking send fields
******************************************************************************/
void phydll_wait_isend() {
    kernel_zero_ic(&cpl);
    kernel_wait_isend(&env, &cpl, &msh);
}


/******************************************************************************
 * \brief Send fields (from PhyDLL’s buffer)
******************************************************************************/
void phydll_send() {
    phydll_isend();
    phydll_wait_isend();
}


/******************************************************************************
 * \brief Non-blocking recv fields (into PhyDLL’s buffer)
******************************************************************************/
void phydll_irecv() {
    kernel_zero_ic(&cpl);
    kernel_irecv_field(&env, &cpl);
}


/******************************************************************************
 * \brief Waiting for non-blocking recv fields
******************************************************************************/
void phydll_wait_irecv() {
    kernel_wait_irecv(&env, &cpl, &msh);
}


/******************************************************************************
 * \brief Recv fields (into PhyDLL’s buffer)
******************************************************************************/
void phydll_recv() {
    phydll_irecv();
    phydll_wait_irecv();
}


/******************************************************************************
 * \brief Set PhyDLL’s field to send (accumulative)
 * \param double** Field to send
 * \param char[] Label of field
******************************************************************************/
void phydll_set_field(double** field, char label[]) {
    kernel_set_field(&env, &cpl, field, label);
}


/******************************************************************************
 * \brief Get PhyDLL’s received field (accumulative)
 * \param double** Received field
 * \param char[] Label of field
******************************************************************************/
void phydll_get_field(double** field, char label[]) {
    kernel_get_field(&env, &cpl, field, label);
}


/******************************************************************************
 * \brief Get field size
 * \param int* size
******************************************************************************/
void phydll_get_field_size(int* size) {
    kernel_get_field_size(&cpl, &msh, size);
}


/******************************************************************************
 * \brief Get fields counts
 * \param int* Physical fields count
 * \param int* DL fields count
******************************************************************************/
void phydll_get_field_counts(int* phy_count, int* dl_count) {
    kernel_get_field_counts(&cpl, phy_count, dl_count);
}


/******************************************************************************
 * \brief Get DL host (master) rank
 * \return Integer 
******************************************************************************/
int phydll_get_dist_rank() {
    return env.dist_rank;
}


/******************************************************************************
 * \brief Get Distant size (Size of DL comm)
 * \return Integer
******************************************************************************/
int phydll_get_dist_size() {
    return env.dist_size;
}


/******************************************************************************
 * \brief Get list of DL process ranks this Phy process sends to 
 * \return List of Integers
******************************************************************************/
int* phydll_get_dest() {
    return env.dest;
}


/******************************************************************************
 * \brief Get number of DL processes this Phy process sends to
 * \return Integer
******************************************************************************/
int phydll_get_ndest() {
    return env.ndest;
}


/******************************************************************************
 * \brief Check if Physical solver is sending data
 * \return Boolean signal
******************************************************************************/
bool phydll_is_phy_signal() {
    kernel_bcast_signal(&env, &cpl);
    return cpl.is_phy_signal;
}


/******************************************************************************
 * \brief Check if current instance is Physical solver
 * \return boolean status
******************************************************************************/
bool phydll_is_phy_instance() {
    return env.is_phy_instance;
}


/******************************************************************************
 * \brief Check if current instance is DL engine
 * \return boolean status
******************************************************************************/
bool phydll_is_dl_instance() {
    return env.is_dl_instance;
}


/******************************************************************************
 * \brief Get current physical solver iteration
 * \return int physical iteration
******************************************************************************/
int phydll_get_phy_ite() {
    return cpl.phy_ite;
}


/******************************************************************************
 * \brief Get current coupling solver iteration
 * \return int coupling iteration
******************************************************************************/
int phydll_get_ite() {
    return cpl.ite;
}


/******************************************************************************
 * \brief Optionally Enable coupling in loop mode
 * \brief It should be associated with the function phydll_is_phy_signal()
******************************************************************************/
void phydll_opt_enable_cpl_loop() {
    cpl.is_with_loop = true;

    char msg[ML_CHAR];
    sprintf(msg, "(PhyDLL) ----> OPTION: Coupling with loop = True\n");
    io_log(&env, msg);
}


/******************************************************************************
 * \brief Optionally set coupling frequency in loop mode
 * \brief Default value = 1
 * \param int Coupling frequency
******************************************************************************/
void phydll_opt_set_freq(int freq) {
    cpl.freq = freq;

    char msg[ML_CHAR];
    sprintf(msg, "(PhyDLL) ----> OPTION: Coupling frequency = %d\n", cpl.freq);
    io_log(&env, msg);
}


/******************************************************************************
 * \brief Optionally set output frequency (saving fields frequency)
 * \brief Default value = 1
 * \param int Output frequency
******************************************************************************/
void phydll_opt_set_output_freq(int output_freq) {
    cpl.output_freq = output_freq;

    char msg[ML_CHAR];
    sprintf(msg, "(PhyDLL) ----> OPTION: Output (mesh/fields) frequency = %d\n", cpl.output_freq);
    io_log(&env, msg);
}
