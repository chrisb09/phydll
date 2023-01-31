!*************************************************************************
! FILE      :   mod_phydll.f90
! DATE      :   26-11-2022
! AUTHORS   :   A. Serhani, C. Lapeyre, G. Staffelbach
! EMAIL     :   phydll@cerfacs.fr
! DETAILS   :   PhyDLL's head module
!*************************************************************************
module mod_phydll
    use mpi                         !< MPI
    use mod_params                  !< Useful params and constants
    use mod_io,     only: io_t      !< Input/Ouput module
    use mod_env,    only: env_t     !< MPI environment module
    use mod_cpl,    only: cpl_t     !< Coupling module
    use mod_mesh,   only: mesh_t    !< Mesh module

    implicit none
    type phydll_t
        ! Attributes
        type(env_t) :: env          !< MPI environment varialbse
        type(io_t) :: io            !< IO object
        type(cpl_t) :: cpl          !< Coupling parameters and fields
        type(mesh_t) :: mesh        !< Mesh object

        ! Procedures
        contains
            procedure :: init                                   !< Initialize PhyDLL
            procedure :: finalize                               !< Finalize PhyDLL

            procedure :: map_directscheme_processes             !< Map DirectScheme processes between Physical solver and DL engine

            procedure :: set_phy_mesh                           !< Set Physical mesh in PhyDLL
            procedure :: send_phy_mesh                          !< Send Physical mesh to DL engine
            procedure :: set_mesh_for_interpscheme              !< Set mesh for InterpolationScheme
            procedure :: define_locate_mesh_for_interpscheme    !< Define and locate mesh for InterpolationScheme

            procedure :: allocate_fields                        !< Allocate exchanged fields
            procedure :: set_phy_field                          !< Set Physical fields to send
            procedure :: apply_dl_field                         !< Apply received DL fields
            procedure :: check_fields_count                     !< Check count of set and applied fields

            procedure :: bcast_signal                           !< Broadcast signal to DL engine in loop-mode

            procedure :: directscheme_anb_send_phy_fields       !< DirectScheme: asynchronous non-blocking (anb) send of Physical fields
            procedure :: directscheme_nb_recv_dl_fields         !< DirectScheme: non-blocking (nb) receive of DL fields
            procedure :: directscheme_wait_anb_send             !< DirectScheme: wait for requests of anb send of Physical fields
            procedure :: directscheme_wait_nb_recv              !< DirectScheme: wait for requests of nb receive of DL fields

            procedure :: interpscheme_anb_send_phy_fields       !< InterpolationScheme: interpolation + asynchronous non-blocking (anb) send of Physical fields
            procedure :: interpscheme_nb_recv_dl_fields         !< InterpolationScheme: non-blocking (nb) receive of DL fields
            procedure :: interpscheme_wait_anb_send             !< InterpolationScheme: wait for requests of anb send of Physical fields
            procedure :: interpscheme_wait_nb_recv              !< InterpolationScheme: wait for requests of nb receive of DL fields
            procedure :: interpscheme_handle_notlocpoints       !< InterpolationScheme: handle not located points (by setting default values)
    end type

    contains

    subroutine init(self, glcomm, comm, status)
    !*********************************************************************
    ! Initialize PhyDLL:
    !   > Check if PhyDLL is enabled
    !   > Split communicators
    !   > Receive coupling parameters from Python
    !   > Initialize CWIPI (for cwipi coupling)
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !   [out]   glcomm  Global communicator (MPI_COMM_WORLD)
    !   [out]   comm    Local communicator
    !   [out]   status  Status of phydll (returns 1)
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout), target :: self
        integer, intent(out) :: glcomm
        integer, intent(out) :: comm
        integer, intent(out) :: status

        ! local
        character(len=ml) :: enable_phydll
        integer :: color = 666
        integer :: ierror

        ! Check if PhyDLL is enabled
        call get_environment_variable("ENABLE_PHYDLL", enable_phydll)
        if (enable_phydll /= "TRUE") then
            status = 0
            write(*,*) "you should enable it" ! @dbg
            return
        end if

        ! Pointers targeting
        self%env = env_t()
        self%io%env => self%env
        self%cpl = cpl_t()
        self%mesh = mesh_t()

        ! Global communicator
        self%env%glcomm = mpi_comm_world
        call mpi_comm_size(self%env%glcomm, self%env%glcomm_size, ierror)
        call mpi_comm_rank(self%env%glcomm, self%env%glcomm_rank, ierror)

        ! Local communicator
        call mpi_comm_split(self%env%glcomm, color, self%env%glcomm_rank, self%env%comm, ierror)
        call mpi_comm_size(self%env%comm, self%env%comm_size, ierror)
        call mpi_comm_rank(self%env%comm, self%env%comm_rank, ierror)

        ! Distant ranks
        self%env%host_rank = 0
        self%env%distant_rank = self%env%comm_size
        self%env%distant_size = self%env%glcomm_size - self%env%comm_size

        call self%io%log_msg("*****************************************************************************", 0)
        call self%io%log_msg("************************* <<< Welcome to PhyDLL >>> *************************", 0)
        call self%io%log_msg("*****************************************************************************", 0)

        ! Recv coupling paramters from Python
        call recv_cpl_params(self)

        if (self%cpl%is_interpolationscheme) then
            call init_cwp_interf(self)
        end if

        ! Set communicators
        glcomm = self%env%glcomm
        comm = self%env%comm
        status = 1
    end subroutine


    subroutine recv_cpl_params(self)
    !*********************************************************************
    !> Receive coupling parameters from Python: - Coupling interface (char)
    !                                           - Number of Physical fields
    !                                           - Number of DL fields
    !                                           - Coupling frequency
    !                                           - DL mesh type
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self

        ! local
        integer :: ierror
        character(len=ll) :: msg

        call mpi_bcast(self%cpl%scheme, ml, mpi_character, self%env%distant_rank, self%env%glcomm, ierror)
        call mpi_bcast(self%cpl%phy_fields%count, 1, mpi_integer, self%env%distant_rank, self%env%glcomm, ierror)
        call mpi_bcast(self%cpl%dl_fields%count, 1, mpi_integer, self%env%distant_rank, self%env%glcomm, ierror)
        call mpi_bcast(self%cpl%freq, 1, mpi_integer, self%env%distant_rank, self%env%glcomm, ierror)
        call mpi_bcast(self%cpl%dl_mesh_type, sl, mpi_character, self%env%distant_rank, self%env%glcomm, ierror)

        call self%io%log_msg("(PhyDLL) -----> coupling params:", 0)
        write(msg, "(A23, A)")  "Coupling interface = ",    self%cpl%scheme;        call self%io%log_msg(msg, 1)
        write(msg, "(A23, I0)") "Coupling frequency = ",    self%cpl%freq;          call self%io%log_msg(msg, 1)
        write(msg, "(A23, I0)") "Count of phy fields = ",  self%cpl%phy_fields%count;   call self%io%log_msg(msg, 1)
        write(msg, "(A23, I0)") "Count of dl fields = ",   self%cpl%dl_fields%count;    call self%io%log_msg(msg, 1)
        write(msg, "(A23, A)")  "DL mesh type = ",          self%cpl%dl_mesh_type;  call self%io%log_msg(msg, 1)

        self%cpl%is_interpolationscheme = trim(self%cpl%scheme) == "IS" .or. &
                                            trim(self%cpl%scheme) == "InterpolationScheme"

        self%cpl%is_directscheme = trim(self%cpl%scheme) == "DS" .or. &
                                     trim(self%cpl%scheme) == "DirectScheme"
    end subroutine


    subroutine init_cwp_interf(self)
    !*********************************************************************
    !> Exchange CWIPI parameters from Python: - CWP Geometric dimension
    !                                         - CWP Geometric tolerence
    !                                         - CWP Output frequency
    !                                         - CWP application name
    !                                         - CWP distant application name
    !> Init CWIPI coupling
    !> Create CWIPI coupling
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !*********************************************************************
#ifdef CWIPI
        use cwipi, only: cwipi_init_f, cwipi_create_coupling_f, cwipi_create_coupling_f, cwipi_cpl_parallel_with_part, &
                        cwipi_static_mesh, cwipi_solver_cell_vertex
