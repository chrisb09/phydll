#!/usr/bin/bash

CWD=$(dirname $(realpath $0))

np_phy=$(($(nproc) / 4 * 3))
np_dl=$(($(nproc) - $np_phy))

echo -e "\tRunning..."
cd $CWD > /dev/null

mpirun --use-hwthread-cpus -n $np_phy ./c_phy.exe : -n $np_dl ./c_dl.exe > /dev/null
if [ $? == 0 ]; then echo -e "\t...Succeeded\n"; else echo -e "\t...Failed"; exit 1; fi

cd - > /dev/null
