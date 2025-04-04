#!/usr/bin/bash

CC=$1
CFLAGS=$2
INC=$3
LIB=$4
NOPHY=$5
CWD=$(dirname $(realpath $0))

cd $CWD > /dev/null

if [[ -z $NOPHY ]]; then
    echo -e "\tCompiling/linking C test physical solver..."
    $CC $CFLAGS ./phy_main.c -o ./c_phy.exe -I$INC -L$LIB -lphydll -Wl,-rpath=$LIB
    if [ $? == 0 ]; then echo -e "\t...Succeeded\n"; else echo -e "\t...Failed"; exit 1; fi
fi

echo -e "\tCompiling/linking C test DL engine..."
$CC $CFLAGS ./dl_main.c -o ./c_dl.exe -I$INC -L$LIB -lphydll -Wl,-rpath=$LIB
if [ $? == 0 ]; then echo -e "\t...Succeeded\n"; else echo -e "\t...Failed"; exit 1; fi

cd - > /dev/null
