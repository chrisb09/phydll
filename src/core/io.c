/******************************************************************************
 * \file src/core/io.c
 * \brief PhyDLL’s IO struct and functions
 * \authors A. Serhani, C. Lapeyre, G. Staffelbach
 * \mainpage phydll.readthedocs.io
 * \remark phydll@cerfacs.fr
 * \date Tue, Apr 11, 2023
 * \copyright CeCILL-B FREE SOFTWARE LICENSE AGREEMENT
 * \copyright COPYRIGHT (C) [2023] [CERFACS]
******************************************************************************/
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <mpi.h>
#include <time.h>

#ifdef HDF5
#include <hdf5.h>
#endif

#include "params.h"
#include "kernel_structs.h"
#include "io.h"

#define DEBUG 0


/******************************************************************************
 * \brief Create the log file and write header coupling information
 * \brief It is called by the DL instance only
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL's coupling struct
 * \param io_t* PhyDLL's io struct
******************************************************************************/
void io_create_logfile(env_t* env, cpl_t* cpl, io_t* io) {
    if (env->is_dl_instance) {
        char* slurm_jobid = getenv("SLURM_JOBID");
        sprintf(io->logfile_name, "phydll-%s.log", slurm_jobid);

        if (env->comm_rank == env->comm_hrank) {
            char text[LL_CHAR];
            io->logfile = fopen(io->logfile_name, "w");

            time_t tm;
            time(&tm);
            sprintf(text, "%s", ctime(&tm)); fputs(text, io->logfile);
            sprintf(text, "JOBID = %s\n", slurm_jobid); fputs(text, io->logfile);

            sprintf(text, " _______________________________________ \n"); fputs(text, io->logfile);
            sprintf(text, "|    _____         ____  __    __       |\n"); fputs(text, io->logfile);
            sprintf(text, "|   |  __ \\       | __ \\ | |   | |      |\n"); fputs(text, io->logfile);
            sprintf(text, "|   | |__) |      | | \\ \\| |   | |      |\n"); fputs(text, io->logfile);
            sprintf(text, "|   |  ___/|      | |  | | |   | |      |\n"); fputs(text, io->logfile);
            sprintf(text, "|   | |    |__\\  /| |_/ /| |__ | |__    |\n"); fputs(text, io->logfile);
            sprintf(text, "|   |_|    |  |\\/ |____/ |____||____|   |\n"); fputs(text, io->logfile);
            sprintf(text, "|              /                        |\n"); fputs(text, io->logfile);
            sprintf(text, "|             /                         |\n"); fputs(text, io->logfile);
            sprintf(text, "|  << Physics Deep Learning coupLer >>  |\n"); fputs(text, io->logfile);
            sprintf(text, "|  phydll@cerfacs.fr       CERFACS(C)   |\n"); fputs(text, io->logfile);
            sprintf(text, "|_______________________________________|\n"); fputs(text, io->logfile);

            sprintf(text, "PHY program lang = %s\n", "..."); fputs(text, io->logfile);
            sprintf(text, "DL program lang = %s\n\n", "..."); fputs(text, io->logfile);

            sprintf(text, "PHY MPI comm size = %d\n", env->dist_size); fputs(text, io->logfile);
            sprintf(text, "DL MPI comm size = %d\n", env->comm_size); fputs(text, io->logfile);
            sprintf(text, "Coupling scheme = %d\n\n", cpl->is_with_phy_mesh); fputs(text, io->logfile);

            fclose(io->logfile);
        }
    }
}


/******************************************************************************
 * \brief Write mesh information on the log file
 * \brief It is called by the DL instance only
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL's coupling struct
 * \param msh_t* PhyDLL's mesh struct
 * \param io_t* PhyDLL's io struct
******************************************************************************/
void io_log_mesh_info(env_t* env, msh_t* msh, io_t* io) {
    if (env->is_dl_instance) {
        io->logfile = fopen(io->logfile_name, "a");
        char text[LL_CHAR];

        MPI_Barrier(env->comm);
        if (env->comm_rank == env->comm_hrank) {
            sprintf(text, "MESH INFORMATIONS\n"); fputs(text, io->logfile);
            sprintf(text, "\tGeometric dim = %dD\n", msh->geodim); fputs(text, io->logfile);
            sprintf(text, "\tTopology = %s\n", msh->topology_type); fputs(text, io->logfile);
            sprintf(text, "\tntcell = %d \t\ttotal number of mesh cells (all partitions)\n", msh->ntcell); fputs(text, io->logfile);
            sprintf(text, "\tntnode = %d \t\ttotal number of mesh nodes (all partitions without dup)\n", msh->ntnode); fputs(text, io->logfile);
            sprintf(text, "\tnvert/cell = %d \tnumber of vertices per unit cell\n\n", msh->nvert); fputs(text, io->logfile);

            sprintf(text, "\t%s%*s%s%*s%s\n", "MPI_rank", 5, " ", "ncell", 5, " ", "nnode"); fputs(text, io->logfile);
        }
        MPI_Barrier(env->comm);
        sprintf(text, "\t%d%13d\t%9d\n", env->comm_rank, msh->ncell, msh->nnode); fputs(text, io->logfile);

        MPI_Barrier(env->comm);
        fclose(io->logfile);
    }
}


