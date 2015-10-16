#!/bin/bash

################################################################################
# coreutils_exp.sh
#
################################################################################

# see http://www.davidpashley.com/articles/writing-robust-shell-scripts.html
set -u # Exit if uninitialized value is used 
set -e # Exit on non-true value
set -o pipefail # exit on fail of any command in a pipe

WRAPPER="`readlink -f "$0"`"
HERE="`dirname "$WRAPPER"`"
ERROR_EXIT=1
PROG=$(basename $0)

# Include gsec_common
. $HERE/gsec_common

# Default command line options
VERBOSE_OUTPUT=1
EXP_NAME=coreutils

ROOT_DIR="`pwd`"
initialize_root_directories
initialize_logging

if test ! ${DATA_TAG+defined}; then
  DATA_TAG="recent"
fi

BASE_OUTPUT_DIR=$DATA_DIR/$EXP_NAME
KLEE_OUTPUT_DIR=$BASE_OUTPUT_DIR/$RUN_PREFIX
mkdir -p $KLEE_OUTPUT_DIR
leval ln -sfT $RUN_PREFIX $BASE_OUTPUT_DIR/$DATA_TAG

################################################################################

thread_counts=(1 2 4 8 16 24)
search_types=(nurs:covnew bfs dfs)
#bc_files=(echo.bc printf.bc)
bc_files=(printf.bc)

bc_dir="/playpen/rac/coreutils/src/coreutils-6.11/obj-llvm/src/"
#bc_cmds=("--sym-args 0 2 5 --sym-args 0 1 10 --sym-files 2 10" "--sym-args 0 4 5 --sym-args 0 1 10")
bc_cmds=("--sym-args 0 4 5 --sym-args 0 1 10")
max_time=600
klee_bin=klee
#klee_bin=klee-st

klee_options=" --use-forked-solver=0 --only-output-states-covering-new  --optimize --libc=uclibc --cloud9-posix-runtime "
klee_options+="--force-parallel-searcher --use-batching-search=1 --batch-time=1 "
klee_options+=" --output-istats=1 --use-call-paths=0 --no-output "
stats_file="coreutils.csv"
################################################################################

run_exp()
{
  STATS_OUTPUT=$KLEE_OUTPUT_DIR/$stats_file
  echo "bc,search,threads,instructions,paths,tests" | tee -a $STATS_OUTPUT
  #for bc_file in ${bc_files[@]}; do 
  for search_type in ${search_types[@]}; do 
    for i in `seq 0 $((${#bc_files[@]} - 1))` ; do
      bc_file=${bc_files[$i]}
      bc_name=$(basename $bc_file .bc)
      for j in `seq 0 $((${#thread_counts[@]} - 1))` ; do
        thread_count=${thread_counts[$j]}
        bc_cmd=${bc_cmds[$i]}
        exp_name="${bc_name}-${thread_count}-$search_type"
        output_dir=$KLEE_OUTPUT_DIR/$exp_name
        leval ./local/bin/${klee_bin} --output-dir=$output_dir --max-time=${max_time} --watchdog --search=${search_type} --use-threads=${thread_count}  ${klee_options} ${bc_dir}/${bc_file} ${bc_cmd}
        instructions=$(grep "total instructions" ${output_dir}/info | awk -F=  '{print $2}')
        paths=$(grep "completed paths" ${output_dir}/info | awk -F=  '{print $2}')
        tests=$(grep "generated tests" ${output_dir}/info | awk -F=  '{print $2}')
        echo "$bc_name,$search_type,$thread_count,$instructions,$paths,$tests" | tee -a $STATS_OUTPUT
        #echo "$bc_name,$search_type,$thread_count,instructions,paths,tests" | tee -a $STATS_OUTPUT
      done
    done
  done
}

klee_options=" --use-forked-solver=0 --only-output-states-covering-new  --optimize --libc=uclibc --cloud9-posix-runtime "
klee_options+="--force-parallel-searcher --use-batching-search=1 --batch-time=1 "
klee_options+=" --output-istats=1 --use-call-paths=0 --no-output "
#search_types=(nurs:covnew bfs dfs)
search_types=(nurs:covnew)
run_exp

#klee_options=" --use-forked-solver=0 --only-output-states-covering-new  --optimize --libc=uclibc --cloud9-posix-runtime "
#klee_options+="--force-parallel-searcher --use-batching-search=1 --batch-time=1 "
#klee_options+=" --output-istats=1 --use-call-paths=0 --no-output "
#search_types=(nurs:covnew)
#run_exp()