#endif
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self

        ! local
        character(len=sl) :: output_format
        character(len=sl) :: output_format_option
        character(len=ll) :: msg
        integer :: ierror

        ! Output formats
        output_format = 'Ensight Gold'
        output_format_option = 'text'

        ! Broadcasts
        call mpi_bcast(self%cpl%dim_geom, 1, mpi_integer, self%env%distant_rank, self%env%glcomm, ierror)
        call mpi_bcast(self%cpl%tol_geom, 1, mpi_double_precision, self%env%distant_rank, self%env%glcomm, ierror)
        call mpi_bcast(self%cpl%out_freq, 1, mpi_integer, self%env%distant_rank, self%env%glcomm, ierror)
        call mpi_bcast(self%cpl%app_name, 3, mpi_character, self%env%host_rank, self%env%glcomm, ierror)
        call mpi_bcast(self%cpl%distant_name, 2, mpi_character, self%env%distant_rank, self%env%glcomm, ierror)

#ifdef CWIPI
        ! Init cwipi
        call cwipi_init_f(self%env%glcomm, self%cpl%app_name, self%env%comm)

        ! Create cwipi
        call cwipi_create_coupling_f(self%cpl%code_name, cwipi_cpl_parallel_with_part, self%cpl%distant_name, &
            self%cpl%dim_geom, self%cpl%tol_geom, cwipi_static_mesh, cwipi_solver_cell_vertex, self%cpl%out_freq, &
            output_format, output_format_option)
