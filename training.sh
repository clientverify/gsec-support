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

tetrinet_training()
{
	for i in $KTEST_DIR/*ktest; do

		local cliver_opts=$CLIVER_OPTS
		cliver_opts+=" -socket-log $i "

	  random_seed=$(parse_ktest_file $i 2)
		starting_height=$(parse_ktest_file $i 2)
		input_gen_type=$(parse_ktest_file $i 3)
		partial_type=$(parse_ktest_file $i 4)
		partial_rate=$(parse_ktest_file $i 5)
		player_name="$(parse_ktest_file $i 7)"
		server_address="$(parse_ktest_file $i 8)"

		bc_file_opts="-autostart "
		bc_file_opts+="-startingheight $starting_height "
		bc_file_opts+="-partialtype $partial_type "
		bc_file_opts+="-partialrate $partial_rate "
		bc_file_opts+="-seed $random_seed "
		bc_file_opts+=" $player_name $server_address "

		cliver_opts+="$BC_FILE $bc_file_opts "

		leval $CLIVER_BIN $cliver_opts

	done
}

do_training()
{
  echo "[cliver training]"

	BC_FILE="$TETRINET_ROOT/bin/tetrinet-klee.bc"

	KTEST_DIR="$DATA_DIR/network/tetrinet/last-run"
	CLIVER_OUTPUT_DIR=$DATA_DIR/$CLIVER_MODE/$(basename $BC_FILE .bc)
	mkdir -p $CLIVER_OUTPUT_DIR
  CLIVER_BIN="$KLEE_ROOT/bin/cliver"

	CLIVER_OPTS+="-libc=uclibc -posix-runtime "
	CLIVER_OPTS+="-pc-single-line -debug-stderr -emit-all-errors "
	CLIVER_OPTS+="-output-dir $CLIVER_OUTPUT_DIR/$RUN_PREFIX "
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

	tetrinet_training

  echo "[done]"
}

main() 
{
  while getopts ":vr:j:" opt; do
    case $opt in
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

	do_training

  echo "Elapsed time: $(elapsed_time $start_time)"
}

# Run main
main "$@"
