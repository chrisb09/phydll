program main
    use mpi
    use phydll, only: phydll_init, phydll_send_phy_fields
    integer :: glcomm
    integer :: comm
    integer :: status
    integer :: ierr 

    call mpi_init(ierr)

    call phydll_init(glcomm, comm, status)
    call phydll_send_phy_fields

    call mpi_finalize(ierr)

end program