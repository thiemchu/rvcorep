#!/bin/bash
# This file should be placed in the same folder as the verilog file containing the top module

if (( $# != 3 )); then
    echo "Usage: ./vivado.sh <#threads> <walltime(hour(s))> <vivado version (e.g., 20183, 20191, etc.)>"
    echo "Got $# args"
    exit
fi

current_dir=`pwd`

vivado_ver=$3
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
vivado_runtime_max_days=$(( $2 / 24 ))
vivado_runtime_max_hours=$(( $2 - 24 * $vivado_runtime_max_days ))
set +x # disables "set -x"

out_dir="${current_dir}/vivado"
mkdir -p $out_dir

tcl_file="${current_dir}/vivado.tcl"
log_file="${out_dir}/vivado.log"
jou_file="${out_dir}/vivado.jou"

current_datetime="`date +%Y%m%d%H%M%S`"
jobname="${current_datetime}_${PWD##*/}"

slurm_o_file="${out_dir}/slurm_${jobname}_o.log"
slurm_e_file="${out_dir}/slurm_${jobname}_e.log"

printf \
"#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=$vivado_num_threads
#SBATCH --time=${vivado_runtime_max_days}-${vivado_runtime_max_hours}:00:00
#SBATCH --job-name=$jobname
#SBATCH --output=$slurm_o_file
#SBATCH --error=$slurm_e_file
cd $current_dir
$vivado_bin \
-log $log_file \
-journal $jou_file \
-mode batch \
-source $tcl_file \
-tclargs $out_dir $vivado_num_threads \
>  ${out_dir}/stdout.txt \
2> ${out_dir}/stderr.txt" | sbatch