/******************************************************************************
 * \brief Generic function to write, by the hostrank, a message on the stdout
 * \param env_t* PhyDLL's environment struct
 * \param char Message to write
******************************************************************************/
void io_log(env_t* env, char msg[]) {
    MPI_Barrier(env->comm);
    if (env->comm_rank == env->comm_hrank) printf("%s", msg);
    MPI_Barrier(env->comm);
}


/******************************************************************************
 * \brief Generic function to write, by all ranks, a message on the stdout file
 * \param env_t* PhyDLL's environment struct
 * \param char Message to write
******************************************************************************/
void io_logall(env_t* env, char msg[]) {
    MPI_Barrier(env->comm);
    printf("%s", msg);
    MPI_Barrier(env->comm);
}


/******************************************************************************
 * \brief Function to write, by all ranks, DEBUG message on the stdout file
 * \param env_t* PhyDLL's environment struct
 * \param char Message to write
******************************************************************************/
void io_log_dbg(env_t* env, char msg[]) {
    if (DEBUG == 1) {
        printf("/!\\ %s /!\\ %d/%d:    %s", env->instance, env->comm_rank, env->comm_size-1, msg);
    }
}


/******************************************************************************
 * \brief Function to write, by all ranks, a double precision array on the stdout
 * \param env_t* PhyDLL's environment struct
 * \param double* Double precision array to write
 * \param int Size of the array
 * \param char Label of the array
 * \param const char Function from which the array was written (__FUNC__)
 * \param int Line from which the array was written (__line__)
******************************************************************************/
void io_log_dbg_arr(env_t* env, double* array, int size, char label[], const char func[], int line) {
    if (DEBUG == 2) {
        char msg[LLL_CHAR*LLL_CHAR], _msg[LL_CHAR];
        sprintf(msg, "%s (l=%d) = [", label, size);
        for (int i = 0; i < size; i++) {
        sprintf(_msg, "%5.3f, ", array[i]);
        strcat(msg, _msg);
        }
        strcat(msg, "]");
        sprintf(_msg, " \t {%s:%d}\n\n", func, line);
        strcat(msg, _msg);
        io_log_dbg(env, msg);
    }
}


/******************************************************************************
 * \brief Function to write, by all ranks, an integer array on the stdout
 * \param env_t* PhyDLL's environment struct
 * \param double* Integer array to write
 * \param int Size of the array
 * \param char Label of the array
 * \param const char Function from which the array was written (__FUNC__)
 * \param int Line from which the array was written (__line__)
******************************************************************************/
void io_log_dbg_arr_int(env_t* env, int* array, int size, char label[], const char func[], int line) {
    if (DEBUG == 2) {
        char msg[LLL_CHAR*LLL_CHAR], _msg[LL_CHAR];
        sprintf(msg, "%s (l=%d) = [", label, size);
        for (int i = 0; i < size; i++) {
        sprintf(_msg, "%d, ", array[i]);
        strcat(msg, _msg);
        }
        strcat(msg, "]");
        sprintf(_msg, " \t {%s:%d}\n\n", func, line);
        strcat(msg, _msg);
        io_log_dbg(env, msg);
    }
}


