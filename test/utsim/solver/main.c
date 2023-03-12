#include <mpi.h>
#include <parmetis.h>
#include <stdlib.h>
#include <stdio.h>
#include <hdf5.h>

int main(int argc, char* argv[]) {
    MPI_Init(&argc, &argv);

    int comm_rank;
    MPI_Comm comm = MPI_COMM_WORLD;
    MPI_Comm_rank(comm, &comm_rank);

    int comm_size;
    MPI_Comm_size(comm, &comm_size);

    char processor_name[MPI_MAX_PROCESSOR_NAME];
    int name_len;
    MPI_Get_processor_name(processor_name, &name_len);

    printf("%d / %d [%s]\n", comm_rank, comm_size, processor_name);

    hid_t file, grp, dset, dtype, dspace;
    herr_t status;
    int dndim;
    file = H5Fopen("../gmesh_meshes/mesh_2d_struc_coarse.mesh.h5", H5F_ACC_RDONLY, H5P_DEFAULT);
    grp = H5Gopen(file, "Connectivity", H5P_DEFAULT);
    dset = H5Dopen(grp, "qua->node", H5P_DEFAULT);
    dtype = H5Dget_type(dset);
    dspace = H5Dget_space(dset);
    dndim = H5Sget_simple_extent_ndims(dspace);

    hsize_t ddims[dndim];
    H5Sget_simple_extent_dims(dspace, ddims, NULL);
    printf("ddim = %d", ddims[0]);

    int data[ddims[0]];
    status = H5Dread(dset, H5T_NATIVE_INT, H5S_ALL, H5S_ALL, H5P_DEFAULT, &data[0]);

    if (comm_rank == 0){
        printf("\n----------------------------------------------------------------------\n");
        for(int i=0; i<ddims[0]; i++){
            printf("%d, ", data[i]);
            if ((i+1)%20 == 0)
                printf("\n");
        }
        printf("\n----------------------------------------------------------------------\n");
    }

    H5Dclose(dset);
    H5Gclose(grp);
    H5Fclose(file);




    // // idx_t *elmdist, *eptr, *eind, *elmwgt, *wgtflag, *numflag, *ncon, *ncommonnodes, *nparts, *options, *edgecut, *part;
    // // real_t *tpwgts, *ubvec;

    // // ParMETIS_V3_PartMeshKway(
    // //     elmdist,
    // //     eptr,
    // //     eind,
    // //     elmwgt,
    // //     wgtflag,
    // //     numflag,
    // //     ncon,
    // //     ncommonnodes,
    // //     nparts,
    // //     tpwgts,
    // //     ubvec,
    // //     options,
    // //     edgecut,
    // //     part,
    // //     &comm
    // // );


    int *vtxdist, *xadj, *adjncy, *vwgt, *adjwgt, *wgtflag, *numflag, *ndims, *ncon, *nparts, *options, *edgecut, *part;
    double *xyz, *tpwgts, *ubvec;

    // vertices distribution
    vtxdist = malloc(comm_size*sizeof(int));
    for(int i=0; i<comm_size; i++){
        vtxdist[i] = 10;
    }

    ParMETIS_V3_PartGeomKway(
        vtxdist,
        xadj,
        adjncy,
        vwgt,
        adjwgt,
        wgtflag,
        numflag,
        ndims,
        xyz,
        ncon,
        nparts,
        tpwgts,
        ubvec,
        options,
        edgecut,
        part,
        &comm
    );

    free(vtxdist);


    MPI_Finalize();
    return 0;
}