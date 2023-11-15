!******************************************************************************
! \file src/fortran/phydll_cf.f90
! \brief Fortran module creating interface of PhyDLL C-written subroutines
! \authors A. Serhani, C. Lapeyre, G. Staffelbach
! \mainpage phydll.readthedocs.io
! \email phydll@cerfacs.fr
! \date Wed, May 03, 2023
! \copyright CeCILL-B FREE SOFTWARE LICENSE AGREEMENT
! \copyright COPYRIGHT (C) [2023] [CERFACS]
!******************************************************************************

module phydll_cf

    interface
        !******************************************************************************
        ! \interface phydll_init_cf
        ! \brief Fortran binding of C function: phydll_init
        ! \param[in] c_char Instance name
        !******************************************************************************
        subroutine phydll_init_cf(instance) bind(c, name="phydll_init")
            use iso_c_binding, only : c_char
            implicit none
            character(kind=c_char), dimension(*), intent(in) :: instance
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_get_local_mpi_fcomm_cf
        ! \brief Fortran binding of C function: phydll_get_local_mpi_fcomm
        ! \return c_int Local mpi communicator
        !******************************************************************************
        function phydll_get_local_mpi_fcomm_cf() bind(c, name="phydll_get_local_mpi_fcomm")
            use iso_c_binding, only : c_int
            implicit none
            integer(c_int) :: phydll_get_local_mpi_fcomm_cf
        end function
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_finalize_cf
        ! \brief Fortran binding of C function: phydll_finalize
        !******************************************************************************
        subroutine phydll_finalize_cf() bind(c, name="phydll_finalize")
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_define_phy_cf
        ! \brief Fortran binding of C function: phydll_define_phy
        ! \param[in] c_int Fields count
        ! \param[in] c_int Field size
        !******************************************************************************
        subroutine phydll_define_phy_cf(count, size) bind(c, name="phydll_define_phy")
            use iso_c_binding, only : c_int
            implicit none
            integer(c_int), value :: count
            integer(c_int), value :: size
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_define_phy_with_mesh_cf
        ! \brief Fortran binding of C function: phydll_define_phy_with_mesh
        ! \param [in] c_int Number of physical fields to send
        ! \param [in] c_int Geometric dimension
        ! \param [in] c_int Number of local mesh cells
        ! \param [in] c_int Number of local mesh nodes
        ! \param [in] c_int Number of global (full) mesh cells
        ! \param [in] c_int Number of global (full) mesh nodes (without duplication)
        ! \param [in] c_int Number of nodes per element (eg. quad=4, tetra=4, hexa=8, prism=6, ...)
        ! \param [in] c_ptr Local connectivity table (element to node), len=nvert*ncell
        ! \param [in] c_ptr Local coordinates table, len=geodim*nnode
        ! \param [in] c_ptr Table of local to global cell numerotation
        ! \param [in] c_ptr Table of local to global node numerotation         !******************************************************************************
        subroutine phydll_define_phy_with_mesh_cf(count, geodim, ncell, nnode, ntcell, ntnode, nvert, &
                                            connec, coords, local_cell_to_global, local_node_to_global) &
                                            bind(c, name="phydll_define_phy_with_mesh")
            use iso_c_binding, only : c_int, c_ptr
            implicit none
            integer(c_int), value :: count
            integer(c_int), value :: geodim
            integer(c_int), value :: ncell
            integer(c_int), value :: nnode
            integer(c_int), value :: ntcell
            integer(c_int), value :: ntnode
            integer(c_int), value :: nvert
            type(c_ptr), intent(in) :: connec
            type(c_ptr), intent(in) :: coords
            type(c_ptr), intent(in) :: local_cell_to_global
            type(c_ptr), intent(in) :: local_node_to_global
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_define_dl_cf
        ! \brief Fortran binding of C function: phydll_define_dl
        ! \param[in] c_int Fields count
        !******************************************************************************
        subroutine phydll_define_dl_cf(count) bind(c, name="phydll_define_dl")
            use iso_c_binding, only : c_int
            implicit none
            integer(c_int), value :: count
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_set_field_cf
        ! \brief Fortran binding of C function: phydll_set_field
        ! \param[in] c_ptr Field array
        ! \param[in] c_char Field label
        !******************************************************************************
        subroutine phydll_set_field_cf(field, label) bind(c, name="phydll_set_field")
            use iso_c_binding, only : c_ptr, c_char
            implicit none
            type(c_ptr), intent(in) :: field
            character(kind=c_char), dimension(*), intent(in) :: label
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_get_field_cf
        ! \brief Fortran binding of C function: phydll_get_field
        ! \param[out] c_ptr Field array
        ! \param[out] c_char Field label
        !******************************************************************************
        subroutine phydll_get_field_cf(field, label) bind(c, name="phydll_get_field")
            use iso_c_binding, only : c_ptr, c_char
            implicit none
            type(c_ptr), intent(out) :: field
            character(kind=c_char), dimension(*), intent(out) :: label
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_send_cf
        ! \brief Fortran binding of C function: phydll_send
        !******************************************************************************
        subroutine phydll_send_cf() bind(c, name="phydll_send")
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_isend_cf
        ! \brief Fortran binding of C function: phydll_isend
        !******************************************************************************
        subroutine phydll_isend_cf() bind(c, name="phydll_isend")
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_wait_isend_cf
        ! \brief Fortran binding of C function: phydll_wait_isend
        !******************************************************************************
        subroutine phydll_wait_isend_cf() bind(c, name="phydll_wait_isend")
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_recv_cf
        ! \brief Fortran binding of C function: phydll_recv
        !******************************************************************************
        subroutine phydll_recv_cf() bind(c, name="phydll_recv")
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_irecv_cf
        ! \brief Fortran binding of C function: phydll_irecv
        !******************************************************************************
        subroutine phydll_irecv_cf() bind(c, name="phydll_irecv")
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_wait_irecv_cf
        ! \brief Fortran binding of C function: phydll_wait_irecv
        !******************************************************************************
        subroutine phydll_wait_irecv_cf() bind(c, name="phydll_wait_irecv")
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_get_field_size_cf
        ! \brief Fortran binding of C function: phydll_get_field_size
        ! \param[out] c_int Field size
        !******************************************************************************
        subroutine phydll_get_field_size_cf(size) bind(c, name="phydll_get_field_size")
            use iso_c_binding, only : c_int
            implicit none
            integer(c_int), intent(out) :: size
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_get_field_counts_cf
        ! \brief Fortran binding of C function: phydll_get_field_counts
        ! \param[out] c_int Physical fields count
        ! \param[out] c_int DL fields count
        !******************************************************************************
        subroutine phydll_get_field_counts_cf(phy_count, dl_count) bind(c, name="phydll_get_field_counts")
            use iso_c_binding, only : c_int
            implicit none
            integer(c_int), intent(out) :: phy_count
            integer(c_int), intent(out) :: dl_count
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_is_phy_signal_cf
        ! \brief Fortran binding of C function: phydll_is_phy_signal
        ! \return c_bool Boolean status
        !******************************************************************************
        function phydll_is_phy_signal_cf() bind(c, name="phydll_is_phy_signal")
            use iso_c_binding, only : c_bool
            implicit none
            logical(kind=c_bool) :: phydll_is_phy_signal_cf
        end function
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_is_phy_instance_cf
        ! \brief Fortran binding of C function: phydll_is_phy_instance
        ! \return c_bool Boolean status
        !******************************************************************************
        function phydll_is_phy_instance_cf() bind(c, name="phydll_is_phy_instance")
            use iso_c_binding, only : c_bool
            implicit none
            logical(kind=c_bool) :: phydll_is_phy_instance_cf
        end function
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_is_phy_instance_cf
        ! \brief Fortran binding of C function: phydll_is_phy_instance
        ! \return c_bool Boolean status
        !******************************************************************************
        function phydll_is_dl_instance_cf() bind(c, name="phydll_is_dl_instance")
            use iso_c_binding, only : c_bool
            implicit none
            logical(kind=c_bool) :: phydll_is_dl_instance_cf
        end function
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_get_phy_ite_cf
        ! \brief Fortran binding of C function: phydll_get_phy_ite
        ! \param[out] c_int Current physical ite
        !******************************************************************************
        function phydll_get_phy_ite_cf() bind(c, name="phydll_get_phy_ite")
            use iso_c_binding, only : c_int
            implicit none
            integer(c_int) :: phydll_get_phy_ite_cf
        end function
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_get_ite_cf
        ! \brief Fortran binding of C function: phydll_get_ite
        ! \param[out] c_int Current coupling ite
        !******************************************************************************
        function phydll_get_ite_cf() bind(c, name="phydll_get_ite")
            use iso_c_binding, only : c_int
            implicit none
            integer(c_int) :: phydll_get_ite_cf
        end function
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_opt_set_freq_cf
        ! \brief Fortran binding of C function: phydll_opt_set_freq
        ! \param[in] c_int Coupling frequency
        !******************************************************************************
        subroutine phydll_opt_set_freq_cf(freq) bind(c, name="phydll_opt_set_freq")
            use iso_c_binding, only : c_int
            implicit none
            integer(c_int), value :: freq
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_opt_set_output_freq_cf
        ! \brief Fortran binding of C function: phydll_opt_set_output_freq
        ! \param[in] c_int Output frequency
        !******************************************************************************
        subroutine phydll_opt_set_output_freq_cf(output_freq) bind(c, name="phydll_opt_set_output_freq")
            use iso_c_binding, only : c_int
            implicit none
            integer(c_int), value :: output_freq
        end subroutine
    end interface


    interface
        !******************************************************************************
        ! \interface phydll_opt_enable_cpl_loop_cf
        ! \brief Fortran binding of C function: phydll_opt_enable_cpl_loop
        !******************************************************************************
        subroutine phydll_opt_enable_cpl_loop_cf() bind(c, name="phydll_opt_enable_cpl_loop")
        end subroutine
    end interface

end module