#endif

        call self%io%log_msg("(PhyDLL) -----> CWIPI params:", 0)
        write(msg, "(A26, I0)")    "CWP geometric dimension = ",    self%cpl%dim_geom;      call self%io%log_msg(msg, 1)
        write(msg, "(A26, F8.6)") "CWP geometric tolerence = ",     self%cpl%tol_geom;      call self%io%log_msg(msg, 1)
        write(msg, "(A26, I0)")   "CWP output frequency = ",        self%cpl%out_freq;      call self%io%log_msg(msg, 1)
        write(msg, "(A26, A)")    "CWP code name = ",               self%cpl%code_name;     call self%io%log_msg(msg, 1)
        write(msg, "(A26, A)")    "CWP application name = ",        self%cpl%app_name;      call self%io%log_msg(msg, 1)
        write(msg, "(A26, A)")    "CWP distant name = ",            self%cpl%distant_name;  call self%io%log_msg(msg, 1)
    end subroutine


    subroutine set_phy_mesh(self, dim, ncell, nnode, nvertex, ntcell, ntnode, &
        node_coords, element_to_node, local_node_to_global, local_element_to_global)
    !*********************************************************************
    !> Set Physical solver mesh
    !
    ! Args:
    !   [inout] self                    PhyDLL object
    !   [in]    dim                     Geometrical dimension
    !   [in]    ncell                   Number of mesh cells (local partition)
    !   [in]    nnode                   Number of mesh nodes (local partition)
    !   [in]    nvertex                 Number of vertices per cell
    !   [in]    ntcell                  Total number of mesh cells (all partitions)
    !   [in]    ntnode                  Total number of mesh nodes (all partitions)
    !   [in]    node_coords             Table of mesh nodes coordinates (local partition)
    !   [in]    element_to_node         Table of element-to-node connectivity (local partition)
    !   [in]    local_node_to_global    Table of local-to-global mesh node mapping
    !   [in]    local_element_to_global Table of local-to-global mesh cell mapping
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self
        integer, intent(in) :: dim
        integer, intent(in) :: ncell
        integer, intent(in) :: nnode
        integer, intent(in) :: nvertex
        integer, intent(in) :: ntcell
        integer, intent(in) :: ntnode
        double precision, dimension(:), intent(in) :: node_coords
        integer, dimension(:), intent(in) :: element_to_node
        integer, dimension(:), intent(in) :: local_node_to_global
        integer, dimension(:), intent(in) :: local_element_to_global

        ! Mesh scalars
        self%mesh%dim = dim
        self%mesh%ncell = ncell
        self%mesh%nnode = nnode
        self%mesh%nvertex = nvertex
        self%mesh%ntcell = ntcell
        self%mesh%ntnode = ntnode

        ! Mesh tables
        allocate(self%mesh%node_coords(self%mesh%nnode * self%mesh%dim));           self%mesh%node_coords = dbinit
        allocate(self%mesh%element_to_node(self%mesh%nvertex * self%mesh%ncell));   self%mesh%element_to_node = iinit
        allocate(self%mesh%local_node_to_global(self%mesh%nnode));                  self%mesh%local_node_to_global = iinit
        allocate(self%mesh%local_element_to_global(self%mesh%ncell));               self%mesh%local_element_to_global = iinit
        self%mesh%element_to_node = element_to_node
        self%mesh%node_coords = node_coords
        self%mesh%local_node_to_global = local_node_to_global
        self%mesh%local_element_to_global = local_element_to_global
    end subroutine


    subroutine set_mesh_for_interpscheme(self, ncell, nnode, nvertex, node_coords, element_to_node)
    !*********************************************************************
    !> Set CWIPI mesh for Physical solver
    !
    ! Args:
    !   [inout] self            PhyDLL object
    !   [in]    dim             Geometrical dimension
    !   [in]    ncell           Number of mesh cells (local partition)
    !   [in]    nnode           Number of mesh nodes (local partition)
    !   [in]    nvertex         Number of vertices per cell
    !   [in]    node_coords     Table of mesh nodes coordinates (local partition)
    !   [in]    element_to_node Table of element-to-node connectivity (local partition)
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self
        integer, intent(in) :: ncell
        integer, intent(in) :: nnode
        integer, intent(in) :: nvertex
        double precision, dimension(:), intent(in) :: node_coords
        integer, dimension(:), intent(in) :: element_to_node

        ! Mesh scalars
        self%mesh%nnode = nnode
        self%mesh%ncell = ncell
        self%mesh%nvertex = nvertex

        ! Mesh tables
        allocate(self%mesh%node_coords(self%mesh%nnode * self%cpl%dim_geom));       self%mesh%node_coords = dbinit
        allocate(self%mesh%element_to_node(self%mesh%nvertex * self%mesh%ncell));   self%mesh%element_to_node = iinit
        self%mesh%node_coords = node_coords
        self%mesh%element_to_node = element_to_node
    end subroutine


    subroutine define_locate_mesh_for_interpscheme(self)
    !*********************************************************************
    ! Define CWIPI mesh for Physical solver:
    !   > Modify connectivity
    !   > Create connectivity indexes
    !   > Define mesh
    !   > Run/load/save localizations
    !   > Get CWIPI not-located points and query default values from Python
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !*********************************************************************
#ifdef CWIPI
        use cwipi, only: cwipi_define_mesh_f, cwipi_locate_f, cwipi_open_location_file_f, cwipi_load_location_f, &
                        cwipi_close_location_file_f, cwipi_save_location_f, cwipi_get_n_located_pts_f, &
                        cwipi_get_n_not_located_pts_f, cwipi_get_located_pts_f, cwipi_get_not_located_pts_f
