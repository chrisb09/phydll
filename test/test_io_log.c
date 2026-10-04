#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <mpi.h>
#include "params.h"
#include "kernel_structs.h"
#include "io.h"

static int barriers;

int MPI_Barrier(MPI_Comm comm) {
    (void)comm;
    ++barriers;
    return MPI_SUCCESS;
}

static void check(const char *logging, const char *sync, int rank,
                  int expected_barriers, long expected_bytes) {
    if (logging) setenv("PHYDLL_IO_LOG", logging, 1);
    else unsetenv("PHYDLL_IO_LOG");
    if (sync) setenv("PHYDLL_IO_LOG_BARRIERS", sync, 1);
    else unsetenv("PHYDLL_IO_LOG_BARRIERS");
    env_t env = {0};
    env.comm_rank = rank;
    env.comm_hrank = 0;
    FILE *capture = tmpfile();
    assert(capture);
    fflush(stdout);
    int saved = dup(STDOUT_FILENO);
    assert(saved >= 0 && dup2(fileno(capture), STDOUT_FILENO) >= 0);
    barriers = 0;
    io_log(&env, "x");
    io_logall(&env, "x");
    fflush(stdout);
    assert(barriers == expected_barriers);
    assert(ftell(capture) == expected_bytes);
    assert(dup2(saved, STDOUT_FILENO) >= 0);
    close(saved);
    fclose(capture);
}

int main(void) {
    check(NULL, NULL, 0, 0, 0);
    check("0", "0", 0, 0, 0);
    check("false", "false", 0, 0, 0);
    check("1", NULL, 0, 0, 2);
    check("1", NULL, 1, 0, 1);
    check(NULL, "1", 0, 4, 0);
    check("1", "1", 0, 4, 2);
    puts("PhyDLL logging defaults and explicit opt-ins passed");
    return 0;
}
