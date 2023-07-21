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
        ! Attributes
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
        character(len=sl) :: topology_type                              !< Mesh element topology type

        contains
            procedure :: get_topology

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

    subroutine get_topology(self)
        implicit none

        class(mesh_t), intent(inout) :: self

        if (self%nvertex == 3) then
            self%topology_type = "Triangle"

        else if (self%nvertex == 4 .and. self%dim == 2) then
            self%topology_type = "Quadrilateral"

        else if (self%nvertex == 4 .and. self%dim == 3) then
            self%topology_type = "Tetrahedron"

        else if (self%nvertex == 6) then
            self%topology_type = "Wedge"

        else if (self%nvertex == 8) then
            self%topology_type = "Hexahedron"

        end if
    end subroutine
end module
