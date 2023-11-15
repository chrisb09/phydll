!*************************************************************************
! FILE      :   main_solver.f90
! DATE      :   13-02-2022
! AUTHORS   :   A. Serhani, C. Lapeyre, G. Staffelbach
! EMAIL     :   phydll@cerfacs.fr
! DETAILS   :   UNITTEST of PhyDLL: solver main
!*************************************************************************
program main_solver
    use mpi,        only: mpi_barrier
    use mod_solver, only: solver_t

    ! Import PhyDLL API
#ifdef PHYDLL
    use phydll_f,   only :  phydll_init_f, phydll_finalize_f, phydll_define_phy_f, &
                            phydll_define_phy_with_mesh_f, phydll_set_field_f, &
                            phydll_get_field_f, phydll_send_f, phydll_recv_f, &
                            phydll_isend_f, phydll_wait_isend_f, &
                            phydll_irecv_f, phydll_wait_irecv_f, &
                            phydll_opt_set_output_freq_f, phydll_opt_enable_cpl_loop_f
#endif

    implicit none

    ! Define solver derived type
    type(solver_t) :: solver

    ! Local: Solver
    integer :: count = 1
    double precision, dimension(:), pointer :: phy_field, dl_field
    integer, parameter :: niter = 5
    integer :: i, j
    double precision :: ampl, sigx, sigy
    character(len=64) :: label

    ! Initialize simulation
    call solver%initialize()

#ifdef PHYDLL
    ! Initialize phydll
    call phydll_init_f("physical", solver%comm)
    call phydll_opt_set_output_freq_f(2)
    call phydll_opt_enable_cpl_loop_f()
#endif

    ! Intialize solver and create mesh
    call solver%init_solver()
    call solver%log(message="WELCOME TO UNITARY TEST", blk=.true.)
    call solver%read_mesh()
    call solver%write_mesh_partitions()
    call solver%log(message="MESH CREATION: DONE!", blk=.true.)

#ifdef PHYDLL
    ! Context: Non-context aware coupling
    ! call phydll_define_phy_f(count=count, size=solver%nnode)

    ! Context: Physical-mesh based coupling
    call phydll_define_phy_with_mesh_f( &
        count=count, &
        geodim=solver%dim, &
        ncell=solver%ncell, &
        nnode=solver%nnode, &
        nvert=solver%nvert, &
        ntcell=solver%ntcell, &
        ntnode=solver%ntnode, &
        coords=solver%coords, &
        connec=solver%element_to_node, &
        local_node_to_global=solver%local_node_to_global, &
        local_cell_to_global=solver%local_element_to_global &
    )

    ! Allocate exchanged fields
    allocate(phy_field(solver%nnode))

    ! Temporal loop
    do i = 1, niter
        ampl = 10.
        sigx = 2./3
        sigy = 1./2
        do j = 0, solver%nnode - 1
            phy_field(j+1) = ampl * exp(-(solver%coords(1 + j*solver%dim) - 3./2)**2/(2*sigx**2) - (solver%coords(2 + j*solver%dim) - 1.)**2/(2*sigy**2))
        end do

        call phydll_set_field_f(phy_field, "gauss")
        call phydll_isend_f()
        call phydll_irecv_f()

        call sleep(2)

        call phydll_wait_isend_f()
        call phydll_wait_irecv_f()

        allocate(dl_field(solver%nnode))
        call phydll_get_field_f(field=dl_field, label=label)
    end do

    ! Deallocate
    deallocate(phy_field)
    ! deallocate(dl_field)

    ! Finalize phydll
    call phydll_finalize_f()
#endif

    ! Finalize solver
    call solver%finalize()
end program