/******************************************************************************
 * \brief Generic function to write a dataset of integers on a hdf5 file
 * \param hid_t hdf5 file identifier
 * \param char Dataset name
 * \param int* Buffer of integers
 * \param int Buffer size
******************************************************************************/
#ifdef HDF5
void _write_h5_dataset_int(hid_t file, char datasetname[], int* buff, int buff_size) {
    hid_t dataspace;
    hid_t dataset;
    hsize_t hdims[1];

    hdims[0] = buff_size;
    dataspace = H5Screate_simple(1, hdims, NULL);
    dataset = H5Dcreate1(file, datasetname, H5T_NATIVE_INT, dataspace, H5P_DEFAULT);
    H5Dwrite(dataset, H5T_NATIVE_INT, H5S_ALL, H5S_ALL, H5P_DEFAULT, buff);
    H5Dclose(dataset);
    H5Sclose(dataspace);
}


/******************************************************************************
 * \brief Generic function to write a dataset of double precision on a hdf5 file
 * \param hid_t hdf5 file identifier
 * \param char Dataset name
 * \param int* Buffer of double precision
 * \param int Buffer size
******************************************************************************/
void _write_h5_dataset_double(hid_t file, char datasetname[], double* buff, int buff_size) {
    hid_t dataspace;
    hid_t dataset;
    hsize_t hdims[1];

    hdims[0] = buff_size;
    dataspace = H5Screate_simple(1, hdims, NULL);
    dataset = H5Dcreate1(file, datasetname, H5T_NATIVE_DOUBLE, dataspace, H5P_DEFAULT);
    H5Dwrite(dataset, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, buff);
    H5Dclose(dataset);
    H5Sclose(dataspace);
}


