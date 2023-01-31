!*************************************************************************
! FILE      :   mod_cpl.f90
! DATE      :   06-12-2022
! AUTHORS   :   A. Serhani, C. Lapeyre, G. Staffelbach
! EMAIL     :   phydll@cerfacs.fr
! DETAILS   :   PhyDLL's coupling variables and parameters
!*************************************************************************
module mod_cpl
    use mod_params

    implicit none

    ! Exchanged fields derived type
    type fields_t
        double precision, dimension(:), allocatable :: array        ! Fields array
        character(len=ml), dimension(:), allocatable :: label       ! Fields labels
        integer, dimension(:), allocatable :: index                 ! Fields indexes
        integer :: count                                            ! Fields count
        integer :: ic                                               ! Fields counter (to check the number of set and applied fields)
    end type

    type cpl_t
        ! Attributes
        type(fields_t) :: phy_fields                                ! Physical solver fields derived type
        type(fields_t) :: dl_fields                                 !> Array of DL fields derived type
        character(len=ml) :: scheme                                 !> Coupling scheme
        character(len=sl) :: dl_mesh_type = "None"                  !> DL engine mesh type
        integer :: freq                                             !> Coupling frequency
        integer :: phy_ite                                          !> Physical solver iteration
        integer :: ite                                              !> Coupling iteration
        logical :: is_cpl_ite                                       !> Check if it is a coupling iteration
        character(len=6) :: code_name = "phydll"                    !> CWIPI's code name
        character(len=3) :: app_name = "phy"                        !> CWIPI's application name
        character(len=2) :: distant_name                            !> CWIPI's distant application name
        integer :: dim_geom                                         !> CWIPI's geometric dimension
        double precision :: tol_geom                                !> CWIPI's geometric tolerence
        integer :: out_freq                                         !> CWIPI's mesh/fields output frequency
        integer :: cwp_nlocpoints                                   !> CWIPI's number of located points
        integer :: cwp_nnotlocpoints                                !> CWIPI's number of not-located points
        integer, dimension(:), allocatable :: cwp_locpoints         !> CWIPI's array of located points
        integer, dimension(:), allocatable :: cwp_notlocpoints      !> CWIPI's array of not-located points
        double precision, dimension(:), allocatable :: cwp_not_loc_pts_default_vals !> CWIPI's default values fof not-located points
        integer :: cpt_phy_fields                                   !> Counter for Physical solver fields
        integer :: cpt_dl_fields                                    !> Counter for deep learning fields
        logical :: is_directscheme                                  !> Check if direct scheme is enabled
        logical :: is_interpolationscheme                           !> Check if interpolation scheme is enabled
        logical :: bsignal
    end type

    interface cpl_t
        procedure :: cpl
    end interface

    contains

    type(cpl_t) function cpl()
    !*********************************************************************
    ! Constructor of cpl_t type
    !*********************************************************************
        cpl%phy_fields%count = iinit
        cpl%phy_fields%ic = 0
        cpl%dl_fields%count = iinit
        cpl%dl_fields%ic = 0
        cpl%freq = iinit
        cpl%dim_geom = iinit
        cpl%out_freq = iinit
        cpl%tol_geom = dbinit
        cpl%cwp_nlocpoints = iinit
        cpl%cwp_nnotlocpoints = iinit
        cpl%is_cpl_ite = .false.
        cpl%phy_ite = 0
        cpl%ite = 0
        cpl%is_directscheme = .false.
        cpl%is_interpolationscheme = .false.
        cpl%bsignal = .false.
    end function
end module