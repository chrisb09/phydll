#include <mpi.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "phydll.h"

#define DEBUG 0

int main(int argc, char* argv[]) {
    // Init MPI
    MPI_Init(&argc, &argv);
    MPI_Comm glcomm = MPI_COMM_WORLD; //@hc comm = MPI_COMM_WORLD;
    int hc_rank; MPI_Comm_rank(glcomm, &hc_rank);

    // Init phydll
    phydll_init("dl");
    MPI_Comm comm = phydll_get_local_mpi_comm();
    int _s; MPI_Comm_size(comm, &_s);

    // Define phydll
    int count = 2;
    phydll_define_dl(count);

    // Get physical field
    int size;
    phydll_get_field_size(&size);

    // Allocate fields
    double* phy_field_0 = (double*) malloc(size * sizeof(double));
    double* phy_field_1 = (double*) malloc(size * sizeof(double));
    double* phy_field_2 = (double*) malloc(size * sizeof(double));

    double* dl_field_0 = (double*) malloc(size * sizeof(double));
    double* dl_field_1 = (double*) malloc(size * sizeof(double));

    // Temporal loop
    // int niter = 5;
    // for (int iter = 1; iter <= niter; iter++) {
    while (phydll_is_phy_signal()) {
        // Receive physical field
        phydll_irecv();
        phydll_wait_irecv();

        char label_0[64], label_1[64], label_2[64];
        phydll_get_field(&phy_field_0, label_0);
        phydll_get_field(&phy_field_1, label_1);
        phydll_get_field(&phy_field_2, label_2);

        // Print received field
        char msg[1024], _msg[1024];
        sprintf(msg, "DL-ENGINE: phy_field(s=%d, l=%s) = [", size, label_0);
        for (int i = 0; i < size; i++) {
            sprintf(_msg, "%5.3f, ", phy_field_0[i]); strcat(msg, _msg);
        } if (DEBUG) printf("%s] \t {%s:%d}\n\n", msg, __func__, __LINE__);

        sprintf(msg, "DL-ENGINE: phy_field(s=%d, l=%s) = [", size, label_1);
        for (int i = 0; i < size; i++) {
            sprintf(_msg, "%2.1f, ", phy_field_1[i]); strcat(msg, _msg);
        } if (DEBUG) printf("%s] \t {%s:%d}\n\n", msg, __func__, __LINE__);

        // Compute DL field
        for (int i = 0; i < size; i++) {
            dl_field_0[i] = -(50 + phy_field_0[i] + phy_field_2[i]);
            dl_field_1[i] = -(80 + phy_field_1[i] + phy_field_2[i]);
        }

        // Set DL field
        char label[64];
        strcpy(label, "TUTO-DL-FIELD000");
        phydll_set_field(&dl_field_0, label);

        strcpy(label, "TUTO-DL-FIELD111");
        phydll_set_field(&dl_field_1, label);

        // Send DL field
        phydll_send();
    }

    // Finalize phydll
    phydll_finalize();

    // Free memory
    free(phy_field_0);
    free(phy_field_1);
    free(phy_field_2);
    free(dl_field_0);
    free(dl_field_1);

    // Finalize MPI
    MPI_Finalize();

    return 0;
}