/******************************************************************************
 * \brief Generic function to write mesh and fields metadata on the xdmf file
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL's coupling struct
 * \param msh_t* PhyDLL's mesh struct
******************************************************************************/
void _write_xdmf(env_t* env, cpl_t* cpl, msh_t* msh) {
    char worder[ML_CHAR];
    sprintf(worder, "\">");
    if (strcmp(msh->topology_type, "Wedge") == 0) {
        sprintf(worder, "\" Order=\"0 5 3 1 4 2\">");
    }

    char prefix[SL_CHAR]; char cprefix[SL_CHAR];
    if (env->is_phy_instance) { sprintf(prefix, "phy"); sprintf(cprefix, "PHY");}
    else if (env->is_dl_instance) { sprintf(prefix, "dl");  sprintf(cprefix, "DL"); }

    char out_dir[ML_CHAR];
    sprintf(out_dir, "./PhyDLL_FIELDS");

    char h5file[LL_CHAR];
    sprintf(h5file, "./FILES/%s_%d_%d-%d.h5", prefix, cpl->ite, env->comm_rank, env->comm_size - 1);

    char file_name[LL_CHAR];
    sprintf(file_name, "%s/FILES/%s_%d_%d-%d.xmf", out_dir, prefix, cpl->ite, env->comm_rank, env->comm_size - 1);

    FILE* file;
    file = fopen(file_name, "w");

    char text[LLL_CHAR];

    sprintf(text, "%s\n", "<?xml version=\"1.0\" ?>"); fputs(text, file);
    sprintf(text, "%s\n", "<!DOCTYPE Xdmf SYSTEM \"Xdmf.dtd\" []>"); fputs(text, file);
    sprintf(text, "%s\n", "<Xdmf Version=\"2.0\" xmlns:xi=\"http://www.w3.org/2001/XInclude\">"); fputs(text, file);

        sprintf(text, "\t%s\n", "<Domain>");    fputs(text, file);

            sprintf(text, "\t\t%s%s%s\n", "<Grid Collection=\"PhyDLL\" Name=\"", cprefix, "\">"); fputs(text, file);

                sprintf(text, "\t\t\t%s%d%s\n", "<Time Value=\"", cpl->ite, "\" />"); fputs(text, file);

                sprintf(text, "\t\t\t%s%s%s%d%s\n", "<Topology Type=\"", msh->topology_type, "\" NumberOfElements=\"", msh->ncell, worder); fputs(text, file);
                    sprintf(text, "\t\t\t\t%s%d%s\n", "<DataItem ItemType=\"Function\" Dimensions=\"", msh->ncell*msh->nvert, "\" Function=\"$0 - 1\">"); fputs(text, file);
                        sprintf(text, "\t\t\t\t\t%s%d%s\n", "<DataItem Format=\"HDF\" DataType=\"Int\" Dimensions=\"", msh->ncell*msh->nvert, "\">"); fputs(text, file);
                            sprintf(text, "\t\t\t\t\t\t%s%s\n", h5file, ":/connec"); fputs(text, file);
                        sprintf(text, "\t\t\t\t\t%s\n", "</DataItem>"); fputs(text, file);
                    sprintf(text, "\t\t\t\t%s\n", "</DataItem>"); fputs(text, file);
                sprintf(text, "\t\t\t%s\n", "</Topology>"); fputs(text, file);

                if (msh->geodim == 2) {sprintf(text, "\t\t\t%s\n", "<Geometry Type=\"X_Y\">"); fputs(text, file);}
                if (msh->geodim == 3) {sprintf(text, "\t\t\t%s\n", "<Geometry Type=\"X_Y_Z\">"); fputs(text, file);}
                    sprintf(text, "\t\t\t\t%s%d%s\n", "<DataItem Format=\"HDF\" ItemType=\"Uniform\" Precision=\"8\" NumberType=\"Float\" Dimensions=\"", msh->nnode, "\">"); fputs(text, file);
                        sprintf(text, "\t\t\t\t\t%s%s\n", h5file, ":/x"); fputs(text, file);
                    sprintf(text, "\t\t\t\t%s\n", "</DataItem>"); fputs(text, file);

                    sprintf(text, "\t\t\t\t%s%d%s\n", "<DataItem Format=\"HDF\" ItemType=\"Uniform\" Precision=\"8\" NumberType=\"Float\" Dimensions=\"", msh->nnode, "\">"); fputs(text, file);
                        sprintf(text, "\t\t\t\t\t%s%s\n", h5file, ":/y"); fputs(text, file);
                    sprintf(text, "\t\t\t\t%s\n", "</DataItem>"); fputs(text, file);

                    if (msh->geodim == 3) {
                    sprintf(text, "\t\t\t\t%s%d%s\n", "<DataItem Format=\"HDF\" ItemType=\"Uniform\" Precision=\"8\" NumberType=\"Float\" Dimensions=\"", msh->nnode, "\">"); fputs(text, file);
                        sprintf(text, "\t\t\t\t\t%s%s\n", h5file, ":/z"); fputs(text, file);
                    sprintf(text, "\t\t\t\t%s\n", "</DataItem>"); fputs(text, file);}
                sprintf(text, "\t\t\t%s\n", "</Geometry>"); fputs(text, file);

                sprintf(text, "\t\t\t%s\n", "<Attribute Name=\"partitioning\" Center=\"Node\" AttributeType=\"Scalar\">"); fputs(text, file);
                    sprintf(text, "\t\t\t\t%s%d%s\n", "<DataItem Format=\"HDF\" DataType=\"Int\" Dimensions=\"", msh->nnode, "\">"); fputs(text, file);
                        sprintf(text, "\t\t\t\t\t%s%s\n", h5file, ":/partitioning"); fputs(text, file);
                    sprintf(text, "\t\t\t\t%s\n", "</DataItem>"); fputs(text, file);
                sprintf(text, "\t\t\t%s\n", "</Attribute>"); fputs(text, file);

                for (int i = 0; i < cpl->phy_count; i++) {
                sprintf(text, "\t\t\t%s%d%s%s%s\n", "<Attribute Name=\"phy_fields_", i, "_", cpl->phy_field[i].label, "\" Center=\"Node\" AttributeType=\"Scalar\">"); fputs(text, file);
                    sprintf(text, "\t\t\t\t%s%d%s\n", "<DataItem Format=\"HDF\" ItemType=\"Uniform\" Precision=\"8\" DataType=\"Float\" Dimensions=\"", msh->nnode, "\">"); fputs(text, file);
                        sprintf(text, "\t\t\t\t\t%s%s%d%s%s\n", h5file, ":/phy_fields_", i, "_", cpl->phy_field[i].label); fputs(text, file);
                    sprintf(text, "\t\t\t\t%s\n", "</DataItem>"); fputs(text, file);
                sprintf(text, "\t\t\t%s\n", "</Attribute>"); fputs(text, file);
                }

                for (int i = 0; i < cpl->dl_count; i++) {
                sprintf(text, "\t\t\t%s%d%s%s%s\n", "<Attribute Name=\"dl_fields_", i, "_", cpl->dl_field[i].label, "\" Center=\"Node\" AttributeType=\"Scalar\">"); fputs(text, file);
                    sprintf(text, "\t\t\t\t%s%d%s\n", "<DataItem Format=\"HDF\" ItemType=\"Uniform\" Precision=\"8\" DataType=\"Float\" Dimensions=\"", msh->nnode, "\">"); fputs(text, file);
                        sprintf(text, "\t\t\t\t\t%s%s%d%s%s\n", h5file, ":/dl_fields_", i, "_", cpl->dl_field[i].label); fputs(text, file);
                    sprintf(text, "\t\t\t\t%s\n", "</DataItem>"); fputs(text, file);
                sprintf(text, "\t\t\t%s\n", "</Attribute>"); fputs(text, file);
                }

            sprintf(text, "\t\t%s\n", "</Grid>"); fputs(text, file);

        sprintf(text, "\t%s\n", "</Domain>");   fputs(text, file);

    sprintf(text, "%s\n", "</Xdmf>"); fputs(text, file);

    fclose(file);
}


