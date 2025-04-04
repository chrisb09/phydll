#include <mpi.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "phydll.h"

#define DEBUG 1

int main(int argc, char* argv[]) {
    // Init MPI
    MPI_Init(&argc, &argv);
    MPI_Comm glcomm = MPI_COMM_WORLD; //@hc comm = MPI_COMM_WORLD;
    int hc_rank; MPI_Comm_rank(glcomm, &hc_rank);

    // Init phydll
    phydll_init("physical");
    MPI_Comm comm = phydll_get_local_mpi_comm();
    int _s; MPI_Comm_size(comm, &_s);

    // Phydll options
    phydll_opt_enable_cpl_loop();
    phydll_opt_set_freq(2);
    phydll_opt_set_output_freq(2);

    // Loop params
    int niter = 5;

    // Define phydll
    int count = 3;
    int size = 5 + hc_rank;
    phydll_define_phy(count, size);

    // Allocate fields
    double* phy_field_0 = (double*) malloc(size * sizeof(double));
    double* phy_field_1 = (double*) malloc(size * sizeof(double));
    double* phy_field_2 = (double*) malloc(size * sizeof(double));

    double* dl_field_0 = (double*) malloc(size * sizeof(double));
    double* dl_field_1 = (double*) malloc(size * sizeof(double));

    // Loop
    for (int iter = 1; iter <= niter; iter++) {
        // Compute physical field
        char label[64];
        for (int i = 0; i < size; i++) {
            phy_field_0[i] = hc_rank + i/10.;
            phy_field_1[i] = hc_rank + i/100.;
            phy_field_2[i] = hc_rank + i/1000.;
        }

        // Set physical field
        strcpy(label, "TUTO-PHY-FIELD000");
        phydll_set_field(&phy_field_0, label);

        strcpy(label, "TUTO-PHY-FIELD111");
        phydll_set_field(&phy_field_1, label);

        strcpy(label, "TUTO-PHY-FIELD222");
        phydll_set_field(&phy_field_2, label);

        // Send physical field
        phydll_isend();
        phydll_wait_isend();

        // Receive DL field
        phydll_recv();

        // Get DL field
        char label_0[64], label_1[64];
        phydll_get_field(&dl_field_0, label_0);
        phydll_get_field(&dl_field_1, label_1);
        phydll_get_field_size(&size);

        // Print received field
        char msg[1024], _msg[1024];
        sprintf(msg, "PHY-MODEL: dl_field(s=%d, l=%s) = [", size, label_0);
        for (int i = 0; i < size; i++) {
            sprintf(_msg, "%5.3f, ", dl_field_0[i]); strcat(msg, _msg);
        } if (DEBUG) printf("%s] \t {%s:%d}\n\n", msg, __func__, __LINE__);

        sprintf(msg, "PHY-MODEL: dl_field(s=%d, l=%s) = [", size, label_1);
        for (int i = 0; i < size; i++) {
            sprintf(_msg, "%5.3f, ", dl_field_1[i]); strcat(msg, _msg);
        } if (DEBUG) printf("%s] \t {%s:%d}\n\n", msg, __func__, __LINE__);
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