#endif
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self

        ! local
        integer, dimension(:), pointer :: connec_cwp
        integer :: i
        integer :: checknlp
        integer :: ierror
        logical :: exists
        character(len=ml) :: location_file
        character(len=ll) :: msg

        exists = .false.
        location_file = ""

        ! Modify connectivity (@dbg)
        allocate(connec_cwp(self%mesh%nvertex * self%mesh%ncell));  connec_cwp = iinit
        connec_cwp(1::self%mesh%nvertex) = self%mesh%element_to_node(1::self%mesh%nvertex)
        connec_cwp(2::self%mesh%nvertex) = self%mesh%element_to_node(3::self%mesh%nvertex)
        connec_cwp(3::self%mesh%nvertex) = self%mesh%element_to_node(2::self%mesh%nvertex)
        connec_cwp(4::self%mesh%nvertex) = self%mesh%element_to_node(4::self%mesh%nvertex)

        ! Create connecivity table (@dbg)
        allocate(self%mesh%connecindex(self%mesh%ncell+1)); self%mesh%connecindex = iinit
        do i = 1, self%mesh%ncell+1
            self%mesh%connecindex(i) = (i-1) * self%mesh%nvertex
        end do

#ifdef CWIPI
        ! Define mesh
        call cwipi_define_mesh_f(self%cpl%code_name, self%mesh%nnode, self%mesh%ncell, &
                                self%mesh%node_coords, self%mesh%connecindex, connec_cwp)

        ! Localization
        write(location_file, "(A, I0, A1, I0)") "./phydll_cwp_locfile-", self%env%comm_size, "-", self%env%distant_size
        inquire(file=location_file, exist=exists)
        if (exists) then
            call self%io%log_msg("(PhyDLL) -----> CWIPI localization file exits!. Load it ...", 0)
            write(msg, "(A,A)") "Localization file: ", location_file; call self%io%log_msg(msg, 1)
            call cwipi_open_location_file_f(self%cpl%code_name,location_file,"r")
            call cwipi_load_location_f(self%cpl%code_name)
            call cwipi_close_location_file_f(self%cpl%code_name)
        else
            call self%io%log_msg("(PhyDLL) -----> CWIPI locates meshes ...", 0)
            call cwipi_open_location_file_f(self%cpl%code_name, location_file, "w")
            call cwipi_locate_f(self%cpl%code_name)
            call cwipi_save_location_f(self%cpl%code_name)
            call cwipi_close_location_file_f(self%cpl%code_name)
            write(msg, "(A,A)") "Localization file saved: ", location_file; call self%io%log_msg(msg, 1)
        end if

        ! Get located and not-located points
        call cwipi_get_n_located_pts_f(self%cpl%code_name, self%cpl%cwp_nlocpoints)
        call cwipi_get_n_not_located_pts_f(self%cpl%code_name, self%cpl%cwp_nnotlocpoints)
#endif

        allocate(self%cpl%cwp_locpoints(self%cpl%cwp_nlocpoints));          self%cpl%cwp_locpoints = iinit
        allocate(self%cpl%cwp_notlocpoints(self%cpl%cwp_nnotlocpoints));    self%cpl%cwp_notlocpoints = iinit
#ifdef CWIPI
        call cwipi_get_located_pts_f(self%cpl%code_name, self%cpl%cwp_locpoints)
        call cwipi_get_not_located_pts_f(self%cpl%code_name, self%cpl%cwp_notlocpoints)
