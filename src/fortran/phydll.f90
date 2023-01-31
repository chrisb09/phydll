!*************************************************************************
! FILE      :   phydll.f90
! DATE      :   29-11-2022
! AUTHORS   :   A. Serhani, C. Lapeyre, G. Staffelbach
! EMAIL     :   phydll@cerfacs.fr
! DETAILS   :   PhyDLL's Application Programming Interface (API)
!*************************************************************************
module phydll
    use mod_params
    use mod_phydll, only: phydll_t

    implicit none

    type(phydll_t) :: ph

    interface phydll_init
       module procedure phydll_init
    end interface

    interface phydll_define
        module procedure phydll_define_mesh
        module procedure phydll_define_nc
    end interface

    interface phydll_set_phy_field
        module procedure phydll_set_phy_field
    end interface

    interface phydll_send_phy_fields
        module procedure phydll_send_phy_fields
    end interface

    interface phydll_recv_dl_fields
        module procedure phydll_recv_dl_fields
    end interface

    interface phydll_apply_dl_field
        module procedure phydll_apply_dl_field
    end interface

    interface phydll_finalize
        module procedure phydll_finalize
    end interface

    interface phydll_what_is_dlmesh
        module procedure phydll_what_is_dlmesh
    end interface

    contains

    subroutine phydll_init(glcomm, comm, status)
    !*********************************************************************
    !> Initialize phydll and split communicators
    !
    ! Args:
    !   [out]   glcomm    Global communicator (MPI_COMM_WORLD)
    !   [out]   comm      Local communicator
    !   [out]   status    Status of phydll (returns 1)
    !*********************************************************************
        implicit none

        ! in/out
        integer, intent(out) :: glcomm
        integer, intent(out) :: comm
        integer, intent(out) :: status

        call ph%init(glcomm, comm, status)
    end subroutine


    subroutine phydll_define_nc(field_size)
    !*********************************************************************
    !> Define non-context aware coupling
    !
    ! Args:
    !   [in]    field_size      Physical solver field size
    !                           (or local mesh partition nnode)
    !*********************************************************************
        implicit none

        ! in/out
        integer, intent(in) :: field_size

        ph%mesh%nnode = field_size

        ! Map processess
        call ph%map_directscheme_processes()

        ! Allocate fields
        call ph%allocate_fields()
    end subroutine


    subroutine phydll_define_mesh(dim, ncell, nnode, nvertex, ntcell, ntnode, &
        node_coords, element_to_node, local_node_to_global, local_element_to_global)
    !*********************************************************************
    !> Define mesh for context-aware coupling.
    !> For dMPI coupling: send mesh informations to DL engine
    !> For CWIPI coupling: Set and locate mesh.
    !
    ! Args:
    !   [in][opt]   dim                     Geometrical dimension
    !   [in]        ncell                   Number of mesh cells (local partition)
    !   [in]        nnode                   Number of mesh nodes (local partition)
    !   [in]        nvertex                 Number of vertices per cell
    !   [in][opt]   ntcell                  Total number of mesh cells (all partitions)
    !   [in][opt]   ntnode                  Total number of mesh nodes (all partitions)
    !   [in][opt]   node_coords             Table of mesh nodes coordinates (local partition)
    !   [in]        element_to_node         Table of element-to-node connectivity (local partition)
    !   [in][opt]   local_node_to_global    Table of local-to-global mesh node mapping
    !   [in][opt]   local_element_to_global Table of local-to-global mesh cell mapping
    !*********************************************************************
        implicit none

        ! in/out
        integer, optional, intent(in)               :: dim
        integer, intent(in)                         :: ncell
        integer, intent(in)                         :: nnode
        integer, intent(in)                         :: nvertex
        integer, optional, intent(in)               :: ntcell
        integer, optional, intent(in)               :: ntnode
        double precision, dimension(:), intent(in)  :: node_coords
        integer, dimension(:), intent(in)           :: element_to_node
        integer, dimension(:), optional, intent(in) :: local_node_to_global
        integer, dimension(:), optional, intent(in) :: local_element_to_global

        if (trim(ph%cpl%dl_mesh_type) == "phymesh") then
            call ph%set_phy_mesh(dim=dim, ncell=ncell, nnode=nnode, nvertex=nvertex, &
                    ntcell=ntcell, ntnode=ntnode, node_coords=node_coords, &
                    element_to_node=element_to_node, local_node_to_global=local_node_to_global, &
                    local_element_to_global=local_element_to_global)
            call ph%send_phy_mesh()
        else
            call ph%set_mesh_for_interpscheme(ncell=ncell, nnode=nnode, nvertex=nvertex, &
                    node_coords=node_coords, element_to_node=element_to_node)
        end if

        if (ph%cpl%is_interpolationscheme) then
            call ph%define_locate_mesh_for_interpscheme()
        end if

        call ph%io%log_msg("(PhyDLL) ----> Coupling mesh has been set !", 0)

        call ph%allocate_fields()
    end subroutine


    subroutine phydll_set_phy_field(field, label, index)
    !*********************************************************************
    !> Check if the current iteration corresponds to a coupling iteration
    !> Set physical fields to send to the DL engine (cf. example below)
    !
    !
    ! Args:
    !   [in]        field   Physical field
    !   [in]        label   Physical field label
    !   [in][opt]   index   Index of the field (default = 1)
    !
    ! Example:
    !   call phydll_set_phy_field(field=field_1, label="field_1", index=1)
    !   call phydll_set_phy_field(field=field_2, label="field_2", index=2)
    !*********************************************************************
        implicit none

        ! in/out
        double precision, dimension(:), intent(in)  :: field
        character(len=*), intent(in) :: label
        integer, optional, intent(in) :: index

        ! local
        integer :: idx = 1
        character(len=ll) :: msg

        if (present(index)) idx = index

        if (idx == 1) ph%cpl%phy_ite = ph%cpl%phy_ite + 1
        ph%cpl%is_cpl_ite = (modulo(ph%cpl%phy_ite - 1 + ph%cpl%freq, ph%cpl%freq) == 0)

        if (ph%cpl%is_cpl_ite) then
            if (idx == 1) ph%cpl%ite = ph%cpl%ite + 1
            ph%cpl%phy_fields%ic = ph%cpl%phy_fields%ic + 1

            if (idx > ph%cpl%phy_fields%count .or. ph%cpl%phy_fields%ic > ph%cpl%phy_fields%count) then
                write(msg, "('Count of Phy fields (idx=', i0, ') practically applied (=', I0, ') is different from that is declared (=', I0, ')' )") &
                    idx, ph%cpl%phy_fields%ic, ph%cpl%phy_fields%count
                call ph%io%log_err(trim(msg))
            end if

            call ph%set_phy_field(field, label, idx)
        end if
    end subroutine


    subroutine phydll_send_phy_fields(loop)
    !*********************************************************************
    !> Broadcast current coupling iteration
    !> Send physical fields to DL engine
    !
    ! Args:
    !   [in]    loop   Activale loop mode
    !*********************************************************************
        implicit none

        ! in/out
        logical, optional, intent(in) :: loop

        ! local
        character(len=ll) :: msg
        integer :: i
        logical :: loop_ = .false.

        if (present(loop)) loop_ = loop

        if (ph%cpl%is_cpl_ite) then
            call ph%check_fields_count()

            if (loop_) call ph%bcast_signal()

            if (ph%cpl%is_directscheme) then
                call ph%directscheme_anb_send_phy_fields()
                call ph%directscheme_nb_recv_dl_fields()

            else if (ph%cpl%is_interpolationscheme) then
                call ph%interpscheme_anb_send_phy_fields()
                call ph%interpscheme_nb_recv_dl_fields()

            end if

            write(msg, "('(PhyDLL) -----> Coupling ite (Phy ite) = ', I0, ' (', I0, ') ...')" ) ph%cpl%ite, ph%cpl%phy_ite
            call ph%io%log_msg(trim(msg), 1)

            call ph%io%log_msg("(PhyDLL) -----> Phy fields sent!", 1)
            do i = 1, ph%cpl%phy_fields%count
                write(msg, "('(', i0, ')', X, A)") ph%cpl%phy_fields%index(i), trim(ph%cpl%phy_fields%label(i))
                call ph%io%log_msg(trim(msg), 4)
            end do

            ph%cpl%phy_fields%ic = 0
            ph%cpl%dl_fields%ic = 0
        end if
    end subroutine


    subroutine phydll_recv_dl_fields()
    !*********************************************************************
    !> Receive predicted (DL) fields from DL engine
    !*********************************************************************
        if (ph%cpl%is_cpl_ite) then
            if (ph%cpl%is_directscheme) then
                call ph%directscheme_wait_anb_send()
                call ph%directscheme_wait_nb_recv()

            else if (ph%cpl%is_interpolationscheme) then
                call ph%interpscheme_wait_anb_send()
                call ph%interpscheme_wait_nb_recv()
                call ph%interpscheme_handle_notlocpoints()
            end if

            call ph%io%log_msg("(PhyDLL) -----> DL fields received! To be applied on:", 1)
        end if
    end subroutine


    subroutine phydll_apply_dl_field(field, label, index)
    !*********************************************************************
    !> Check if the current iteration corresponds to a coupling iteration
    !> Apply DL fields (accumulative, cf. example below)
    !
    !
    ! Args:
    !   [in]        field   DL field
    !   [in]        label   DL field label
    !   [in][opt]   index   Index of the field (default = 1)
    !
    ! Example:
    !   call phydll_apply_dl_field(field=field_1, label="field_1", index=1)
    !   call phydll_apply_dl_field(field=field_2, label="field_2", index=2)
    !*********************************************************************
        implicit none

        ! in/out
        double precision, dimension(:), intent(out) :: field
        character(len=*), intent(in) :: label
        integer, optional, intent(in) :: index

        ! local
        character(len=ll) :: msg

        if (ph%cpl%is_cpl_ite) then
            ph%cpl%dl_fields%ic = ph%cpl%dl_fields%ic + 1

            if (index > ph%cpl%dl_fields%count .or. ph%cpl%dl_fields%ic > ph%cpl%dl_fields%count) then
                write(msg, "('Count of DL fields (idx=', i0, ') practically applied (=', I0, ') is different from that is declared (=', I0, ')' )") &
                    index, ph%cpl%dl_fields%ic, ph%cpl%dl_fields%count
                call ph%io%log_err(trim(msg))
            end if

            call ph%apply_dl_field(field, label, index)

            write(msg, "('(', i0, ')', X, A)") ph%cpl%dl_fields%index(index), trim(ph%cpl%dl_fields%label(index))
            call ph%io%log_msg(trim(msg), 4)
        end if
    end subroutine


    subroutine phydll_finalize
    !*********************************************************************
    !> Finalize phydll
    !*********************************************************************
        call ph%io%log_msg("(PhyDLL) -----> Finalizing", 0)
        call ph%finalize()
    end subroutine


    subroutine phydll_what_is_dlmesh(answer)
    !*********************************************************************
    ! @DBG
    !> Ask the type of mesh used in the coupling
    !
    ! Args:
    !   [out]   answer      0: NC;      1: PhyMESH;     2: CWP Mesh
    !*********************************************************************
        implicit none

        ! in/out
        integer, intent(out) :: answer

        if (trim(ph%cpl%dl_mesh_type) == "NC") then
            answer = 0
        else
            if (trim(ph%cpl%dl_mesh_type) == "phymesh") then
                answer = 1
            else
                answer = 2
            end if
        end if
    end subroutine
end module
