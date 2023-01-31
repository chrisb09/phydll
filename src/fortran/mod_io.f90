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

    implicit none
    type io_t
        ! Attributes
        type(env_t), pointer :: env                     ! Pointer to be associated with phydll%env

        ! Procedures
        contains
            procedure, private :: logg
            procedure, private :: loggall
            procedure :: log_msg
            procedure :: log_warn
            procedure :: log_err
            procedure :: log_db
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
            write(*, "(A)") trim(message)
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
        write(*, "(A)") trim(message)

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
        integer, intent(in) :: lv
        logical, optional, intent(in) :: allmpi

        ! local
        character(len=lll) :: msg
        logical :: all
        integer, parameter :: hd = 6
        character(len=sl) :: fmt = "(A)"

        ! Check if allmpi
        if (present(allmpi)) then
            all = allmpi
        else
            all = .false.
        end if

        ! Set message format (with header)
        if (lv > 0) write(fmt, "('(', I0, 'X, A)')") lv*hd
        write(msg, fmt) message

        ! Write message
        if (all) then
            call self%loggall(msg)
        else
            call self%logg(msg)
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
        call self%logg(trim(warn) // " " // message)
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
        call self%logg(trim(err) // " " // message)
        call exit(0)
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
        if (present(allmpi)) then
            lallmpi = allmpi
        else
            lallmpi = .false.
        end if

        ! Write
        if (lallmpi) then
            write(db_message, "('/!\ /!\ /!\', 4X, I10, '/', I0, 4X, A)") self%env%comm_rank, self%env%comm_size, message
            call self%loggall(db_message)
        else
            write(db_message, "('/!\ /!\ /!\', X, A)") message
            call self%logg(db_message)
        end if
    end subroutine
end module
