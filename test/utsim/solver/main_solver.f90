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
    use phydll,     only: phydll_init, phydll_finalize, phydll_define, phydll_set_phy_field, &
                            phydll_send_phy_fields, phydll_recv_dl_fields, phydll_apply_dl_field, &
                            phydll_what_is_dlmesh
#endif

    implicit none

    ! Define solver derived type
    type(solver_t) :: solver

    ! Local: PhyDLL
    integer :: enable_phydll
    integer :: glcomm
    integer :: context_type

    ! Local: Solver
    double precision, dimension(:), allocatable :: phy_field, dl_field
    integer :: niter = 5
    integer :: i, j
    double precision :: ampl, sigx, sigy
    ! Initialize simulation
    call solver%initialize()

#ifdef PHYDLL
    ! Initialize phydll
    call phydll_init(glcomm, solver%comm, enable_phydll)
#endif

    ! Intialize solver and create mesh
    call solver%init_solver()
    call solver%log(message="WELCOME TO UNITARY TEST", blk=.true.)
    call solver%read_mesh()
    call solver%write_mesh_partitions()
    call solver%log(message="MESH CREATION: DONE!", blk=.true.)

#ifdef PHYDLL
    if (enable_phydll == 1) then
        ! Get coupling contexet
        call phydll_what_is_dlmesh(context_type)

        if (context_type == 0) then
            ! Context: Non-context aware coupling
            call phydll_define(field_size=solver%nnode)

        else if (context_type == 1) then
            ! Context: Physical-mesh based coupling
            call phydll_define( dim=solver%dim, &
                                ncell=solver%ncell, &
                                nnode=solver%nnode, &
                                nvertex=solver%nvertex, &
                                ntcell=solver%ntcell, &
                                ntnode=solver%ntnode, &
                                node_coords=solver%coords, &
                                element_to_node=solver%element_to_node, &
                                local_node_to_global=solver%local_node_to_global, &
                                local_element_to_global=solver%local_element_to_global )

        else if (context_type == 2) then
            ! Context: Distinct-mesh based coupling
            call phydll_define( dim=solver%dim, &
                                ncell=solver%ncell, &
                                nnode=solver%nnode, &
                                nvertex=solver%nvertex, &
                                element_to_node=solver%element_to_node, &
                                node_coords=solver%coords )

        end if

        ! Allocate exchanged fields
        allocate(phy_field(solver%nnode))
        allocate(dl_field(solver%nnode))

        ! Necessary barrier
        call mpi_barrier(glcomm, i)

        ! Temporal loop
        do i = 1, niter
            ampl = 10.
            sigx = 2./3
            sigy = 1./2
            do j = 0, solver%nnode - 1
                phy_field(j+1) = ampl * exp(-(solver%coords(1 + j*solver%dim) - 3./2)**2/(2*sigx**2) - (solver%coords(2 + j*solver%dim) - 1.)**2/(2*sigy**2))
            end do
            ! phy_field = 10 * solver%comm_rank + 100 * i

            call phydll_set_phy_field(field=phy_field, label="gauss", index=1)
            call phydll_send_phy_fields(loop=.true.)

            call phydll_recv_dl_fields()
            call phydll_apply_dl_field(field=dl_field, label="mydlfield", index=1)
        end do


        ! Deallocate
        deallocate(phy_field)
        deallocate(dl_field)

        ! Finalize phydll
        call phydll_finalize()
    end if
#endif

    ! Finalize solver
    call solver%finalize()
end program