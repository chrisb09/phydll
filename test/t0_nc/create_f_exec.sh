#!/usr/bin/bash

FC=$1
FFLAGS=$2
INC=$3
LIB=$4
CWD=$(dirname $(realpath $0))

cd $CWD > /dev/null

echo -e "\tCompiling/linking Fortran test physical solver..."
$FC $FFLAGS ./phy_main.f90 -o ./f_phy.exe -I$INC -L$LIB -lphydll -lphydll_f -Wl,-rpath=$LIB
if [ $? == 0 ]; then echo -e "\t...Succeeded\n"; else echo -e "\t...Failed"; exit 1; fi

cd - > /dev/null
