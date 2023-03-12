program main
    use mpi

    integer, parameter :: iinit = -99999
    double precision, parameter :: rinit = -99999.99999

    integer :: comm = MPI_COMM_WORLD
    integer :: comm_size
    integer :: comm_rank
    integer :: ierr

    integer :: ndim = 2 ! @hc

    character(len=256) :: filename
    character(len=256) :: groupname
    character(len=256) :: datasetname

    integer :: global_connec_dim
    integer :: ncell
    integer, dimension(:), allocatable :: global_connec

    integer, dimension(:), allocatable :: recvcounts
    integer, dimension(:), allocatable :: recvdispls

    integer :: el_2_part_dim
    integer, dimension(:), allocatable :: el_2_part
    integer, dimension(:), allocatable :: el_2_part_all

    integer :: nnode
    double precision, dimension(:), allocatable :: x
    double precision, dimension(:), allocatable :: y
    double precision, dimension(:), allocatable :: coords

    double precision, dimension(:), allocatable :: xglob
    double precision, dimension(:), allocatable :: yglob


    integer :: nvertex = 4! @hc
    integer :: ntcell
    integer :: ntnode

    integer, dimension(:), allocatable :: temp

    integer, dimension(:), allocatable :: connec
    integer, dimension(:), allocatable :: local_node_to_global
    integer, dimension(:), allocatable :: local_cell_to_global

    integer :: i, j
    logical :: to_cycle

    interface
        subroutine read_h5_dataset(filename, groupname, datasetname, array_dim, array_int, array_real)
            implicit none
            character(len=*), intent(in) :: filename
            character(len=*), intent(in) :: groupname
            character(len=*), intent(in) :: datasetname
            integer, intent(out) :: array_dim
            integer, dimension(:), allocatable, optional, intent(out) :: array_int
            double precision, dimension(:), allocatable, optional, intent(out) :: array_real
        end subroutine
    end interface

    call mpi_init(ierr)

    call mpi_comm_size(comm, comm_size, ierr)
    call mpi_comm_rank(comm, comm_rank, ierr)


    write(filename, "('el2part_', i0, '.h5')") comm_size
    write(groupname, "('part', i7.7)") comm_rank + 1

    datasetname = "qua->node"
    call read_h5_dataset(trim(filename), trim(groupname), trim(datasetname), global_connec_dim, array_int=global_connec)
    datasetname = "el_2_part"

    ncell = global_connec_dim / nvertex

    call read_h5_dataset(trim(filename), trim(groupname), trim(datasetname), el_2_part_dim, array_int=el_2_part)

    call read_h5_dataset("meshfile.h5", "Coordinates", "x", nnode, array_real=xglob)
    call read_h5_dataset("meshfile.h5", "Coordinates", "y", nnode, array_real=yglob)


    if (comm_rank == 1) write(*,*) "global_connec = ", global_connec
    ! if (comm_rank == 1) write(*,*) "maxval(global_connec) = ", maxval(global_connec)
    ! if (comm_rank == 0) write(*,*) "x = \n", x

    call mpi_allreduce(maxval(global_connec), ntnode, 1, MPI_INTEGER, MPI_MAX, comm, ierr)
    call mpi_allreduce(ncell, ntcell, 1, MPI_INTEGER, MPI_SUM, comm, ierr)


    allocate(recvcounts(comm_size)); recvcounts = iinit
    allocate(recvdispls(comm_size)); recvdispls = iinit

    call mpi_allgather(el_2_part_dim, 1, MPI_INTEGER, recvcounts, 1, MPI_INTEGER, comm, ierr)
    recvdispls(1) = 0
    do i = 2, comm_size
        recvdispls(i) = recvdispls(i-1) + recvcounts(i-1)
    end do
    if (comm_rank == 1) write(*,*) "recvcounts = ", recvcounts
    if (comm_rank == 1) write(*,*) "recvdispls = ", recvdispls

    allocate(el_2_part_all(ntcell)); el_2_part_all = iinit
    call mpi_allgatherv(el_2_part, el_2_part_dim, MPI_INTEGER, el_2_part_all, recvcounts, recvdispls, MPI_INTEGER, comm, ierr)
    el_2_part_all = el_2_part_all - 1

    allocate(local_cell_to_global(ncell)); local_cell_to_global = iinit
    j = 1
    do i = 1, ntcell
        if (el_2_part_all(i) == comm_rank) then
            local_cell_to_global(j) = i
            j = j + 1
        end if
    end do

    if (comm_rank == 1) write(*,*) "el_2_part_all = ", el_2_part_all
    write(*,*) "el_2_part_", comm_rank, "   =  ",  el_2_part
    write(*,*) "local_cell_to_global = ", local_cell_to_global


    ! Create local connectivity and hash table for local-to-global nodes
    allocate(connec(ncell*nvertex)); connec = iinit
    allocate(temp(ntnode)); temp = iinit
    connec = -1
    temp = -1
    connec(1) = 1
    temp(1) = global_connec(1)
    do i = 2, ncell*nvertex
        to_cycle = .false.
        do j = 1, i-1
            if (global_connec(i) == global_connec(j)) then
                connec(i) = connec(j)
                to_cycle = .true.
                exit
            end if
        end do
        if (to_cycle) cycle
        connec(i) = i
        temp(i) = global_connec(i)
    end do


    ! Reduce the size of the hash table
    nnode = count(temp >= 1)
    allocate(local_node_to_global(nnode)); local_node_to_global = iinit
    j = 1
    do i = 1, ntnode
        if (temp(i) >= 1) then
            local_node_to_global(j) = temp(i)
            j = j + 1
        end if
    end do

    allocate(x(nnode)); x = rinit
    allocate(y(nnode)); y = rinit
    x = xglob(local_node_to_global)
    y = yglob(local_node_to_global)

    allocate(coords(ndim*nnode)); coords = rinit
    coords(1::ndim) = xglob(local_node_to_global)
    coords(2::ndim) = yglob(local_node_to_global)





    ! if (comm_rank == 1) write(*,*) "connec = ", connec
    ! if (comm_rank == 1) write(*,*) "temp = ", temp
    ! if (comm_rank == 1) write(*,*) "local_node_to_global = ", local_node_to_global
    ! if (comm_rank == 1) write(*,*) "x = ", x
    ! if (comm_rank == 1) write(*,*) "y = ", y


    do i = 0, comm_size - 1
        call mpi_barrier(comm, ierr)
        if (comm_rank == i) then
            write(*, "('***** rank = ', i0 , ' ****************************************')") i
            write(*, "('ndim = ', i0)") ndim
            write(*, "('nvertex = ', i0)") nvertex
            write(*, "('ncell = ', i0)") ncell
            write(*, "('nnode = ', i0)") nnode
            write(*, "('ntcell = ', i0)") ntcell
            write(*, "('ntnode = ', i0)") ntnode
            write(*,"('global_connec_dim = ', i0)") global_connec_dim
            write(*, "(A)") "*******************************************************"
            write(*,*) " "
        end if
        call mpi_barrier(comm, ierr)
    end do





    ! call h5fopen_f("./meshfile.h5", H5F_ACC_RDONLY_F, file, ierr)
    ! call h5gopen_f(file, "Coordinates", grp, ierr)
    ! call h5dopen_f(grp, "x", dset, ierr)
    ! call h5dget_type_f(dset, dtype, ierror)
    ! call h5dget_space_f(dset, dspace, ierr)
    ! call h5sget_simple_extent_ndims_f(dspace, ndims, ierr)


    deallocate(local_node_to_global)
    deallocate(connec)
    deallocate(temp)
    deallocate(recvcounts)
    deallocate(recvdispls)
    deallocate(el_2_part_all)
    deallocate(local_cell_to_global)
    deallocate(el_2_part)
    deallocate(global_connec)
    deallocate(xglob)
    deallocate(yglob)
    deallocate(x)
    deallocate(y)
    deallocate(coords)

    call mpi_finalize(ierror)

end program

subroutine read_h5_dataset(filename, groupname, datasetname, array_dim, array_int, array_real)
    use hdf5

    implicit none

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

    character(len=512) :: message

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

    ! write(*, "('filename = ', A)") filename
    ! write(*, "('grpnam = ', A)") groupname

    deallocate(dims)
    deallocate(maxdims)
    call h5dclose_f(dset, herr)
    call h5gclose_f(grp, herr)
    call h5fclose_f(file, herr)
end subroutine