/******************************************************************************
 * \brief Open the xdmf collection file and write headers
 * \param env_t* PhyDLL's environment struct
******************************************************************************/
void _open_xdmf_collec(env_t* env) {
    char out_dir[ML_CHAR];
    sprintf(out_dir, "./PhyDLL_FIELDS");

    char prefix[SL_CHAR]; char cprefix[SL_CHAR];
    if (env->is_phy_instance) { sprintf(prefix, "phy"); sprintf(cprefix, "PHY");}
    else if (env->is_dl_instance) { sprintf(prefix, "dl");  sprintf(cprefix, "DL"); }

    char file_name[LL_CHAR];
    sprintf(file_name, "%s/%s.xmf", out_dir, prefix);

    if (env->comm_rank == env->comm_hrank) {
        FILE* file;
        file = fopen(file_name, "w");

        char text[LLL_CHAR];

        sprintf(text, "%s\n", "<?xml version=\"1.0\" ?>"); fputs(text, file);
        sprintf(text, "%s\n", "<!DOCTYPE Xdmf SYSTEM \"Xdmf.dtd\" []>"); fputs(text, file);
        sprintf(text, "%s\n", "<Xdmf Version=\"2.0\" xmlns:xi=\"http://www.w3.org/2001/XInclude\">"); fputs(text, file);
        sprintf(text, "\t%s\n", "<Domain>");    fputs(text, file);
        sprintf(text, "\t\t%s%s%s\n", "<Grid Name=\"PhyDLL_", cprefix, "\" GridType=\"Collection\" CollectionType=\"Temporal\">"); fputs(text, file);
        fclose(file);
    }
}


/******************************************************************************
 * \brief Append metadata to the xdmf collection file
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL's coupling struct
******************************************************************************/
void _append_xdmf_collec(env_t* env, cpl_t* cpl) {
    char out_dir[ML_CHAR];
    sprintf(out_dir, "./PhyDLL_FIELDS");

    char prefix[SL_CHAR]; char cprefix[SL_CHAR];
    if (env->is_phy_instance) { sprintf(prefix, "phy"); sprintf(cprefix, "PHY");}
    else if (env->is_dl_instance) { sprintf(prefix, "dl");  sprintf(cprefix, "DL"); }

    char file_name[LL_CHAR];
    sprintf(file_name, "%s/%s.xmf", out_dir, prefix);

    if (env->comm_rank == env->comm_hrank) {
        FILE* file;
        file = fopen(file_name, "a");

        char text[LLL_CHAR];

        sprintf(text, "\t\t\t%s%s%s%d%s\n", "<Grid Name =\"", prefix, "_", cpl->ite, "\" GridType=\"Collection\" CollectionType=\"Spatial\">"); fputs(text, file);

            for (int i = 0; i < env->comm_size; i++) {
            sprintf(text, "\t\t\t\t%s%s%s%d%s%d%s%d%s\n", "<xi:include href=\"./FILES/", prefix, "_", cpl->ite, "_", i, "-", env->comm_size-1, ".xmf\" xpointer=\"xpointer(//Xdmf/Domain/Grid)\"/>"); fputs(text, file);
            }

        sprintf(text, "\t\t\t%s\n", "</Grid>"); fputs(text, file);

        fclose(file);
    }
}


