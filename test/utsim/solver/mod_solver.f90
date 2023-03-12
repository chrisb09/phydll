!*************************************************************************
! FILE      :   mod_solver.f90
! DATE      :   13-02-2022
! AUTHORS   :   A. Serhani, C. Lapeyre, G. Staffelbach
! EMAIL     :   phydll@cerfacs.fr
! DETAILS   :   UNITTEST of PhyDLL: solver module
!*************************************************************************
module mod_solver
    use mpi
    use hdf5

    implicit none

    ! Initialization parameters
    integer, parameter :: iinit = -99999
    double precision, parameter :: rinit = -99999.99999
    integer, parameter :: ll = 1024

    type solver_t
        integer :: comm = mpi_comm_world
        integer :: comm_size
        integer :: comm_rank
        integer :: ierr

        double precision :: time
        integer :: wrkarr = 0
        integer :: wrkh5 = 0
        logical :: db_mesh_info = .false.

        character(len=ll) :: topology_type
        character(len=ll) :: outmeshfile

        integer :: dim
        integer :: ncell
        integer :: nnode
        integer :: nvertex
        integer :: ntcell
        integer :: ntnode
        double precision, dimension(:), allocatable :: coords
        integer, dimension(:), allocatable :: element_to_node
        integer, dimension(:), allocatable :: local_node_to_global
        integer, dimension(:), allocatable :: local_element_to_global

        contains

        procedure :: initialize
        procedure :: init_solver
        procedure :: finalize

        procedure :: read_mesh
        procedure :: write_mesh_partitions
        procedure :: write_xdmf

        procedure :: read_h5_dataset
        procedure :: write_h5_dataset

        procedure :: log
        procedure :: log_array
        procedure :: progress_bar
    end type

    contains

    subroutine initialize(self)
    !*********************************************************************
    ! Initiliaze MPI
    !*********************************************************************
        implicit none

        class(solver_t), intent(inout) :: self

        call mpi_init(self%ierr)
        self%time = mpi_wtime()
    end subroutine


    subroutine init_solver(self)
    !*********************************************************************
    ! Initialize solver
    !*********************************************************************
        implicit none

        class(solver_t), intent(inout) :: self
        integer :: herr

        call h5open_f(herr)

        call mpi_comm_size(self%comm, self%comm_size, self%ierr)
        call mpi_comm_rank(self%comm, self%comm_rank, self%ierr)
    end subroutine

    subroutine finalize(self)
    !*********************************************************************
    ! Finalize solver
    !*********************************************************************
        implicit none

        class(solver_t), intent(inout) :: self

        character(len=ll) :: message

        deallocate(self%coords)
        deallocate(self%element_to_node)
        deallocate(self%local_node_to_global)
        deallocate(self%local_element_to_global)

        write(message, "(a, 'FULL TIME = ', f13.6, ' s', a)") ""//new_line("a"), mpi_wtime()-self%time, ""//new_line("a")
        if (self%db_mesh_info) call self%log(message)

        call mpi_finalize(self%ierr)
    end subroutine


    subroutine read_mesh(self)
    !*********************************************************************
    ! Read mesh and partitioning (el2part.h5 file)
    ! Compute the arguments of PhyDLL's mesh definition
    !*********************************************************************
        implicit none

        class(solver_t), intent(inout) :: self

        character(len=ll) :: filename
        character(len=ll) :: groupname
        character(len=ll) :: datasetname

        integer :: global_connec_dim
        integer, dimension(:), allocatable :: global_connec

        integer, dimension(:), allocatable :: recvcounts
        integer, dimension(:), allocatable :: recvdispls

        integer :: el_2_part_dim
        integer, dimension(:), allocatable :: el_2_part
        integer, dimension(:), allocatable :: el_2_part_all

        double precision, dimension(:), allocatable :: xglob
        double precision, dimension(:), allocatable :: yglob
        double precision, dimension(:), allocatable :: zglob

        integer, dimension(:), allocatable :: temp

        integer(hid_t) :: hash_file, hash_grp
        character(len=ll) :: hash_tables
        logical :: hash_exists

        character(len=ll) :: message

        integer :: i, j, k
        logical :: to_cycle

        double precision :: tic, toc

        ! READ GLOBAL CONNEC
        write(filename, "('el2part_', i0, '.h5')") self%comm_size
        write(groupname, "('part', i7.7)") self%comm_rank + 1
        call get_environment_variable("EL2PART_ELEMENT_TYPE", datasetname) ! export EL2PART_ELEMENT_TYPE=`h5ls el2part_4.h5/part0000001 | tail -1 | awk '{ print $1}'`
        call self%read_h5_dataset(trim(filename), trim(groupname), trim(datasetname), global_connec_dim, array_int=global_connec)
        if (self%db_mesh_info) call self%log_array(name="global_connec", array=global_connec, blk=.true., wrk=self%wrkarr)

        ! COMPUTE NVERTEXT & NCELL
        select case (trim(datasetname))
        case ("tri->node")
            self%nvertex = 3
            self%dim = 2
            self%topology_type = "Triangle"

        case ("qua->node")
            self%nvertex = 4
            self%dim = 2
            self%topology_type = "Quadrilateral"

        case ("tet->node")
            self%nvertex = 4
            self%dim = 3
            self%topology_type = "Tetrahedron"

        case ("hex->node")
            self%nvertex = 8
            self%dim = 3
            self%topology_type = "Hexahedron"

        case ("pri->node")
            self%nvertex = 6
            self%dim = 3
            self%topology_type = "Wedge"

        end select
        self%ncell = global_connec_dim / self%nvertex

        ! READ EL_2_PART
        write(filename, "('el2part_', i0, '.h5')") self%comm_size
        write(groupname, "('part', i7.7)") self%comm_rank + 1
        datasetname = "el_2_part"
        call self%read_h5_dataset(trim(filename), trim(groupname), trim(datasetname), el_2_part_dim, array_int=el_2_part)
        if (self%db_mesh_info) call self%log_array(name="el_2_part", array=el_2_part, blk=.true., wrk=self%wrkarr)

        ! READ COORDINATES
        call self%read_h5_dataset("meshfile.h5", "Coordinates", "x", self%ntnode, array_real=xglob)
        call self%read_h5_dataset("meshfile.h5", "Coordinates", "y", self%ntnode, array_real=yglob)
        if (self%dim == 3) call self%read_h5_dataset("meshfile.h5", "Coordinates", "z", self%ntnode, array_real=zglob)

        ! COMPUTE NTNODE & NTCELL
        if (self%db_mesh_info) call self%log("ALLREDUCE (ntcell) ..."); tic = mpi_wtime()
        call mpi_allreduce(maxval(global_connec), self%ntnode, 1, MPI_INTEGER, MPI_MAX, self%comm, self%ierr)
        call mpi_allreduce(self%ncell, self%ntcell, 1, MPI_INTEGER, MPI_SUM, self%comm, self%ierr)
        toc = mpi_wtime(); write(message, "('DONE - ', f13.6, ' s', a)") (toc-tic), ""//new_line("a"); if (self%db_mesh_info) call self%log(message)

        ! GET EL_2_PART_ALL
        if (self%db_mesh_info) call self%log("ALLGATHER (el_2_part_all) ..."); tic = mpi_wtime()
        allocate(el_2_part_all(self%ntcell)); el_2_part_all = iinit
        allocate(recvcounts(self%comm_size)); recvcounts = iinit
        allocate(recvdispls(self%comm_size)); recvdispls = iinit
        call mpi_allgather(el_2_part_dim, 1, MPI_INTEGER, recvcounts, 1, MPI_INTEGER, self%comm, self%ierr)
        recvdispls(1) = 0
        do i = 2, self%comm_size
            recvdispls(i) = recvdispls(i-1) + recvcounts(i-1)
        end do
        call mpi_allgatherv(el_2_part, el_2_part_dim, MPI_INTEGER, el_2_part_all, recvcounts, recvdispls, MPI_INTEGER, self%comm, self%ierr)
        el_2_part_all = el_2_part_all - 1
        toc = mpi_wtime(); write(message, "('DONE - ', f13.6, ' s', a)") (toc-tic), ""//new_line("a"); if (self%db_mesh_info) call self%log(message)
        if (self%db_mesh_info) call self%log_array(name="el_2_part_all", array=el_2_part_all, blk=.true., wrk=self%wrkarr)

        ! COMPUTE LOCAL_ELEMENT_TO_GLOBAL
        if (self%db_mesh_info) call self%log("COMPUTE (local_element_to_global) ..."); tic = mpi_wtime()
        allocate(self%local_element_to_global(self%ncell)); self%local_element_to_global = iinit
        j = 1
        do i = 1, self%ntcell
            if (el_2_part_all(i) == self%comm_rank) then
                self%local_element_to_global(j) = i
                j = j + 1
            end if
        end do
        toc = mpi_wtime(); write(message, "('DONE - ', f13.6, ' s', a)") (toc-tic), ""//new_line("a"); if (self%db_mesh_info) call self%log(message)
        if (self%db_mesh_info) call self%log_array(name="local_element_to_global", array=self%local_element_to_global, blk=.true., wrk=self%wrkarr)

        ! COMPUTE ELEMENT_TO_NODE
        write(message, "('COMPUTE (element_to_node) [loop range = ', i0, '] ...')") self%ncell*self%nvertex
        if (self%db_mesh_info) call self%log(message); tic = mpi_wtime()
        allocate(self%element_to_node(self%ncell*self%nvertex)); self%element_to_node = iinit
        allocate(temp(self%ncell*self%nvertex)); temp = iinit ! @dbg self%ntnode

        write(hash_tables, "('./HASH_TABLES/file_', i0, '-', i0, '_', i0, '-', i0, '.h5')") self%comm_rank, self%comm_size, self%ntnode, self%ntcell
        inquire(file=hash_tables, exist=hash_exists)

        if (hash_exists) then

            call self%read_h5_dataset(trim(hash_tables), "arrays", "element_to_node", array_dim=i, array_int=self%element_to_node)
            call self%read_h5_dataset(trim(hash_tables), "arrays", "temp", array_dim=i, array_int=temp)

        else
            self%element_to_node(1) = 1
            temp(1) = global_connec(1)
            k = 2
            do i = 2, self%ncell*self%nvertex
                call self%progress_bar(i, self%ncell*self%nvertex)
                !write(message, "(t4, i0, '/', i0, ' [', f5.2, ' %] ...')") i, self%ncell*self%nvertex, dble(i)/dble(self%ncell*self%nvertex)*100; if (self%db_mesh_info) call self%log(message)
                to_cycle = .false.
                do j = 1, i-1
                    if (global_connec(i) == global_connec(j)) then
                        self%element_to_node(i) = self%element_to_node(j)
                        to_cycle = .true.
                        exit
                    end if
                end do
                if (to_cycle) cycle
                self%element_to_node(i) = k
                temp(i) = global_connec(i)
                k = k + 1
            end do
            toc = mpi_wtime(); write(message, "('DONE - ', f13.6, ' s', a)") (toc-tic), ""//new_line("a"); if (self%db_mesh_info) call self%log(message)
            call h5fcreate_f(hash_tables, H5F_ACC_TRUNC_F, hash_file, self%ierr)
            call h5gcreate_f(hash_file, "arrays", hash_grp, self%ierr)
            call self%write_h5_dataset(file=hash_grp, datasetname="element_to_node", buff=self%element_to_node)
            call self%write_h5_dataset(file=hash_grp, datasetname="temp", buff=temp)
            CALL h5gclose_f(hash_grp, self%ierr)
            call h5fclose_f(hash_file, self%ierr)

        end if
        toc = mpi_wtime(); write(message, "('DONE - ', f13.6, ' s', a)") (toc-tic), ""//new_line("a"); if (self%db_mesh_info) call self%log(message)
        if (self%db_mesh_info) call self%log_array(name="element_to_node", array=self%element_to_node, blk=.true., wrk=self%wrkarr)


        ! COMPUTE LOCAL_NODE_TO_GLOBAL
        write(message, "('COMPUTE (local_node_to_global) [loop range = ', i0, '] ...')") self%ncell*self%nvertex
        if (self%db_mesh_info) call self%log(message); tic = mpi_wtime()
        self%nnode = count(temp >= 1)
        allocate(self%local_node_to_global(self%nnode)); self%local_node_to_global = iinit
        j = 1
        do i = 1, self%ncell*self%nvertex ! @dbg self%ntnode
            call self%progress_bar(i, self%ncell*self%nvertex)
            if (temp(i) >= 1) then
                self%local_node_to_global(j) = temp(i)
                j = j + 1
            end if
        end do
        toc = mpi_wtime(); write(message, "('DONE - ', f13.6, ' s', a)") (toc-tic), ""//new_line("a"); if (self%db_mesh_info) call self%log(message)
        if (self%db_mesh_info) call self%log_array(name="local_node_to_global", array=self%local_node_to_global, blk=.true., wrk=self%wrkarr)

        ! if (self%db_mesh_info) call self%log_array(name="UNIT TEST:element_to_node", array=global_connec-self%element_to_node(self%local_node_to_global), blk=.true., wrk=0) !wrk=-1)

        ! COMPUTE NODE COORDINATES
        if (self%db_mesh_info) call self%log("COMPUTE (coords) ..."); tic = mpi_wtime()
        allocate(self%coords(self%dim*self%nnode)); self%coords = rinit
        self%coords(1::self%dim) = xglob(self%local_node_to_global)
        self%coords(2::self%dim) = yglob(self%local_node_to_global)
        if (self%dim == 3) self%coords(3::self%dim) = zglob(self%local_node_to_global)
        toc = mpi_wtime(); write(message, "('DONE - ', f13.6, ' s', a)") (toc-tic), ""//new_line("a"); if (self%db_mesh_info) call self%log(message)

        ! if (self%db_mesh_info) call self%log_array(name="x", array_real=self%coords(1::self%dim), wrk=self%wrkarr, blk=.true.)
        ! if (self%db_mesh_info) call self%log_array(name="y", array_real=self%coords(2::self%dim), wrk=self%wrkarr, blk=.true.)
        ! if (self%dim == 3) if (self%db_mesh_info) call self%log_array(name="z", array_real=self%coords(3::self%dim), wrk=self%wrkarr, blk=.true.)

        ! PRINT MESH INFO
        write(message, "(a)") ""//new_line("a")
        write(message, "(a, 4x, 'ndim = ', i0, a)") trim(message), self%dim, " "//new_line("a")
        write(message, "(a, 4x, 'nvertex = ', i0, a)") trim(message), self%nvertex, " "//new_line("a")
        write(message, "(a, 4x, 'ncell = ', i0, a)") trim(message), self%ncell, " "//new_line("a")
        write(message, "(a, 4x, 'nnode = ', i0, a)") trim(message), self%nnode, " "//new_line("a")
        write(message, "(a, 4x, 'ntcell = ', i0, a)") trim(message), self%ntcell, " "//new_line("a")
        write(message, "(a, 4x, 'ntnode = ', i0, a)") trim(message), self%ntnode, " "!//new_line("a")
        if (self%db_mesh_info) call self%log(message=message, blk=.true., wrk=self%wrkarr)

        deallocate(temp)
        deallocate(recvcounts)
        deallocate(recvdispls)
        deallocate(el_2_part_all)
        deallocate(el_2_part)
        deallocate(global_connec)
        deallocate(xglob)
        deallocate(yglob)
        if (self%dim == 3) deallocate(zglob)
        !call exit(0)
    end subroutine


    subroutine write_mesh_partitions(self)
    !*********************************************************************
    ! Write mesh information into h5 file
    !*********************************************************************
        implicit none

        class(solver_t), intent(inout) :: self

        integer(hid_t) :: file
        integer :: herr
        double precision, dimension(self%nnode) :: contgarr

        write(self%outmeshfile, "('./mesh_', i0, '-', i0, '_', i0, '-', i0, '.h5')") self%comm_rank, self%comm_size, self%ntnode, self%ntcell
        call h5fcreate_f("./OUTPUTED_MESH_PARTITIONS/"//trim(self%outmeshfile), H5F_ACC_TRUNC_F, file, herr)

        call self%write_h5_dataset(file=file, datasetname="dim", buff=(/self%dim/))
        call self%write_h5_dataset(file=file, datasetname="nvertex", buff=(/self%nvertex/))
        call self%write_h5_dataset(file=file, datasetname="ncell", buff=(/self%ncell/))
        call self%write_h5_dataset(file=file, datasetname="nnode", buff=(/self%nnode/))
        call self%write_h5_dataset(file=file, datasetname="ntcell", buff=(/self%ntcell/))
        call self%write_h5_dataset(file=file, datasetname="ntnode", buff=(/self%ntnode/))

        call self%write_h5_dataset(file=file, datasetname="element_to_node", buff=self%element_to_node)
        call self%write_h5_dataset(file=file, datasetname="local_node_to_global", buff=self%local_node_to_global)
        call self%write_h5_dataset(file=file, datasetname="local_element_to_global", buff=self%local_element_to_global)


        contgarr(:) = self%coords(1::self%dim)
        call self%write_h5_dataset(file=file, datasetname="x", buff_real=contgarr)

        contgarr(:) = self%coords(2::self%dim)
        call self%write_h5_dataset(file=file, datasetname="y", buff_real=contgarr)

        if (self%dim == 3 ) then
            contgarr(:) = self%coords(3::self%dim)
            call self%write_h5_dataset(file=file, datasetname="z", buff_real=contgarr)
        end if

        contgarr = self%comm_rank
        call self%write_h5_dataset(file=file, datasetname="mpi_rank", buff_real=contgarr)

        call h5fclose_f(file, herr)

        call self%write_xdmf()
    end subroutine


    subroutine write_xdmf(self)
    !*********************************************************************
    ! Write xdmf file for mesh visualization
    !*********************************************************************
        implicit none

        class(solver_t), intent(inout) :: self
        character(len=ll) :: xdmffile, xdmfcollec
        character(len=ll) :: worder ='">'
        integer :: i

        if (trim(self%topology_type) == "Wedge") worder = '" Order="0 5 3 1 4 2">'
        write(xdmffile, "('./OUTPUTED_MESH_PARTITIONS/mesh_', i0, '-', i0, '_', i0, '-', i0, '.xmf')") self%comm_rank, self%comm_size, self%ntnode, self%ntcell

        open(1, file=xdmffile, status='new')

        write(1, "(a)") '<?xml version="1.0" ?>'
        write(1, "(a)") '<!DOCTYPE Xdmf SYSTEM "Xdmf.dtd" []>'
        write(1, "(a)") '<Xdmf Version="2.0" xmlns:xi="http://www.w3.org/2001/XInclude">'

            write(1, "(t4, a)") '<Domain>'

                write(1, "(t8, a, i0, a)") '<Grid Collection="MESH" Name="mesh_part_', self%comm_rank, '">'
                    write(1, "(t12, a, a, a, i0, a)") '<Topology Type="', trim(self%topology_type), '" NumberOfElements="', self%ncell, trim(worder)
                        write(1, "(t16, a, i0, a)") '<DataItem ItemType="Function" Dimensions="', self%ncell*self%nvertex, '" Function="$0 - 1">'
                            write(1, "(t20, a, i0, a)") '<DataItem Format="HDF" DataType="Int" Dimensions="', self%ncell*self%nvertex, '">'
                                write(1, "(t24, a, a)") trim(self%outmeshfile), ':/element_to_node'
                            write(1, "(t20, a)") '</DataItem>'
                        write(1, "(t16, a)") '</DataItem>'
                    write(1, "(t12, a, i0, a)") '</Topology>'

                    if (self%dim == 2) write(1, "(t12, a)") '<Geometry Type="X_Y">'
                    if (self%dim == 3) write(1, "(t12, a)") '<Geometry Type="X_Y_Z">'
                        write(1, "(t16, a, i0, a)") '<DataItem Format="HDF" ItemType="Uniform" Precision="8" NumberType="Float" Dimensions="', self%nnode, '">'
                            write(1, "(t20, a, a)") trim(self%outmeshfile), ':/x'
                        write(1, "(t16, a)") '</DataItem>'
                        write(1, "(t16, a, i0, a)") '<DataItem Format="HDF" ItemType="Uniform" Precision="8" NumberType="Float" Dimensions="', self%nnode, '">'
                            write(1, "(t20, a, a)") trim(self%outmeshfile), ':/y'
                        write(1, "(t16, a)") '</DataItem>'
                        if (self%dim == 3) then
                        write(1, "(t16, a, i0, a)") '<DataItem Format="HDF" ItemType="Uniform" Precision="8" NumberType="Float" Dimensions="', self%nnode, '">'
                            write(1, "(t20, a, a)") trim(self%outmeshfile), ':/z'
                        write(1, "(t16, a)") '</DataItem>'
                        end if
                    write(1, "(t12, a, i0, a)") '</Geometry>'

                    write(1, "(t12, a)") '<Attribute Name="mpi_rank" Center="Node" AttributeType="Scalar">'
                        write(1, "(t16, a, i0, a)") '<DataItem Format="HDF" DataType="Int" Dimensions="', self%nnode, '">'
                            write(1, "(t20, a, a)") trim(self%outmeshfile), ':/mpi_rank'
                        write(1, "(t16, a)") '</DataItem>'
                    write(1, "(t12, a, i0, a)") '</Attribute>'

                write(1, "(t8, a)") '</Grid>'

            write(1, "(t4, a)") '</Domain>'

        write(1, "(a)") '</Xdmf>'
        close(1)


        ! Create collection
        if (self%comm_rank == 0) then
            write(xdmfcollec, "('./OUTPUTED_MESH_PARTITIONS/mesh_collec_', i0, 'd', a, '_', i0, 'P_', i0, 'N-', i0, 'C.xmf')") self%dim, self%topology_type(1:1), self%comm_size, self%ntnode, self%ntcell
            open(2, file=xdmfcollec, status='new')
            write(2, "(a)") '<?xml version="1.0" ?>'
            write(2, "(a)") '<!DOCTYPE Xdmf SYSTEM "Xdmf.dtd" []>'
            write(2, "(a)") '<Xdmf Version="2.0" xmlns:xi="http://www.w3.org/2001/XInclude">'
                write(2, "(t4, a)") '<Domain>'
                    write(2, "(t8, a)") '<Grid Name="mesh_partitions" GridType="Collection" CollectionType="Spatial">'
                        do i = 0, self%comm_size - 1
                        write(xdmffile, "('./mesh_', i0, '-', i0, '_', i0, '-', i0, '.xmf')") i, self%comm_size, self%ntnode, self%ntcell
                        write(2, "(t12, a, a, a)") '<xi:include href="', trim(xdmffile), '" xpointer="xpointer(//Xdmf/Domain/Grid)"/>'
                        end do
                    write(2, "(t8, a)") '</Grid>'
                write(2, "(t4, a)") '</Domain>'
            write(2, "(a)") '</Xdmf>'
        end if
    end subroutine


    subroutine write_h5_dataset(self, file, datasetname, buff, buff_real)
    !*********************************************************************
    ! Write hdf5 dataset
    !*********************************************************************
        implicit none

        class(solver_t), intent(inout) :: self
        integer(hid_t) :: file
        character(len=*) :: datasetname
        integer, dimension(:), optional :: buff
        double precision, dimension(:), optional :: buff_real

        integer(hid_t) :: dataset
        integer(hid_t) :: dataspace
        integer(hsize_t), dimension(1) :: hdims
        integer :: herr

        character(len=ll) :: message

        write(message, "('Writing dataset: ', a)") trim(datasetname)
        if (self%db_mesh_info) call self%log(trim(message), wrk=self%wrkh5, blk=.true.)

        if (present(buff)) then
            hdims(1) = size(buff)
        elseif (present(buff_real)) then
            hdims(1) = size(buff_real)
        end if

        call h5screate_simple_f(1, hdims, dataspace, herr)

        if (present(buff)) then
            call h5dcreate_f(file, trim(datasetname), H5T_NATIVE_INTEGER, dataspace, dataset, herr)
            call h5dwrite_f(dataset, H5T_NATIVE_INTEGER, buff, hdims, herr)

        elseif (present(buff_real)) then
            call h5dcreate_f(file, trim(datasetname), H5T_NATIVE_DOUBLE, dataspace, dataset, herr)
            call h5dwrite_f(dataset, H5T_NATIVE_DOUBLE, buff_real, hdims, herr)

        end if

        call h5dclose_f(dataset, herr)
        call h5sclose_f(dataspace, herr)
    end subroutine


    subroutine read_h5_dataset(self, filename, groupname, datasetname, array_dim, array_int, array_real)
    !*********************************************************************
    ! Read hdf5 dataset
    !*********************************************************************
        implicit none

        class(solver_t), intent(inout) :: self

        character(len=*), intent(in) :: filename
        character(len=*), intent(in) :: groupname
        character(len=*), intent(in) :: datasetname
        integer, intent(out) :: array_dim
        integer, dimension(:), allocatable, optional, intent(out) :: array_int
        double precision, dimension(:), allocatable, optional, intent(out) :: array_real

        integer :: herr
        integer(hid_t) :: file
        integer(hid_t) :: grp
        integer(hid_t) :: dset
        integer(hid_t) :: dtype
        integer(hid_t) :: dspace
        integer :: ndims
        integer(hsize_t), dimension(:), allocatable :: dims, maxdims

        character(len=ll) :: message

        write(message, "('Reading dataset: ', a, '/', a, '/', a)") trim(filename), trim(groupname), trim(datasetname)
        if (self%db_mesh_info) call self%log(trim(message), wrk=self%wrkh5, blk=.true.)

        call h5fopen_f(trim(filename), H5F_ACC_RDONLY_F, file, herr)
        call h5gopen_f(file, trim(groupname), grp, herr)
        call h5dopen_f(grp, trim(datasetname), dset, herr)

        call h5dget_type_f(dset, dtype, herr)
        call h5dget_space_f(dset, dspace, herr)
        call h5sget_simple_extent_ndims_f(dspace, ndims, herr)

        allocate(dims(ndims))
        allocate(maxdims(ndims))
        call h5sget_simple_extent_dims_f(dspace, dims, maxdims, herr)
        array_dim = dims(1)

        if (present(array_int)) then
            allocate(array_int(array_dim))
            call h5dread_f(dset, dtype, array_int, dims, herr)

        else if (present(array_real)) then
            allocate(array_real(array_dim))
            call h5dread_f(dset, dtype, array_real, dims, herr)

        end if

        deallocate(dims)
        deallocate(maxdims)
        call h5dclose_f(dset, herr)
        call h5gclose_f(grp, herr)
        call h5fclose_f(file, herr)
    end subroutine


    subroutine log(self, message, wrk, blk)
    !*********************************************************************
    ! Logging subroutine
    !*********************************************************************
        implicit none

        ! in/out
        class(solver_t), intent(inout) :: self
        character(len=*), intent(in) :: message
        integer, optional, intent(in) :: wrk
        logical, optional, intent(in) :: blk

        integer :: wrank
        logical :: blck
        character(len=ll) :: line = repeat("*", 64)
        integer :: i

        wrank = 0
        if (present(wrk)) wrank = wrk

        blck = .false.
        if (present(blk)) blck = blk

        call mpi_barrier(self%comm, self%ierr); call mpi_barrier(self%comm, self%ierr); call mpi_barrier(self%comm, self%ierr)
        if (blck .and. self%comm_rank == max(wrank, 0)) write(*, "(a)") trim(line)
        call mpi_barrier(self%comm, self%ierr); call mpi_barrier(self%comm, self%ierr); call mpi_barrier(self%comm, self%ierr)

        if (wrank == -1) then
            do i = 0, self%comm_size - 1
                call mpi_barrier(self%comm, self%ierr); call mpi_barrier(self%comm, self%ierr); call mpi_barrier(self%comm, self%ierr)
                if (i == self%comm_rank) write(*, "('(', i0, '/', i0, ') : ', a)") self%comm_rank, self%comm_size, trim(message)
                call mpi_barrier(self%comm, self%ierr); call mpi_barrier(self%comm, self%ierr); call mpi_barrier(self%comm, self%ierr)
            end do
        else if (self%comm_rank == wrank) then
            write(*, "(a)") trim(message)
        end if

        call mpi_barrier(self%comm, self%ierr); call mpi_barrier(self%comm, self%ierr); call mpi_barrier(self%comm, self%ierr)
        if (blck .and. self%comm_rank == max(wrank, 0)) write(*, "(a)") trim(line)//new_line("a")
        call mpi_barrier(self%comm, self%ierr); call mpi_barrier(self%comm, self%ierr); call mpi_barrier(self%comm, self%ierr)
    end subroutine


    subroutine log_array(self, name, array, array_real, wrk, blk)
    !*********************************************************************
    ! Array logging
    !*********************************************************************
        implicit none

        class(solver_t), intent(inout) :: self
        character(len=*), intent(in) :: name
        integer, dimension(:), optional, intent(in) :: array
        double precision, dimension(:), optional, intent(in) :: array_real
        integer, optional, intent(in) :: wrk
        logical, optional, intent(in) :: blk

        integer :: sz = 0
        integer :: i
        character(len=ll*2**4) :: message
        integer, parameter :: ml = 1000

        if (present(array)) then
            sz = size(array)
            if (sz <= ml) then
                write(message, "(a, ' [', i0, '] = ', i0)") name, sz, array(1)
                do i = 2, sz
                    write(message, "(a, ', ', i0)") trim(message), array(i)
                end do
            end if

        else if (present(array_real)) then
            sz = size(array_real)
            if (sz <= ml) then
                write(message, "(a, ' [', i0, '] = ', f12.6)") name, sz, array_real(1)
                do i = 2, sz
                    write(message, "(a, ', ', f12.6)") trim(message), array_real(i)
                end do
            end if
        end if

        if (sz > 0 .and. sz <= ml) call self%log(message, wrk, blk)
    end subroutine


    subroutine progress_bar(self, i, N)
    !*********************************************************************
    ! Progress bar (for hash table creation)
    !*********************************************************************
        implicit none

        class(solver_t), intent(inout) :: self
        integer, intent(in) :: i
        integer, intent(in) :: N

        character(len=ll) :: message

        if ( N > 100 ) then
            if (mod(i, N/100) == 0 .and. N >= 1e5) then
                write(message, "(t4, '[', i0, ' %] ', A)")  (i*100)/N, repeat("#", (i*100)/N)
                call self%log(message)
            end if
        end if
    end subroutine
end module