#endif

        call self%io%log_msg("Localization results:", 1)
        write(msg, "(A15, A20, A20)") "MPI rank", "N Located Pts", "N NotLocated Pts";                          call self%io%log_msg(msg, 1)
        write(msg, "(I15, I20, I20)") self%env%comm_rank, self%cpl%cwp_nlocpoints, self%cpl%cwp_nnotlocpoints;  call self%io%log_msg(msg, 1, .true.)

        ! Check if not located points exist, then query default values from python
        call mpi_reduce(self%cpl%cwp_nnotlocpoints, checknlp, 1, mpi_integer, mpi_max, self%env%host_rank, self%env%comm, ierror)
        call mpi_bcast(checknlp, 1, mpi_integer, self%env%host_rank, self%env%glcomm, ierror)
        allocate(self%cpl%cwp_not_loc_pts_default_vals(self%cpl%dl_fields%count));   self%cpl%cwp_not_loc_pts_default_vals = dbinit
        if (checknlp > 0) then
            call mpi_bcast(self%cpl%cwp_not_loc_pts_default_vals, self%cpl%dl_fields%count, mpi_double_precision, self%env%distant_rank, self%env%glcomm, ierror)
        end if
    end subroutine


    subroutine map_directscheme_processes(self)
    !*********************************************************************
    !> Map processes of dMPI coupling
    !> Send field size to Python (for NC coupling)
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self

        ! local
        integer :: av_t_py_q
        integer :: av_t_py_r
        integer :: ierror

        ! Map processes
        av_t_py_q = self%env%comm_size / self%env%distant_size
        av_t_py_r = MODULO(self%env%comm_size, self%env%distant_size)

        if (self%env%comm_rank / (av_t_py_q+1) < av_t_py_r) THEN
          self%env%pydest = self%env%comm_size + self%env%comm_rank / (av_t_py_q+1)
        else
          self%env%pydest = self%env%comm_size + (self%env%comm_rank - av_t_py_r) / av_t_py_q
        end if

        ! Send field size (NC)
        if (trim(self%cpl%dl_mesh_type) == "NC") then
            call mpi_send(self%mesh%nnode, 1, mpi_integer, self%env%pydest, 83, self%env%glcomm, ierror)
        end if
    end subroutine


    subroutine send_phy_mesh(self)
    !*********************************************************************
    ! Send Physical solver mesh to DL engine: - Local connectivity
    !                                         - Node coordinates
    !                                         - Local-to-global node table
    !                                         - Local-to-global cell table
    !                                         - Total number of mesh nodes
    !                                         - Total number of mesh cells
    !                                         - Number of vertices per cell
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self

        ! local
        integer, parameter :: cm_n = 4
        integer, dimension(cm_n) :: cnt
        integer, dimension(cm_n) :: tag
        integer, dimension(cm_n) :: requests
        integer, dimension(mpi_status_size, cm_n) :: statuses
        integer :: ierror

        ! Map processes
        call self%map_directscheme_processes()

        ! Local connectivity
        cnt(1) = self%mesh%nvertex * self%mesh%ncell
        tag(1) = 1
        call mpi_isend(self%mesh%element_to_node, cnt(1), mpi_integer, self%env%pydest, tag(1), self%env%glcomm, requests(1), ierror)

        ! Local nodes coordinates
        cnt(2) = self%mesh%nnode * self%mesh%dim
        tag(2) = 2
        call mpi_isend(self%mesh%node_coords, cnt(2), mpi_double_precision, self%env%pydest, tag(2), self%env%glcomm, requests(2), ierror)

        ! Local node to global table
        cnt(3) = self%mesh%nnode
        tag(3) = 3
        call mpi_isend(self%mesh%local_node_to_global, cnt(3), mpi_integer, self%env%pydest, tag(3), self%env%glcomm, requests(3), ierror)

        ! Local element to global table
        cnt(4) = self%mesh%ncell
        tag(4) = 4
        call mpi_isend(self%mesh%local_element_to_global, cnt(4), mpi_integer, self%env%pydest, tag(4), self%env%glcomm, requests(4), ierror)

        ! Wait all
        call mpi_waitall(cm_n, requests, statuses, ierror)

        ! Broadcast scalars to DL
        call mpi_bcast(self%mesh%ntnode, 1, mpi_integer, self%env%host_rank, self%env%glcomm, ierror)
        call mpi_bcast(self%mesh%ntcell, 1, mpi_integer, self%env%host_rank, self%env%glcomm, ierror)
        call mpi_bcast(self%mesh%nvertex, 1, mpi_integer, self%env%host_rank, self%env%glcomm, ierror)
    end subroutine


    subroutine allocate_fields(self)
    !*********************************************************************
    ! Allocate exchanged fields: phy_fields and dl_fields
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self

        ! Allocate Physical fields
        allocate(self%cpl%phy_fields%array(self%mesh%nnode * self%cpl%phy_fields%count))
        self%cpl%phy_fields%array = dbinit
        allocate(self%cpl%phy_fields%label(self%cpl%phy_fields%count))
        self%cpl%phy_fields%label = cinit
        allocate(self%cpl%phy_fields%index(self%cpl%phy_fields%count))
        self%cpl%phy_fields%index = iinit

        ! Allocate DL fields
        allocate(self%cpl%dl_fields%array(self%mesh%nnode * self%cpl%dl_fields%count))
        self%cpl%dl_fields%array = dbinit
        allocate(self%cpl%dl_fields%label(self%cpl%dl_fields%count))
        self%cpl%dl_fields%label = cinit
        allocate(self%cpl%dl_fields%index(self%cpl%dl_fields%count))
        self%cpl%dl_fields%index = iinit

        ! Initialize counter
        self%cpl%dl_fields%ic = self%cpl%dl_fields%count

        ! Allocate requests and statuses for separate communications
        allocate(self%env%sep_requests(self%cpl%phy_fields%count+self%cpl%dl_fields%count))
        allocate(self%env%sep_statuses(mpi_status_size, self%cpl%phy_fields%count+self%cpl%dl_fields%count))
    end subroutine


    subroutine set_phy_field(self, field, label, index)
    !*********************************************************************
    ! Accumulative set of Physical solver field to send
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !   [in]    field   Field to set
    !   [in]    label   Field label
    !   [inopt] index   Index of the field (default = 1)
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self
        double precision, dimension(:), intent(in) :: field
        character(len=*), intent(in) :: label
        integer, optional, intent(in) :: index

        ! Set field
        self%cpl%phy_fields%array(index::self%cpl%phy_fields%count) = field
        self%cpl%phy_fields%label(index) = trim(label)
        self%cpl%phy_fields%index(index) = index
    end subroutine


    subroutine apply_dl_field(self, field, label, index)
    !*********************************************************************
    ! Apply deep learing field
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !   [in]    field   Field to be applied on
    !   [in]    label   Field label
    !   [inopt] index   Index of the field (default = 1)
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self
        double precision, dimension(:), intent(inout) :: field
        character(len=*), intent(in) :: label
        integer, optional, intent(in) :: index

        ! local
        integer :: idx = 1

        ! Set index (optional)
        if (present(index)) idx = index

        ! Apply DL field
        field = self%cpl%dl_fields%array(idx::self%cpl%dl_fields%count)
        self%cpl%dl_fields%label(idx) = label
        self%cpl%dl_fields%index(idx) = idx
    end subroutine


    subroutine check_fields_count(self)
    !*********************************************************************
    ! Check if the given number of exchanged solver fields is correctly set
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self

        ! local
        character(len=ll) :: msg

        ! DL fields
        if (self%cpl%dl_fields%ic /= self%cpl%dl_fields%count) then
            write(msg, "('Count of DL fields practically applied (=', I0, ') is different from that is declared (=', I0, ')' )") &
                self%cpl%dl_fields%ic, self%cpl%dl_fields%count
            call self%io%log_err(msg)
        end if

        ! Solver fields
        if (self%cpl%phy_fields%ic /= self%cpl%phy_fields%count) then
            write(msg, "('Count of Solver fields practically set (=', I0, ') is different from that is declared (=', I0, ')' )") &
                self%cpl%phy_fields%ic, self%cpl%phy_fields%count
            call self%io%log_err(msg)
        end if
    end subroutine


    subroutine bcast_signal(self)
    !*********************************************************************
    ! Broadcast Physical solver iteration and launch coupling (for loop-mode)
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self

        ! local
        integer :: ierror

        ! Broadcast iteration
        self%cpl%bsignal = .true.
        call mpi_bcast(self%cpl%phy_ite, 1, mpi_integer, self%env%host_rank, self%env%glcomm, ierror)
    end subroutine


    subroutine directscheme_anb_send_phy_fields(self, index)
    !*********************************************************************
    ! DirectScheme:
    !   > Asychronous non-blocking send of Physical fields to DL engine
    !   > @wip separate anb send of Physical fields to DL engine
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !   [in]    index   @wip index for separate communications (default=-1)
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self
        integer, optional, intent(in) :: index

        ! local
        integer :: idx = -1
        integer :: tag
        integer :: count
        integer :: ierror
        double precision, dimension(self%mesh%nnode) :: buf

        if (present(index)) idx = index

        tag = 1777

        ! @wip Separate asynchronous non-blocking send of Physical solver fields
        if (idx > 0) then
            buf = self%cpl%phy_fields%array(idx::self%cpl%phy_fields%count)
            count = self%mesh%nnode
            call mpi_issend(buf, count, mpi_double_precision, self%env%pydest, tag, self%env%glcomm, self%env%sep_requests(idx), ierror)

        ! Compact asynchronous non-blocking send of Physical solver fields
        else if (idx == -1) then
            count = self%mesh%nnode * self%cpl%phy_fields%count
            call mpi_issend(self%cpl%phy_fields%array, count, mpi_double_precision, self%env%pydest, tag, self%env%glcomm, self%env%requests(1), ierror)

        end if
    end subroutine


    subroutine directscheme_nb_recv_dl_fields(self, index)
    !*********************************************************************
    ! DirectScheme:
    !   > Non-blocking receive of DL fields from DL engine
    !   > @wip separate nb receive of DL fields from DL engine
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !   [in]    index   @wip index for separate communications (default=-1)
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self
        integer, optional, intent(in) :: index

        ! local
        integer :: tag
        integer :: count
        integer :: ierror
        integer :: idx = -1
        double precision, dimension(self%mesh%nnode*self%cpl%dl_fields%count) :: buf

        if (present(index)) idx = index

        tag = 7111

        ! @wip Separate receive
        if (idx > 0) then
            count = self%mesh%nnode
            buf(1+(idx-1)*count : idx*count) = dbinit
            call mpi_irecv(self%cpl%dl_fields%array(idx::self%cpl%dl_fields%count), count, mpi_double_precision, self%env%pydest, tag, self%env%glcomm, self%env%sep_requests(self%cpl%phy_fields%count+idx), ierror)

        ! Compact receive
        else if (idx == -1) then
            count = self%mesh%nnode * self%cpl%dl_fields%count
            call mpi_irecv(self%cpl%dl_fields%array, count, mpi_double_precision, self%env%pydest, tag, self%env%glcomm, self%env%requests(2), ierror)

        end if
    end subroutine


    subroutine directscheme_wait_anb_send(self, index)
    !*********************************************************************
    ! DirectScheme:
    !   > Wait for requests of anb send of Physical fields to DL engine
    !   > @wip separate wait
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !   [in]    index   @wip index for separate communications (default=-1)
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self
        integer, optional, intent(in) :: index

        ! local
        integer :: ierror
        integer :: idx = -1

        if (present(index)) idx = index

        ! @wip Separate wait for send requests
        if (idx > 0) then
            call mpi_wait(self%env%sep_requests(idx), self%env%sep_statuses(:,idx), ierror)

        ! Compact wait (waitall) for send request
        else if (idx == -1) then
            call mpi_wait(self%env%requests(1), self%env%statuses(:,1), ierror)

        endif
    end subroutine


    subroutine directscheme_wait_nb_recv(self, index)
    !*********************************************************************
    ! DirectScheme:
    !   > Wait for requests of nb receive of DL fields from DL engine
    !   > @wip separate wait
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !   [in]    index   @wip index for separate communications (default=-1)
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self
        integer, optional, intent(in) :: index

        ! local
        integer :: ierror
        integer :: idx = -1

        if (present(index)) idx = index

        ! @wip Separate wait for recv requests
        if (idx > 0) then
            call mpi_wait(self%env%sep_requests(self%cpl%phy_fields%count+idx), self%env%sep_statuses(:,self%cpl%phy_fields%count+idx), ierror)

        ! Compact wait (waitall) for recv request
        else if (idx == -1) then
            call mpi_wait(self%env%requests(2), self%env%statuses(:,2), ierror)

        endif
    end subroutine


    subroutine interpscheme_anb_send_phy_fields(self, index)
    !*********************************************************************
    ! InterpolationScheme: (CWIPI)
    !   > Interpolation + asychronous non-blocking send of Physical fields to DL engine
    !   > @wip separate interp + anb send of Physical fields to DL engine
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !   [in]    index   @wip index for separate communications (default=-1)
    !*********************************************************************
