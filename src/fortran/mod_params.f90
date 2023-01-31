!*************************************************************************
! FILE      :   mod_params.f90
! DATE      :   06-12-2022
! AUTHORS   :   A. Serhani, C. Lapeyre, G. Staffelbach
! EMAIL     :   phydll@cerfacs.fr
! DETAILS   :   Useful parameters and constants
!*************************************************************************
module mod_params
    implicit none

    integer, parameter :: sl = 16                           !< Short string length
    integer, parameter :: ml = 64                           !< Medium string length
    integer, parameter :: ll = 256                          !< Long string length
    integer, parameter :: lll = 1024                        !< Very long string length
    integer, parameter :: iinit = -99999                    !< Default values for integers
    double precision, parameter :: dbinit = -9999.9999      !< Default values for double percisions
    character, parameter :: cinit = "Z"                     !< Default values for strings
end module