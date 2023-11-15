program phy_main
    use mpi
    use phydll_f,   only : phydll_init_f, phydll_finalize_f, phydll_define_phy_f, &
                        phydll_set_field_f, phydll_get_field_f, phydll_send_f, phydll_recv_f, &
                        phydll_isend_f, phydll_wait_isend_f, phydll_irecv_f, phydll_wait_irecv_f, &
                        phydll_opt_enable_cpl_loop_f, phydll_opt_set_freq_f, phydll_opt_set_output_freq_f
    !@hc
    use iso_c_binding

    integer :: comm
    integer :: myrank
    integer :: ierr

    character(kind=c_char, len=16) :: instance
    integer(c_int) :: count = 3
    integer(c_int) :: size = 5

    double precision, dimension(:), pointer :: phy_field_0, phy_field_1, phy_field_2
    character(kind=c_char, len=64) :: phy_label_0, phy_label_1, phy_label_2

    double precision, dimension(:), pointer :: dl_field_0, dl_field_1
    character(kind=c_char, len=64) :: dl_label_0, dl_label_1

    integer :: iter
    integer :: niter = 5

    integer :: i

    instance = "physical"

    call mpi_init(ierr)
    call mpi_comm_rank(MPI_COMM_WORLD, myrank, ierr)

    call phydll_init_f(instance=instance, comm=comm)
    call phydll_opt_enable_cpl_loop_f()
    call phydll_opt_set_freq_f(2)
    call phydll_opt_set_output_freq_f(2)
    call phydll_define_phy_f(count=count, size=size)

    ! TEST "comm"
    call mpi_bcast(niter, 1, MPI_INT, 0, comm, ierr)

    allocate(phy_field_0(size))
    allocate(phy_field_1(size))
    allocate(phy_field_2(size))

    do iter = 1, niter
        do i = 1, size
            phy_field_0(i) = 10d0 * myrank + 100d0 + 1000d0 * iter
            phy_field_1(i) = 20d0 * myrank + 200d0 + 1000d0 * iter
            phy_field_2(i) = 30d0 * myrank + 300d0 + 1000d0 * iter
        end do
        phy_label_0 = "fortran_phy_field_0"
        phy_label_1 = "fortran_phy_field_1"
        phy_label_2 = "fortran_phy_field_2"

        call phydll_set_field_f(phy_field_0, phy_label_0)
        call phydll_set_field_f(phy_field_1, phy_label_1)
        call phydll_set_field_f(phy_field_2, phy_label_2)

        ! call phydll_send_f()
        call phydll_isend_f()
        call phydll_wait_isend_f()

        ! call sleep(2)

        ! call phydll_recv_f()
        call phydll_irecv_f()
        call phydll_wait_irecv_f()

        allocate(dl_field_0(size))
        allocate(dl_field_1(size))

        call phydll_get_field_f(dl_field_0, dl_label_0)
        call phydll_get_field_f(dl_field_1, dl_label_1)

        ! deallocate(dl_field_0)
        ! deallocate(dl_field_1)
    end do

    deallocate(phy_field_0)
    deallocate(phy_field_1)
    deallocate(phy_field_2)

    call phydll_finalize_f()
    call mpi_finalize(ierr)
end program