#ifdef CWIPI
        use cwipi, only: cwipi_issend_f
#endif
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self
        integer, optional, intent(in) :: index

        ! local
        character(len=sl) :: exchname
        character(len=ml) :: sendfieldname
        integer :: tag
        integer :: stride
        integer :: time_step_visu
        double precision :: time_val_visu
        integer :: idx = -1
        double precision, dimension(self%mesh%nnode) :: buf

        if (present(index)) idx = index

        ! For visualization
        time_step_visu = self%cpl%phy_ite
        time_val_visu = dble(self%cpl%phy_ite)

        exchname = "phydll_s_phy"
        tag = 1777

        ! @wip Separate interp + issend (cwipi)
        if (idx > 0) then
            write(sendfieldname, "('phy_fields_', a)") trim(self%cpl%phy_fields%label(idx))
            stride = 1
            buf = self%cpl%phy_fields%array(idx::self%cpl%phy_fields%count)
#ifdef CWIPI
            call cwipi_issend_f(self%cpl%code_name, exchname, tag, &
                                stride, time_step_visu, time_val_visu, &
                                trim(sendfieldname), buf, self%env%sep_requests(idx))
#endif

        ! Compact intepr + issend (cwipi)
        else if (idx == -1) then
            sendfieldname = "phy_fields"
            stride = self%cpl%phy_fields%count
