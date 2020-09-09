#!/bin/bash

if (( $# != 2 )); then
    echo "Usage: ./vivado.sh <#threads> <vivado version (e.g., 20183, 20191, etc.)>"
    echo "Got $# args"
    exit
fi

current_dir=`pwd`

vivado_ver=$2
if [ $vivado_ver -eq 20174 ]; then
    vivado_bin="/opt/Xilinx/Vivado/2017.4/bin/vivado"
elif [ $vivado_ver -eq 20183 ]; then
    vivado_bin="/tools/Xilinx/Vivado/2018.3/bin/vivado"
elif [ $vivado_ver -eq 20191 ]; then
    vivado_bin="/tools/Xilinx/Vivado/2019.1/bin/vivado"
elif [ $vivado_ver -eq 20192 ]; then
    vivado_bin="/tools/Xilinx/Vivado/2019.2/bin/vivado"
else
    echo "Not supported vivado version"
    exit
fi

if [ ! -f $vivado_bin ]; then
    echo "The specified Vivado version has not been installed yet"
    exit
fi

set -x # enables a mode of the shell where all executed commands are printed to the terminal
vivado_num_threads=$(( $1 <= 8 ? $1 : 8 ))
out_dir="${current_dir}/vivado"
set +x # disables "set -x"

mkdir -p $out_dir

tcl_file="${current_dir}/vivado.tcl"
log_file="${out_dir}/vivado.log"
jou_file="${out_dir}/vivado.jou"

$vivado_bin \
    -log $log_file \
    -journal $jou_file \
    -mode batch \
    -source $tcl_file \
    -tclargs $out_dir $vivado_num_threads \
    >  ${out_dir}/stdout.txt \
    2> ${out_dir}/stderr.txt &
