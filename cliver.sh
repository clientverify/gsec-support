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
USE_GDB=0
ROOT_DIR="`pwd`"
	
# Default cliver options
CLIVER_MODE="training"
CLIVER_LIBC="uclibc"
OUTPUT_LLVM_ASSEMBLY=0
OUTPUT_LLVM_BITCODE=0
PRINT_INSTRUCTIONS=0
MAX_MEMORY=32000
SWITCH_TYPE="simple"
USE_TEE_BUF=1
DISABLE_OUTPUT=0
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

parse_tetrinet_parameters()
{
  local random_seed=$(parse_ktest_file $1 2)
	local starting_height=$(parse_ktest_file $1 2)
	local input_gen_type=$(parse_ktest_file $1 3)
	local partial_type=$(parse_ktest_file $1 4)
	local partial_rate=$(parse_ktest_file $1 5)
	local player_name="$(parse_ktest_file $1 7)"
	local server_address="$(parse_ktest_file $1 8)"

	local bc_file_opts="-autostart "
	bc_file_opts+="-startingheight $starting_height "
	bc_file_opts+="-partialtype $partial_type "
	bc_file_opts+="-partialrate $partial_rate "
	bc_file_opts+="-seed $random_seed "
	bc_file_opts+=" $player_name $server_address "
	printf "%s" "$bc_file_opts"
}

initialize_cliver()
{
	CLIVER_BIN="$KLEE_ROOT/bin/cliver"

	BASE_OUTPUT_DIR=$DATA_DIR/$CLIVER_MODE/$(basename $BC_FILE .bc)

	CLIVER_OUTPUT_DIR=$BASE_OUTPUT_DIR/$RUN_PREFIX

	leval mkdir -p $CLIVER_OUTPUT_DIR
	leval ln -sfT $RUN_PREFIX $BASE_OUTPUT_DIR/recent
}

initialize_tetrinet()
{
	KTEST_DIR="$DATA_DIR/network/tetrinet/last-run"
	BC_FILE="$TETRINET_ROOT/bin/tetrinet-klee.bc"
}

cliver_parameters()
{
	local cliver_params="-posix-runtime -pc-single-line -emit-all-errors -debug-stderr "
	cliver_params+="-no-output=$DISABLE_OUTPUT "
	cliver_params+="-use-tee-buf=$USE_TEE_BUF "
	cliver_params+="-libc=$CLIVER_LIBC "
	cliver_params+="-switch-type=$SWITCH_TYPE "
	cliver_params+="-output-source=$OUTPUT_LLVM_ASSEMBLY "
	cliver_params+="-output-module=$OUTPUT_LLVM_BITCODE "
	cliver_params+="-max-memory=$MAX_MEMORY "
	cliver_params+="-always-print-object-bytes=$PRINT_OBJECT_BYTES " 
	cliver_params+="-debug-address-space-graph=$DEBUG_ADDRESS_SPACE_GRAPH " 
	cliver_params+="-debug-state-merger=$DEBUG_STATE_MERGER "
	cliver_params+="-debug-network-manager=$DEBUG_NETWORK_MANAGER "
	cliver_params+="-debug-socket=$DEBUG_SOCKET "
	cliver_params+="-debug-searcher=$DEBUG_SEARCHER "
	cliver_params+="-debug-print-instructions=$PRINT_INSTRUCTIONS "
	cliver_params+="-cliver-mode=$CLIVER_MODE "
	printf "%s" "$cliver_params"
}

run_cliver()
{
 	if [ $USE_LSF -eq 1 ]; then
 		lbsub $CLIVER_BIN $@
 	elif [ $USE_GDB -eq 1 ]; then
 		geval $CLIVER_BIN-bin $@
 	else
 		leval $CLIVER_BIN-bin $@
 	fi
}

do_training()
{
	for i in $KTEST_DIR/*ktest; do

		local ktest_basename=$(basename $i .ktest)
		local cliver_params="$(cliver_parameters)"

		cliver_params+=" -socket-log $i "
		cliver_params+=" -output-dir $CLIVER_OUTPUT_DIR/$ktest_basename "

		cliver_params+="$BC_FILE $(parse_tetrinet_parameters $i) "

		run_cliver $cliver_params

	done
}

do_verification()
{
	for i in $KTEST_DIR/*ktest; do

		local ktest_basename=$(basename $i .ktest)
		local cliver_params="$(cliver_parameters)"

		cliver_params+=" -socket-log $i "
		cliver_params+=" -output-dir $CLIVER_OUTPUT_DIR/$ktest_basename "

		cliver_params+="$BC_FILE $(parse_tetrinet_parameters $i) "

		run_cliver $cliver_params

	done
}

main() 
{
  while getopts ":vr:j:blm:dg" opt; do
    case $opt in
      l)
        USE_LSF=1
				;;
      
			g)
        USE_GDB=1
				;;

			d)
				DEBUG_ADDRESS_SPACE_GRAPH=1
				DEBUG_STATE_MERGER=1
				DEBUG_NETWORK_MANAGER=1
				DEBUG_SOCKET=1
				DEBUG_SEARCHER=1
				;;

      v)
        VERBOSE_OUTPUT=1
        ;;
  
      r)
        echo "Setting root dir to $OPTARG"
        ROOT_DIR="$OPTARG"
        ;;
   
      m)
        CLIVER_MODE="$OPTARG"
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

	echo "[cliver mode: $CLIVER_MODE]"

  initialize_root_directories
  initialize_logging $@

	# bc file initialization
	initialize_tetrinet

	initialize_cliver

	if [ $USE_LSF -eq 1 ]; then
		initialize_lsf
	fi

  # record start time
  start_time=$(elapsed_time)

	case $CLIVER_MODE in

		training )
			do_training
			;;

		verif*)
			do_verification
			;;

	esac

  echo "[elapsed time: $(elapsed_time $start_time)]"
}

# Run main
main "$@"
