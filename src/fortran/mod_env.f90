!*************************************************************************
! FILE      :   mod_env.f90
! DATE      :   06-12-2022
! AUTHORS   :   A. Serhani, C. Lapeyre, G. Staffelbach
! EMAIL     :   phydll@cerfacs.fr
! DETAILS   :   PhyDLL's MPI environment
!*************************************************************************
module mod_env
    use mod_params
    use mpi, only: mpi_status_size

    implicit none

    type env_t
        integer :: glcomm                                       !< Global communicator (Phy+DL) = MPI_COMM_WORLD
        integer :: glcomm_size                                  !< Size of global communicator (glcomm)
        integer :: glcomm_rank                                  !< Rank in global communicator (glcomm)
        integer :: comm                                         !< Local communicator (Physical solver only)
        integer :: comm_size                                    !< Size of local communicator (comm)
        integer :: comm_rank                                    !< Rank in local communicator (comm)
        integer :: host_rank                                    !< Host rank (Physical solver master rank)
        integer :: distant_rank                                 !< Distant rank (DL master rank)
        integer :: distant_size                                 !< Distant size (Size of DL comm)
        integer :: pydest                                       !< Corresponding DL rank (for dMPI/NC couplings)
        logical :: enabled                                      !< Check if PhyDLL is enabled
        integer, dimension(2) :: requests                       !< Array of MPI requests (1) issend (2) irecv
        integer, dimension(mpi_status_size, 2) :: statuses      !< Array of MPI statuses of (1) issend (2) irecv
        integer, dimension(:), allocatable :: sep_requests      !< @dbg Array of MPI requests for separate communications
        integer, dimension(:, :), allocatable :: sep_statuses   !< @dbg Array of MPI statuses of separate communications
    end type

    interface env_t
        procedure :: env
    end interface

    contains

    type(env_t) function env()
    !*********************************************************************
    ! Constructor of env_t type
    !*********************************************************************
        env%glcomm = iinit
        env%glcomm_size = iinit
        env%glcomm_rank = iinit
        env%comm = iinit
        env%comm_size = iinit
        env%host_rank = iinit
        env%distant_rank = iinit
        env%distant_size = iinit
        env%pydest = iinit
        env%requests = iinit
        env%statuses = iinit
    end function
end module