#ifdef CWIPI
            call cwipi_issend_f(self%cpl%code_name, exchname, tag, &
                                stride, time_step_visu, time_val_visu, &
                                trim(sendfieldname), self%cpl%phy_fields%array, self%env%requests(1))
#endif

        end if
    end subroutine


    subroutine interpscheme_nb_recv_dl_fields(self, index)
    !*********************************************************************
    ! InterpolationScheme: (CWIPI)
    !   > Non-blocking receive of DL fields from DL engine
    !   > @wip separate nb receive of DL fields from DL engine
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !   [in]    index   @wip index for separate communications (default=-1)
    !*********************************************************************
#ifdef CWIPI
        use cwipi, only: cwipi_ireceive_f
#endif
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self
        integer, optional, intent(in) :: index

        ! local
        character(len=sl) :: exchname
        character(len=sl) :: recvfieldname
        integer :: tag
        integer :: stride
        integer :: time_step_visu
        double precision :: time_val_visu
        integer :: idx = -1

        if (present(index)) idx = index

        ! For visualization
        time_step_visu = self%cpl%phy_ite
        time_val_visu = dble(self%cpl%phy_ite)

        ! CWIPI irecv
        exchname = "phydll_r_dl"
        recvfieldname = "dl_fields"
        tag = 7111
        stride = self%cpl%dl_fields%count
