#!/usr/bin/bash

source ~/envs/shenv-phydll.sh
cd $(dirname $(realpath $0))/.. > /dev/null

CC=mpicc
FC=mpifort
BUILD=./phydll_installation
logfile=$(realpath $BUILD/phydll_pipeline_$(date +%s).log)
mkdir -p $BUILD

stage() {
    echo -n "$1: "
    shift 1
    $* &>> $logfile
    if [ $? == 0 ]; then echo -e "passed"; else echo "failed: (log file: $logfile)" ; exit 1; fi
}

stage "clean" "make clean"
stage "info" "make CC=$CC FC=$FC ENABLE_FORTRAN=ON ENABLE_PYTHON=ON BUILD=$BUILD info"
stage "c compile" "make CC=$CC BUILD=$BUILD compile"
stage "c-c t0nc run" "make CC=$CC BUILD=$BUILD crun"
stage "fortran compile" "make CC=$CC FC=$FC ENABLE_FORTRAN=ON BUILD=$BUILD fcompile"
stage "fortran-c t0nc run" "make CC=$CC FC=$FC ENABLE_FORTRAN=ON BUILD=$BUILD frun"
stage "python setup" "make CC=$CC ENABLE_PYTHON=ON BUILD=$BUILD pysetup"
stage "py-py t0nc run" "make CC=$CC ENABLE_PYTHON=ON BUILD=$BUILD pyrun"

echo -e "\nfull log file: $logfile"
cd - > /dev/null
