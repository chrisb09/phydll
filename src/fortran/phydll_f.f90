!******************************************************************************
! \file src/fortran/phydll_f.f90
! \brief PhyDLL’s Fortran interface
! \authors A. Serhani, C. Lapeyre, G. Staffelbach
! \mainpage phydll.readthedocs.io
! \email phydll@cerfacs.fr
! \date Wed, May 03, 2023
! \copyright CeCILL-B FREE SOFTWARE LICENSE AGREEMENT
! \copyright COPYRIGHT (C) [2023] [CERFACS]
!******************************************************************************

module phydll_f
    use iso_c_binding
    use phydll_cf

    integer :: size__ = 0

    interface phydll_init_f
        module procedure phydll_init_f
    end interface

    interface phydll_finalize_f
        module procedure phydll_finalize_f
    end interface

    interface phydll_define_phy_f
        module procedure phydll_define_phy_f
    end interface

    interface phydll_define_phy_with_mesh_f
        module procedure phydll_define_phy_with_mesh_f
    end interface

    interface phydll_define_dl_f
        module procedure phydll_define_dl_f
    end interface

    interface phydll_set_field_f
        module procedure phydll_set_field_f
    end interface

    interface phydll_get_field_f
        module procedure phydll_get_field_f
    end interface

    interface phydll_send_f
        module procedure phydll_send_f
    end interface

    interface phydll_isend_f
        module procedure phydll_isend_f
    end interface

    interface phydll_wait_isend_f
        module procedure phydll_wait_isend_f
    end interface

    interface phydll_recv_f
        module procedure phydll_recv_f
    end interface

    interface phydll_irecv_f
        module procedure phydll_irecv_f
    end interface

    interface phydll_wait_irecv_f
        module procedure phydll_wait_irecv_f
    end interface

    interface phydll_get_field_size_f
        module procedure phydll_get_field_size_f
    end interface

    interface phydll_get_field_counts_f
        module procedure phydll_get_field_counts_f
    end interface

    interface phydll_is_phy_signal_f
        module procedure phydll_is_phy_signal_f
    end interface

    interface phydll_get_phy_ite_f
        module procedure phydll_get_phy_ite_f
    end interface

    interface phydll_get_ite_f
        module procedure phydll_get_ite_f
    end interface

    interface phydll_opt_enable_cpl_loop_f
        procedure phydll_opt_enable_cpl_loop_cf
    end interface

    interface phydll_opt_set_freq_f
        procedure phydll_opt_set_freq_cf
    end interface

    interface phydll_opt_set_output_freq_f
        procedure phydll_opt_set_output_freq_cf
    end interface

    contains

    !******************************************************************************
    ! \brief Initiliaze PhyDLL
    ! \param[in] character Instance ("physical", "Physical", "phy", "Phy", "dl", "deeplearning", "DL", "DeepLearning")
    ! \param[out] integer MPI local communicator
    !******************************************************************************
    subroutine phydll_init_f(instance, comm)
        implicit none
        character(kind=c_char, len=*) :: instance
        integer, intent(out) :: comm

        character(len=64) :: instance_c

        write(instance_c, "(a,a)") trim(instance), C_NULL_CHAR
        call phydll_init_cf(trim(instance_c))

        comm = phydll_get_local_mpi_fcomm_cf()
    end subroutine


    !******************************************************************************
    ! \brief Finalize PhyDLL
    !******************************************************************************
    subroutine phydll_finalize_f()
        call phydll_finalize_cf()
    end subroutine


    !******************************************************************************
    ! \brief Define PhyDLL’s physical solver instance
    ! \param[in] integer Count of physical fields to send
    ! \param[in] integer Length of physical field (or number of mesh nodes)
    !******************************************************************************
    subroutine phydll_define_phy_f(count, size)
        implicit none
        integer(c_int), value :: count
        integer(c_int), value :: size

        size__ = size
        call phydll_define_phy_cf(count, size)
    end subroutine


    !******************************************************************************
    ! \brief Define PhyDLL's physical solver instance with mesh support
    ! \param [in] integer Number of physical fields to send
    ! \param [in] integer Geometric dimension
    ! \param [in] integer Number of local mesh cells
    ! \param [in] integer Number of local mesh nodes
    ! \param [in] integer Number of global (full) mesh cells
    ! \param [in] integer Number of global (full) mesh nodes (without duplication)
    ! \param [in] integer Number of nodes per element (eg. quad=4, tetra=4, hexa=8, prism=6, ...)
    ! \param [in] integer(:) Local connectivity table (element to node), len=nvert*ncell
    ! \param [in] double precision(:) Local coordinates table, len=geodim*nnode
    ! \param [in] integer(:) Table of local to global cell numerotation, len=ncell
    ! \param [in] integer(:) Table of local to global node numerotation, len=nnode
    !******************************************************************************
    subroutine phydll_define_phy_with_mesh_f(count, geodim, ncell, nnode, ntcell, ntnode, nvert, &
                                            connec, coords, local_cell_to_global, local_node_to_global)
        implicit none
        integer(c_int), value :: count
        integer(c_int), value :: geodim
        integer(c_int), value :: ncell
        integer(c_int), value :: nnode
        integer(c_int), value :: ntcell
        integer(c_int), value :: ntnode
        integer(c_int), value :: nvert

        integer, dimension(:), pointer, intent(in) :: connec
        double precision, dimension(:), pointer, intent(in) :: coords
        integer, dimension(:), pointer, intent(in) :: local_cell_to_global
        integer, dimension(:), pointer, intent(in) :: local_node_to_global

        type(c_ptr) :: connec_c
        type(c_ptr) :: coords_c
        type(c_ptr) :: local_cell_to_global_c
        type(c_ptr) :: local_node_to_global_c

        connec_c = c_loc(connec)
        coords_c = c_loc(coords)
        local_cell_to_global_c = c_loc(local_cell_to_global)
        local_node_to_global_c = c_loc(local_node_to_global)

        call phydll_define_phy_with_mesh_cf(count, geodim, ncell, nnode, ntcell, ntnode, nvert, &
                                        connec_c, coords_c, local_cell_to_global_c, local_node_to_global_c)
    end subroutine


    !******************************************************************************
    ! \brief Define PhyDLL’s DL instance
    ! \param[in] integer Count of DL fields
    !******************************************************************************
    subroutine phydll_define_dl_f(count)
        implicit none
        integer(c_int) :: count

        call phydll_define_dl_cf(count)
    end subroutine


    !******************************************************************************
    ! \brief Set PhyDLL’s field to send (accumulative)
    ! \param[in] double precision(:) Field to send double-precision pointer
    ! \param[in] character Label of field
    !******************************************************************************
    subroutine phydll_set_field_f(field, label)
        implicit none
        double precision, dimension(:), pointer, intent(in) :: field
        character(kind=c_char, len=*), intent(in) :: label
        type(c_ptr) :: field_c
        character(len=256) :: label_c

        write(label_c, "(a,a)") trim(label), C_NULL_CHAR

        field_c = c_loc(field)
        call phydll_set_field_cf(field_c, trim(label_c))
    end subroutine


    !******************************************************************************
    ! \brief Get PhyDLL’s received field (accumulative)
    ! \param[out] double precision(:) Received field double-precision pointer
    ! \param[out] character Label of field
    !******************************************************************************
    subroutine phydll_get_field_f(field, label)
        implicit none
        double precision, dimension(:), pointer, intent(out) :: field
        character(kind=c_char, len=*), intent(out) :: label

        type(c_ptr) :: field_c
        character(len=256) :: label_c

        write(label_c, "(a,a)") trim(label), C_NULL_CHAR

        call phydll_get_field_cf(field_c, label)
        call c_f_pointer(field_c, field, [size__])
    end subroutine


    !******************************************************************************
    ! \brief Send fields (from PhyDLL’s buffer)
    !******************************************************************************
    subroutine phydll_send_f()
        call phydll_send_cf()
    end subroutine


    !******************************************************************************
    ! \brief Non-blocking send fields (from PhyDLL’s buffer)
    !******************************************************************************
    subroutine phydll_isend_f()
        call phydll_isend_cf()
    end subroutine


    !******************************************************************************
    ! \brief Waiting for non-blocking send fields (from PhyDLL’s buffer)
    !******************************************************************************
    subroutine phydll_wait_isend_f()
        call phydll_wait_isend_cf()
    end subroutine


    !******************************************************************************
    ! \brief Recv fields (into PhyDLL’s buffer)
    !******************************************************************************
    subroutine phydll_recv_f()
        call phydll_recv_cf()
    end subroutine


    !******************************************************************************
    ! \brief Non-blocking recv fields (into PhyDLL’s buffer)
    !******************************************************************************
    subroutine phydll_irecv_f()
        call phydll_irecv_cf()
    end subroutine


    !******************************************************************************
    ! \brief Waiting for non-blocking recv fields (into PhyDLL’s buffer)
    !******************************************************************************
    subroutine phydll_wait_irecv_f()
        call phydll_wait_irecv_cf()
    end subroutine


    !******************************************************************************
    ! \brief Get field size
    ! \param[out] integer Size
    !******************************************************************************
    subroutine phydll_get_field_size_f(size)
        implicit none
        integer(c_int), intent(out) :: size

        call phydll_get_field_size_cf(size)
    end subroutine


    !******************************************************************************
    ! \brief Get fields counts
    ! \param[out] integer Physical fields count
    ! \param[out] integer DL fields count
    !******************************************************************************
    subroutine phydll_get_field_counts_f(phy_count, dl_count)
        implicit none
        integer(c_int), intent(out) :: phy_count
        integer(c_int), intent(out) :: dl_count

        call phydll_get_field_counts_cf(phy_count, dl_count)
    end subroutine


    !******************************************************************************
    ! \brief Check if Physical solver is sending data
    ! \return logical Boolean signal
    !******************************************************************************
    function phydll_is_phy_signal_f()
        implicit none
        logical(kind=c_bool) :: phydll_is_phy_signal_f

        phydll_is_phy_signal_f = phydll_is_phy_signal_cf()
    end function


    !******************************************************************************
    ! \brief Check if current instance is Physical solver
    ! \return logical Boolean status
    !******************************************************************************
    function phydll_is_phy_instance_f()
        implicit none
        logical(kind=c_bool) :: phydll_is_phy_instance_f

        phydll_is_phy_instance_f = phydll_is_phy_instance_cf()
    end function


    !******************************************************************************
    ! \brief Check if current instance is DL engine
    ! \return logical Boolean status
    !******************************************************************************
    function phydll_is_dl_instance_f()
        implicit none
        logical(kind=c_bool) :: phydll_is_dl_instance_f

        phydll_is_dl_instance_f = phydll_is_dl_instance_cf()
    end function


    !******************************************************************************
    ! \brief Get current physical iteration
    ! \return integer physical iteration
    !******************************************************************************
    subroutine phydll_get_phy_ite_f(phy_ite)
        implicit none
        integer(kind=c_int), intent(out) :: phy_ite

        phy_ite = phydll_get_phy_ite_cf()
    end subroutine


    !******************************************************************************
    ! \brief Get current coupling iteration
    ! \return integer coupling iteration
    !******************************************************************************
    subroutine phydll_get_ite_f(ite)
        implicit none
        integer(kind=c_int), intent(out) :: ite

        ite = phydll_get_ite_cf()
    end subroutine

end module
