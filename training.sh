#!/bin/bash

# see http://www.davidpashley.com/articles/writing-robust-shell-scripts.html
set -u # Exit if uninitialized value is used 
set -e # Exit on non-true value
set -o pipefail # exit on fail of any command in a pipe

WRAPPER="`readlink -f "$0"`"
HERE="`dirname "$WRAPPER"`"

# Include gsec_common
. $HERE/gsec_common

# Command line options
VERBOSE_OUTPUT=0
MAKE_THREADS=4
USE_LSF=0
ROOT_DIR="`pwd`"
	
# Cliver options
CLIVER_MODE="training"
OUTPUT_LLVM_ASSEMBLY=0
PRINT_INSTRUCTIONS=0
MAX_MEMORY=16000
SWITCH_TYPE="simple"
DEBUG_ADDRESS_SPACE_GRAPH=0
DEBUG_STATE_MERGER=0
DEBUG_NETWORK_MANAGER=0
DEBUG_SOCKET=0
DEBUG_SEARCHER=0
PRINT_OBJECT_BYTES=0

parse_ktest_file()
{
	eval "basename $1 .ktest | awk -F_ '{ printf \$$2 }'"
}

initialize_training()
{
	KTEST_DIR="$DATA_DIR/network/tetrinet/last-run"
	TRAINING_DIR=$DATA_DIR/$CLIVER_MODE/$(basename $BC_FILE .bc)

	CLIVER_OUTPUT_DIR=$TRAINING_DIR/$RUN_PREFIX
	
	CLIVER_BIN="$KLEE_ROOT/bin/cliver"

	BC_FILE="$TETRINET_ROOT/bin/tetrinet-klee.bc"

	leval mkdir -p $CLIVER_OUTPUT_DIR
	leval ln -sf $CLIVER_OUTPUT_DIR $TRAINING_DIR/recent
}

tetrinet_training()
{
	for i in $KTEST_DIR/*ktest; do

		local ktest_basename=$(basename $i .ktest)
		local cliver_opts=$CLIVER_OPTS
		cliver_opts+=" -socket-log $i "
		cliver_opts+=" -output-dir $CLIVER_OUTPUT_DIR/$ktest_basename "

	  local random_seed=$(parse_ktest_file $i 2)
		local starting_height=$(parse_ktest_file $i 2)
		local input_gen_type=$(parse_ktest_file $i 3)
		local partial_type=$(parse_ktest_file $i 4)
		local partial_rate=$(parse_ktest_file $i 5)
		local player_name="$(parse_ktest_file $i 7)"
		local server_address="$(parse_ktest_file $i 8)"

		local bc_file_opts="-autostart "
		bc_file_opts+="-startingheight $starting_height "
		bc_file_opts+="-partialtype $partial_type "
		bc_file_opts+="-partialrate $partial_rate "
		bc_file_opts+="-seed $random_seed "
		bc_file_opts+=" $player_name $server_address "

		cliver_opts+="$BC_FILE $bc_file_opts "

		if [ $USE_LSF -eq 1]; then
			lbsub $CLIVER_BIN $cliver_opts
		else
			leval $CLIVER_BIN $cliver_opts
		fi

	done
}

do_training()
{
  echo "[cliver training]"

	CLIVER_OPTS+="-libc=uclibc -posix-runtime "
	CLIVER_OPTS+="-pc-single-line -debug-stderr -emit-all-errors "
	CLIVER_OPTS+="-switch-type=$SWITCH_TYPE "
	CLIVER_OPTS+="-output-source=$OUTPUT_LLVM_ASSEMBLY "
	CLIVER_OPTS+="-max-memory=$MAX_MEMORY "
	CLIVER_OPTS+="-always-print-object-bytes=$PRINT_OBJECT_BYTES " 
	CLIVER_OPTS+="-debug-address-space-graph=$DEBUG_ADDRESS_SPACE_GRAPH " 
	CLIVER_OPTS+="-debug-state-merger=$DEBUG_STATE_MERGER "
	CLIVER_OPTS+="-debug-network-manager=$DEBUG_NETWORK_MANAGER "
	CLIVER_OPTS+="-debug-socket=$DEBUG_SOCKET "
	CLIVER_OPTS+="-debug-searcher=$DEBUG_SEARCHER "
	CLIVER_OPTS+="-debug-print-instructions=$PRINT_INSTRUCTIONS "
	CLIVER_OPTS+="-cliver-mode=$CLIVER_MODE "
	#CLIVER_OPTS+="-output-dir $CLIVER_OUTPUT_DIR/"

	tetrinet_training

  echo "[done]"
}

main() 
{
  while getopts ":vr:j:bl" opt; do
    case $opt in
      l)
        USE_LSF=1
				;;

      v)
        VERBOSE_OUTPUT=1
        ;;
  
      r)
        echo "Setting root dir to $OPTARG"
        ROOT_DIR="$OPTARG"
        ;;
  
      j)
        MAKE_THREADS=$OPTARG
        ;;
  
      :)
        echo "Option -$OPTARG requires an argument"
        exit
        ;;
  
    esac
  done

  initialize_root_directories

  initialize_logging $@

  # record start time
  start_time=$(elapsed_time)

	initialize_training
	do_training

  echo "Elapsed time: $(elapsed_time $start_time)"
}

# Run main
main "$@"
