!*************************************************************************
! FILE      :   mod_mesh.f90
! DATE      :   06-12-2022
! AUTHORS   :   A. Serhani, C. Lapeyre, G. Staffelbach
! EMAIL     :   phydll@cerfacs.fr
! DETAILS   :   PhyDLL's mesh module
!*************************************************************************
module mod_mesh
    use mod_params

    implicit none

    type mesh_t
        ! Attributes
        integer :: dim                                                  !< Geometric dimension
        integer :: ncell                                                !< Local number of cells
        integer :: nnode                                                !< Local number of nodes
        integer :: nvertex                                              !< Number of vertices per cell
        integer :: ntcell                                               !< Number total of cells of the full mesh
        integer :: ntnode                                               !< Number total of nodes of the full mesh
        double precision, dimension(:), allocatable :: node_coords      !< Local nodes coordinates
        integer, dimension(:), allocatable :: element_to_node           !< Local connectivity
        integer, dimension(:), allocatable :: local_node_to_global      !< Table of local node to global
        integer, dimension(:), allocatable :: local_element_to_global   !< Table of local element to global
        integer, dimension(:), allocatable :: connecindex               !< Table of local connectivity indexes
    end type

    interface mesh_t
        procedure :: mesh
    end interface

    contains

    type(mesh_t) function mesh()
    !*********************************************************************
    ! Constructor of mesh_t type
    !*********************************************************************
        mesh%dim = iinit
        mesh%ncell = iinit
        mesh%nnode = iinit
        mesh%nvertex = iinit
        mesh%ntcell = iinit
    end function

end module