#ifdef CWIPI
        call cwipi_ireceive_f(self%cpl%code_name, exchname, tag, &
                              stride, time_step_visu, time_val_visu, &
                              recvfieldname, self%cpl%dl_fields%array, self%env%requests(2))
#endif
    end subroutine


    subroutine interpscheme_wait_anb_send(self, index)
    !*********************************************************************
    ! InterpolatonScheme:
    !   > Wait for requests of anb send of Physical fields to DL engine
    !   > @wip separate wait
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !   [in]    index   @wip index for separate communications (default=-1)
    !*********************************************************************
#ifdef CWIPI
        use cwipi, only: cwipi_wait_issend_f
#endif
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self
        integer, optional, intent(in) :: index

        ! local
        integer :: idx = -1

        if (present(index)) idx = index

        ! @dbg (to avoid W unused dummy argument)
        self%cpl%code_name = self%cpl%code_name

#ifdef CWIPI
        ! Wait of send
        if (idx > 0) then
            call cwipi_wait_issend_f(self%cpl%code_name, self%env%sep_requests(idx))
        else
            call cwipi_wait_issend_f(self%cpl%code_name, self%env%requests(1))
        end if
#endif
    end subroutine


    subroutine interpscheme_wait_nb_recv(self, index)
    !*********************************************************************
    ! InterpolationScheme:
    !   > Wait for requests of nb receive of DL fields from DL engine
    !   > @wip separate wait
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !   [in]    index   @wip index for separate communications (default=-1)
    !*********************************************************************
#ifdef CWIPI
        use cwipi, only: cwipi_wait_irecv_f
#endif
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self
        integer, optional, intent(in) :: index

        ! local
        integer :: idx = -1

        if (present(index)) idx = index

        ! @dbg (to avoid W unused dummy argument)
        self%cpl%code_name = self%cpl%code_name

        ! Wait of recv
#ifdef CWIPI
        call cwipi_wait_irecv_f(self%cpl%code_name, self%env%requests(2))
#endif
    end subroutine


    subroutine interpscheme_handle_notlocpoints(self)
    !*********************************************************************
    ! InterpolationScheme:
    !   > Handle not-located points (CWIPI)
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !*********************************************************************
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self

        ! local
        double precision, dimension(self%mesh%nnode) :: array_1
        double precision, dimension(self%mesh%nnode) :: array_2
        integer :: i

        ! Handle not-located points
        if (self%cpl%cwp_nnotlocpoints > 0) then
          do i = 1, self%cpl%dl_fields%count
            array_1(:) = self%cpl%cwp_not_loc_pts_default_vals(i)
            array_2(:) = self%cpl%dl_fields%array(i::self%cpl%dl_fields%count)
            array_1(self%cpl%cwp_locpoints) = array_2(:self%cpl%cwp_nlocpoints)
            self%cpl%dl_fields%array(i::self%cpl%dl_fields%count) = array_1(:)
          end do
        end if
    end subroutine


    subroutine finalize(self)
    !*********************************************************************
    ! Finalize PhyDLL:
    !   > Broadcast finalizing signal to DL engine
    !   > Deallocate arrays
    !   > Delete coupling (CWIPI)
    !
    ! Args:
    !   [inout] self    PhyDLL object
    !*********************************************************************
#ifdef CWIPI
        use cwipi, only: cwipi_finalize_f, cwipi_delete_coupling_f
#endif
        implicit none

        ! in/out
        class(phydll_t), intent(inout) :: self

        ! local
        integer :: sig
        integer :: ierror

        ! Send signal
        if (self%cpl%bsignal) then
            sig = -1
            call mpi_bcast(sig , 1, mpi_integer, self%env%host_rank, self%env%glcomm, ierror)
        end if

        ! Deallocate fields
        deallocate(self%cpl%phy_fields%array)
        deallocate(self%cpl%phy_fields%label)
        deallocate(self%cpl%phy_fields%index)
        deallocate(self%cpl%dl_fields%array)
        deallocate(self%cpl%dl_fields%label)
        deallocate(self%cpl%dl_fields%index)

        deallocate(self%env%sep_requests)
        deallocate(self%env%sep_statuses)

        ! Deallocate mesh arrays
        if (trim(self%cpl%dl_mesh_type) /= "NC") then
            deallocate(self%mesh%node_coords)
            deallocate(self%mesh%element_to_node)

            if (trim(self%cpl%dl_mesh_type) == "phymesh") then
                deallocate(self%mesh%local_node_to_global)
                deallocate(self%mesh%local_element_to_global)
            end if
        end if

        ! Deallocate CWIPI arrays
        if (self%cpl%is_interpolationscheme) then
            deallocate(self%mesh%connecindex)
            deallocate(self%cpl%cwp_locpoints)
            deallocate(self%cpl%cwp_notlocpoints)
            deallocate(self%cpl%cwp_not_loc_pts_default_vals)
#ifdef CWIPI
            ! call cwipi_finalize_f
            call cwipi_delete_coupling_f(self%cpl%code_name)
#endif
        end if
    end subroutine
end module
