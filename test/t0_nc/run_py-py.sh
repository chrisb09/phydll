#!/usr/bin/bash

CWD=$(dirname $(realpath $0))

np_phy=$(($(nproc) / 4 * 3))
np_dl=$(($(nproc) - $np_phy))

echo -e "\tRunning..."
cd $CWD > /dev/null

mpirun --use-hwthread-cpus -n $np_phy python ./phy_main.py : -n $np_dl python ./dl_main.py > /dev/null
if [ $? == 0 ]; then echo -e "\t...Succeeded\n"; else echo -e "\t...Failed"; exit 1; fi

cd - > /dev/null
