!*************************************************************************
! FILE      :   ds_nc/main.f90
! DATE      :   07-03-2023
! AUTHORS   :   A. Serhani, C. Lapeyre, G. Staffelbach
! EMAIL     :   phydll@cerfacs.fr
! DETAILS   :   Example of Physical solver for Direct-Scheme Non-context 
!               aware coupling
!*************************************************************************
program main
    use mpi
    use phydll, only: phydll_init, phydll_finalize, phydll_define, phydll_set_phy_field, phydll_send_phy_fields, phydll_recv_dl_fields, phydll_apply_dl_field

    implicit none 

    ! MPI 
    integer :: global_comm
    integer :: comm
    integer :: ierr

    ! PhyDLL
    integer :: enable_phydll

    ! Exchanged arrays 
    integer :: arr_size = 10
    double precision, dimension(:), allocatable :: phy_arr_1
    double precision, dimension(:), allocatable :: phy_arr_2
    double precision, dimension(:), allocatable :: dl_arr

    ! Temporal loop
    integer :: niter = 5
    integer :: iter

    ! Init mpi
    call mpi_init(ierr)

    ! Init/define phydll coupling
    call phydll_init(global_comm, comm, enable_phydll)
    call phydll_define(field_size=arr_size)

    ! Allocate exchanged fields
    allocate(phy_arr_1(arr_size))
    allocate(phy_arr_2(arr_size))
    allocate(dl_arr(arr_size))

    ! Temporal loop
    do iter = 1, niter
        ! Compute physical fields
        phy_arr_1 = 100. + iter 
        phy_arr_2 = 200. + iter

        ! Set physical fields to send
        call phydll_set_phy_field(field=phy_arr_1, label="field_1", index=1)
        call phydll_set_phy_field(field=phy_arr_2, label="field_2", index=2) 
        ! Send physical fields
        call phydll_send_phy_fields(loop=.true.)
        
        call sleep(2)
        
        ! Recv dl fields
        call phydll_recv_dl_fields()
        ! Apply dl fields
        call phydll_apply_dl_field(field=dl_arr, label="dl_arr", index=1)

        call sleep(1)
    end do

    ! Deallocate exchanged fields
    deallocate(phy_arr_1)
    deallocate(phy_arr_2)
    deallocate(dl_arr)

    ! Finalize phydll
    call phydll_finalize()

    ! Finalize mpi
    call mpi_finalize(ierr)
end program