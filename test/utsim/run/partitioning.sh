#!/bin/bash -x

# MODULES
module load avbp

# PARSING OPTIONS
MESHFILE="meshfile.h5"
NPARTs=4
METHOD="kway"
while getopts :m:n:a: opt; do
  case $opt in
    (m) MESHFILE=$OPTARG;;
    (n) NPARTS=$OPTARG;;
    (a) METHOD=$OPTARG;;
  esac
done

cp $MESHFILE ./meshfile.h5
rm partition.choices
rm el2part*

# PARTITION CHOICES
echo -e "&PARAMS
 MESHFILE=meshfile.h5,            ! Meshfile
 METHOD=$METHOD,                 ! Method: kway or recursive
 NPARTS=$NPARTS,                ! number of partitions
 CONTIGUOUS='yes',              ! contiguous partitioniong yes/no
 WEIGHTED='no',                ! Constraints ? yes/no
 PARTICLE='./weightfile.h5',    ! Lagrangian particile file
 OUTPUTXMF='yes',               ! Write xmf file yes/no (requires memory and time)
 OUTPUT_STATS='yes',            ! Output detailed stats
 /" > partition.choices

./partition_main.e_KRAKEN

mkdir -p ./OUTPUTED_MESH_PARTITIONS ./HASH_TABLES

