**PhyDLL** (fidɛl) (**Phy**sics **D**eep **L**earning coup**L**er) is an open-source library to couple massively parallel physical solvers to distributed deep learning inferences.

The documentation is available in [phydll.readthedocs.io](https://phydll.readthedocs.io)

![PhyDLL](docs/images/phydll_1.png)

# Runtime Logging

Routine `io_log`/`io_logall` messages and their MPI logging barriers are disabled
by default. Set `PHYDLL_IO_LOG=1` to enable these messages. Set
`PHYDLL_IO_LOG_BARRIERS=1` separately to enable synchronized logging; these
barriers can delay coupling and should normally remain disabled in benchmarks.
Apply the same barrier setting to every process in an instance communicator.
Errors and dedicated initialization/debug diagnostics are unchanged.

Run the standalone logging regression with an MPI C compiler (no MPI launch is
needed; the test intercepts barriers):

```bash
mpicc -Isrc/core test/test_io_log.c src/core/io.c -o /tmp/phydll-test-io-log
/tmp/phydll-test-io-log
```
