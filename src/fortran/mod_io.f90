!*************************************************************************
! FILE      :   mod_env.f90
! DATE      :   06-12-2022
! AUTHORS   :   A. Serhani, C. Lapeyre, G. Staffelbach
! EMAIL     :   phydll@cerfacs.fr
! DETAILS   :   PhyDLL's input/output module
!*************************************************************************
module mod_io
    use mod_params
    use mpi,        only: mpi_barrier
    use mod_env,    only: env_t
    use mod_cpl,    only: cpl_t
    use mod_mesh,   only: mesh_t

    implicit none
    type io_t
        ! Attributes
        type(env_t), pointer :: env                     ! Associated (pointer) to phydll%env
        type(cpl_t), pointer :: cpl                     ! Associated (pointer) to phydll%cpl
        type(mesh_t), pointer :: mesh                   ! Associated (pointer) to phydll%mesh

        ! Procedures
        contains
            procedure, private :: logg
            procedure, private :: loggall
            procedure :: log_msg
            procedure :: log_warn
            procedure :: log_err
            procedure :: log_db
#ifdef HDF5
            procedure :: save_exch_fields
            procedure :: write_xdmf_file
            procedure, nopass :: write_h5_dataset
#endif
    end type

    contains

    subroutine logg(self, message)
    !*********************************************************************
    ! Master process writes on log file
    !
    ! Args:
    !   [in]    self        IO object
    !   [in]    message     Message to write
    !*********************************************************************
        implicit none

        ! in/out
        class(io_t), intent(in) :: self
        character(len=*), intent(in) :: message

        ! local
        integer :: ierror

        call mpi_barrier(self%env%comm, ierror)

        ! Write message
        if (self%env%comm_rank == 0) then
            write(*, "(a)") trim(message)
        end if

        call mpi_barrier(self%env%comm, ierror)
    end subroutine


    subroutine loggall(self, message)
    !*********************************************************************
    ! All processes write on log file
    !
    ! Args:
    !   [in]    self        IO object
    !   [in]    message     Message to write
    !*********************************************************************
        implicit none

        ! in/out
        class(io_t), intent(in) :: self
        character(len=*), intent(in) :: message

        ! local
        integer :: ierror

        call mpi_barrier(self%env%comm, ierror)

        ! Write message
        write(*, "(a)") trim(message)

        call mpi_barrier(self%env%comm, ierror)
        call logg(self, " ")
    end subroutine


    subroutine log_msg(self, message, lv, allmpi)
    !*********************************************************************
    ! Generic message log with debug level and mpi option
    !
    ! Args:
    !   [in]    self        IO object
    !   [in]    message     Message to write
    !   [in]    lv          Debug level
    !   [in]    allmpi      Message written by Master or All processes
    !*********************************************************************
        implicit none

        ! in/out
        class(io_t), intent(in) :: self
        character(len=*), intent(in) :: message
        integer, optional, intent(in) :: lv
        logical, optional, intent(in) :: allmpi

        ! local
        character(len=lll) :: msg
        integer :: level
        logical :: all
        integer, parameter :: hd = 6
        character(len=sl) :: fmt

        ! Header lever
        level = 0
        if (present(lv)) level = lv

        ! Check if allmpi
        all = .false.
        if (present(allmpi)) all = allmpi

        ! Set message format (with header)
        fmt = "(a)"
        if (level > 0) write(fmt, "('(', i0, 'x, a)')") level * hd
        write(msg, trim(fmt)) trim(message)

        ! Write message
        if (all) then
            call self%loggall(trim(msg))
        else
            call self%logg(trim(msg))
        end if
    end subroutine


    subroutine log_warn(self, message)
    !*********************************************************************
    ! Log warning
    !
    ! Args:
    !   [in]    self        IO object
    !   [in]    message     Message to write
    !*********************************************************************
        implicit none

        ! in/out
        class(io_t), intent(in) :: self
        character(len=*), intent(in) :: message

        ! local
        character(len=ml) :: warn

        write(warn, "('PhyDLL !! WARNING !! >')")
        call self%logg(trim(warn) // " " // trim(message))
    end subroutine


    subroutine log_err(self, message)
    !*********************************************************************
    ! Log warning
    !
    ! Args:
    !   [in]    self        IO object
    !   [in]    message     Message to write
    !*********************************************************************
        implicit none

        ! in/out
        class(io_t), intent(in) :: self
        character(len=*), intent(in) :: message

        ! local
        character(len=ml) :: err

        write(err, "('PhyDLL !! ERROR !! >')")
        call self%logg(trim(err) // " " // trim(message))
        call exit(1)
    end subroutine


    subroutine log_db(self, message, allmpi)
    !*********************************************************************
    ! Log for debugging
    !
    ! Args:
    !   [in]    self        IO object
    !   [in]    message     Message to write
    !   [in]    allmpi      Message written by Master or All processes
    !*********************************************************************
        implicit none

        ! in/out
        class(io_t), intent(in) :: self
        character(len=*), intent(in) :: message
        logical, optional, intent(in) :: allmpi

        ! local
        character(len=lll) :: db_message
        logical :: lallmpi

        ! Check if allmpi
        lallmpi = .false.
        if (present(allmpi)) lallmpi = allmpi

        ! Write
        if (lallmpi) then
            write(db_message, "('/!\ /!\ /!\', 4x, i0, '/', i0, 4x, a)") self%env%comm_rank, self%env%comm_size - 1, trim(message)
            call self%loggall(trim(db_message))
        else
            write(db_message, "('/!\ /!\ /!\', x, a)") trim(message)
            call self%logg(trim(db_message))
        end if
    end subroutine

#ifdef HDF5
    subroutine save_exch_fields(self)
    !*********************************************************************
    ! Write exchanged fields in ./PhyDLL_FIELDS (by default)
    !
    ! Args:
    !   [in]    self    IO object
    !*********************************************************************
        use hdf5, only: h5fcreate_f, h5fclose_f, hid_t, H5F_ACC_TRUNC_F

        implicit none

        ! in/out
        class(io_t), intent(inout) :: self

        ! local
        character(len=ll) :: h5file
        character(len=ll) :: datasetname
        integer(hid_t) :: file
        integer :: herr
        integer, dimension(self%mesh%nnode) :: arr
        integer :: i

        write(h5file, "(a, '/FILES/fields_phy_', i0, '_', i0, '-', i0, '.h5')") trim(self%cpl%out_dir), self%cpl%ite, self%env%comm_rank, self%env%comm_size - 1
        call h5fcreate_f(trim(h5file), H5F_ACC_TRUNC_F, file, herr)

        call self%write_h5_dataset(file=file, datasetname="connec", buff_int=self%mesh%element_to_node)
        call self%write_h5_dataset(file=file, datasetname="x", buff_real=self%mesh%node_coords(1::self%mesh%dim))
        call self%write_h5_dataset(file=file, datasetname="y", buff_real=self%mesh%node_coords(2::self%mesh%dim))
        if (self%mesh%dim == 3) call self%write_h5_dataset(file=file, datasetname="z", buff_real=self%mesh%node_coords(3::self%mesh%dim))

        arr = self%env%comm_rank;   call self%write_h5_dataset(file=file, datasetname="mpi_rank", buff_int=arr)
        arr = self%env%pydest;      call self%write_h5_dataset(file=file, datasetname="pydest_rank", buff_int=arr)

        do i = 1, self%cpl%phy_fields%count
            write(datasetname, "('phy_fields_', i0, '_', a)") i, trim(self%cpl%phy_fields%label(i))
            call self%write_h5_dataset(file=file, datasetname=trim(datasetname), buff_real=self%cpl%phy_fields%array(i::self%cpl%phy_fields%count))
        end do

        do i = 1, self%cpl%dl_fields%count
            write(datasetname, "('dl_fields_', i0, '_', a)") i, trim(self%cpl%dl_fields%label(i))
            call self%write_h5_dataset(file=file, datasetname=trim(datasetname), buff_real=self%cpl%dl_fields%array(i::self%cpl%dl_fields%count))
        end do

        call h5fclose_f(file, herr)

        call self%write_xdmf_file(trim(h5file))
    end subroutine


    subroutine write_h5_dataset(file, datasetname, buff_int, buff_real)
    !*********************************************************************
    ! Write exchanged fields to ./PhyDLL_FIELDS (by default)
    !
    ! Args:
    !   [in]    self        IO object
    !   [in]    file        HDF5 file_id (integer(hid_t))
    !   [in]    datasetname Dataset name
    !   [in]    buff_int    Array of integers
    !   [in]    buff_real   Array of reals
    !*********************************************************************
        use hdf5, only: h5screate_simple_f, h5dcreate_f, h5dwrite_f, h5dclose_f, h5sclose_f, &
                        hid_t, hsize_t, H5T_NATIVE_INTEGER, H5T_NATIVE_DOUBLE

        implicit none

        ! in/out
        integer(hid_t), intent(in) :: file
        character(len=*), intent(in) :: datasetname
        integer, dimension(:), optional, intent(in) :: buff_int
        double precision, dimension(:), optional, intent(in) :: buff_real

        ! local
        integer(hid_t) :: dataset
        integer(hid_t) :: dataspace
        integer(hsize_t), dimension(1) :: hdims
        integer :: herr

        if (present(buff_int)) then
            hdims(1) = size(buff_int)
        elseif (present(buff_real)) then
            hdims(1) = size(buff_real)
        end if

        call h5screate_simple_f(1, hdims, dataspace, herr)

        if (present(buff_int)) then
            call h5dcreate_f(file, trim(datasetname), H5T_NATIVE_INTEGER, dataspace, dataset, herr)
            call h5dwrite_f(dataset, H5T_NATIVE_INTEGER, buff_int, hdims, herr)

        elseif (present(buff_real)) then
            call h5dcreate_f(file, trim(datasetname), H5T_NATIVE_DOUBLE, dataspace, dataset, herr)
            call h5dwrite_f(dataset, H5T_NATIVE_DOUBLE, buff_real, hdims, herr)

        end if

        call h5dclose_f(dataset, herr)
        call h5sclose_f(dataspace, herr)
    end subroutine


    subroutine write_xdmf_file(self, h5file)
    !*********************************************************************
    ! Write xdmf file for exch fields visualization
    !
    ! Args:
    !   [in]    self        IO object
    !   [in]    h5file      hdf5 file path
    !*********************************************************************
        implicit None

        class(io_t), intent(inout) :: self
        character(len=*), intent(in) :: h5file

        ! local
        character(len=ll) :: xdmffile
        character(len=ll) :: worder ='">'
        character(len=ll) :: h5file_rel
        character(len=ml) :: tempchar
        integer :: i

        h5file_rel = '.'//trim(h5file(len(trim(self%cpl%out_dir))+1:))

        if (trim(self%mesh%topology_type) == "Wedge") worder = '" Order="0 5 3 1 4 2">'
        write(xdmffile, "(a, '/FILES/fields_phy_', i0, '_', i0, '-', i0, '.xmf')") trim(self%cpl%out_dir), self%cpl%ite, self%env%comm_rank, self%env%comm_size - 1

        open(1, file=trim(xdmffile), action='write')

        write(1, "(a)") '<?xml version="1.0" ?>'
        write(1, "(a)") '<!DOCTYPE Xdmf SYSTEM "Xdmf.dtd" []>'
        write(1, "(a)") '<Xdmf Version="2.0" xmlns:xi="http://www.w3.org/2001/XInclude">'

            write(1, "(t4, a)") '<Domain>'

                write(1, "(t8, a)") '<Grid Collection="PhyDLL" Name="exch_fields_dl">'

                    write(1, "(t12, a, a, a, i0, a)") '<Topology Type="', trim(self%mesh%topology_type), '" NumberOfElements="', self%mesh%ncell, trim(worder)
                        write(1, "(t16, a, i0, a)") '<DataItem ItemType="Function" Dimensions="', self%mesh%ncell*self%mesh%nvertex, '" Function="$0 - 1">'
                            write(1, "(t20, a, i0, a)") '<DataItem Format="HDF" DataType="Int" Dimensions="', self%mesh%ncell*self%mesh%nvertex, '">'
                                write(1, "(t24, a, a)") trim(h5file_rel), ':/connec'
                            write(1, "(t20, a)") '</DataItem>'
                        write(1, "(t16, a)") '</DataItem>'
                    write(1, "(t12, a, i0, a)") '</Topology>'

                    if (self%mesh%dim == 2) write(1, "(t12, a)") '<Geometry Type="X_Y">'
                    if (self%mesh%dim == 3) write(1, "(t12, a)") '<Geometry Type="X_Y_Z">'
                        write(1, "(t16, a, i0, a)") '<DataItem Format="HDF" ItemType="Uniform" Precision="8" NumberType="Float" Dimensions="', self%mesh%nnode, '">'
                            write(1, "(t20, a, a)") trim(h5file_rel), ':/x'
                        write(1, "(t16, a)") '</DataItem>'
                        write(1, "(t16, a, i0, a)") '<DataItem Format="HDF" ItemType="Uniform" Precision="8" NumberType="Float" Dimensions="', self%mesh%nnode, '">'
                            write(1, "(t20, a, a)") trim(h5file_rel), ':/y'
                        write(1, "(t16, a)") '</DataItem>'
                        if (self%mesh%dim == 3) then
                        write(1, "(t16, a, i0, a)") '<DataItem Format="HDF" ItemType="Uniform" Precision="8" NumberType="Float" Dimensions="', self%mesh%nnode, '">'
                            write(1, "(t20, a, a)") trim(h5file_rel), ':/z'
                        write(1, "(t16, a)") '</DataItem>'
                        end if
                    write(1, "(t12, a, i0, a)") '</Geometry>'

                    write(1, "(t12, a)") '<Attribute Name="mpi_rank" Center="Node" AttributeType="Scalar">'
                        write(1, "(t16, a, i0, a)") '<DataItem Format="HDF" DataType="Int" Dimensions="', self%mesh%nnode, '">'
                            write(1, "(t20, a, a)") trim(h5file_rel), ':/mpi_rank'
                        write(1, "(t16, a)") '</DataItem>'
                    write(1, "(t12, a, i0, a)") '</Attribute>'

                    write(1, "(t12, a)") '<Attribute Name="pydest_rank" Center="Node" AttributeType="Scalar">'
                        write(1, "(t16, a, i0, a)") '<DataItem Format="HDF" DataType="Int" Dimensions="', self%mesh%nnode, '">'
                            write(1, "(t20, a, a)") trim(h5file_rel), ':/pydest_rank'
                        write(1, "(t16, a)") '</DataItem>'
                    write(1, "(t12, a, i0, a)") '</Attribute>'

                    do i = 1, self%cpl%phy_fields%count
                    write(tempchar, "('phy_fields_', i0, '_', a)") i, trim(self%cpl%phy_fields%label(i))
                    write(1, "(t12, a, a, a)") '<Attribute Name="', trim(tempchar) ,'" Center="Node" AttributeType="Scalar">'
                        write(1, "(t16, a, i0, a)") '<DataItem Format="HDF" ItemType="Uniform" Precision="8" NumberType="Float" Dimensions="', self%mesh%nnode, '">'
                            write(1, "(t20, a, a, i0, a, a)") trim(h5file_rel), ':/phy_fields_', i, '_', trim(self%cpl%phy_fields%label(i))
                        write(1, "(t16, a)") "</DataItem>"
                    write(1, "(t12, a)") "</Attribute>"
                    end do

                    do i = 1, self%cpl%dl_fields%count
                    write(tempchar, "('dl_fields_', i0, '_', a)") i, trim(self%cpl%dl_fields%label(i))
                    write(1, "(t12, a, a, a)") '<Attribute Name="', trim(tempchar) ,'" Center="Node" AttributeType="Scalar">'
                        write(1, "(t16, a, i0, a)") '<DataItem Format="HDF" ItemType="Uniform" Precision="8" NumberType="Float" Dimensions="', self%mesh%nnode, '">'
                            write(1, "(t20, a, a, i0, a, a)") trim(h5file_rel), ':/dl_fields_', i, '_', trim(self%cpl%dl_fields%label(i))
                        write(1, "(t16, a)") "</DataItem>"
                    write(1, "(t12, a)") "</Attribute>"
                    end do

                write(1, "(t8, a)") '</Grid>'

            write(1, "(t4, a)") '</Domain>'

        write(1, "(a)") '</Xdmf>'
        close(1)
    end subroutine
#endif

end module