/******************************************************************************
 * \brief Write footers and close the xdmf collection file
 * \param env_t* PhyDLL's environment struct
******************************************************************************/
void io_close_xdmf_collec(env_t* env) {
    char out_dir[ML_CHAR];
    sprintf(out_dir, "./PhyDLL_FIELDS");

    char prefix[SL_CHAR]; char cprefix[SL_CHAR];
    if (env->is_phy_instance) { sprintf(prefix, "phy"); sprintf(cprefix, "PHY");}
    else if (env->is_dl_instance) { sprintf(prefix, "dl");  sprintf(cprefix, "DL"); }

    char file_name[LL_CHAR];
    sprintf(file_name, "%s/%s.xmf", out_dir, prefix);

    if (env->comm_rank == env->comm_hrank) {
        FILE* file;
        file = fopen(file_name, "a");

        char text[LLL_CHAR];
        sprintf(text, "\t\t%s\n", "</Grid>"); fputs(text, file);
        sprintf(text, "\t%s\n", "</Domain>");   fputs(text, file);
        sprintf(text, "%s\n", "</Xdmf>"); fputs(text, file);

        fclose(file);
    }
}


/******************************************************************************
 * \brief Write/save exchanged fields by both instances
 * \param env_t* PhyDLL's environment struct
 * \param cpl_t* PhyDLL's coupling struct
 * \param msh_t* PhyDLL's mesh struct
******************************************************************************/
void io_save_fields(env_t* env, cpl_t* cpl, msh_t* msh) {
    hid_t file;
    char file_name[LL_CHAR];

    char out_dir[ML_CHAR];
    sprintf(out_dir, "./PhyDLL_FIELDS");

    if (cpl->ite == 1) {
        char cmd[LL_CHAR];
        sprintf(cmd, "mkdir -p %s/FILES", out_dir);
        system(cmd);
    }

    char prefix[SL_CHAR]; char cprefix[SL_CHAR];
    if (env->is_phy_instance) { sprintf(prefix, "phy"); sprintf(cprefix, "PHY");}
    else if (env->is_dl_instance) { sprintf(prefix, "dl");  sprintf(cprefix, "DL"); }

    sprintf(file_name, "%s/FILES/%s_%d_%d-%d.h5", out_dir, prefix, cpl->ite, env->comm_rank, env->comm_size - 1);
    file = H5Fcreate(file_name, H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);

    // Write connecitivy table
    _write_h5_dataset_int(file, "connec", msh->connec, msh->ncell*msh->nvert);

    // Write x-axis coordinates
    double* x = malloc(msh->nnode * sizeof(double));
    for (int i = 0; i < msh->nnode; i++) {
        x[i] = msh->coords[msh->geodim * i];
    }
    _write_h5_dataset_double(file, "x", x, msh->nnode);
    free(x);

    // Write y-axis coordinates
    double* y = malloc(msh->nnode * sizeof(double));
    for (int i = 0; i < msh->nnode; i++) {
        y[i] = msh->coords[1 + msh->geodim * i];
    }
    _write_h5_dataset_double(file, "y", y, msh->nnode);
    free(y);

    // Write z-axis coordinates
    if (msh->geodim == 3) {
        double* z = malloc(msh->nnode * sizeof(double));
        for (int i = 0; i < msh->nnode; i++) {
            z[i] = msh->coords[2 + msh->geodim * i];
        }
        _write_h5_dataset_double(file, "z", z, msh->nnode);
        free(z);
    }

    // Write MPI rank field
    int* rk = malloc(msh->nnode * sizeof(int));
    for (int i = 0; i < msh->nnode; i++) {
        rk[i] = env->comm_rank;
    }
    _write_h5_dataset_int(file, "partitioning", rk, msh->nnode);
    free(rk);

    char label[LL_CHAR];
    double* buff = NULL;
    int buff_size = msh->nnode;

    // Write DL fields
    for (int i = 0; i < cpl->dl_count; i++) {
        sprintf(label, "dl_fields_%d_%s", i, cpl->dl_field[i].label);

        if (env->is_phy_instance) buff = cpl->dl_field[i].array;
        else if (env->is_dl_instance) buff = cpl->dl_field[i].array_trim;
        _write_h5_dataset_double(file, label, buff, buff_size);
    }

    // Write PHY fields
    for (int i = 0; i < cpl->phy_count; i++) {
        sprintf(label, "phy_fields_%d_%s", i, cpl->phy_field[i].label);

        if (env->is_phy_instance) buff = cpl->phy_field[i].array;
        else if (env->is_dl_instance) buff = cpl->phy_field[i].array_trim;
        _write_h5_dataset_double(file, label, buff, buff_size);
    }

    H5Fclose(file);

    if (cpl->ite == 1) _open_xdmf_collec(env);
    _write_xdmf(env, cpl, msh);
    _append_xdmf_collec(env, cpl);
}
#endif
