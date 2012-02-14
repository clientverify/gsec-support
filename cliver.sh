#!/bin/bash

# see http://www.davidpashley.com/articles/writing-robust-shell-scripts.html
set -u # Exit if uninitialized value is used 
set -e # Exit on non-true value
set -o pipefail # exit on fail of any command in a pipe

WRAPPER="`readlink -f "$0"`"
HERE="`dirname "$WRAPPER"`"

# Include gsec_common
. $HERE/gsec_common

# Default command line options
VERBOSE_OUTPUT=0
MAKE_THREADS=4
USE_LSF=0
USE_GDB=0
USE_HEAP_PROFILER=0
USE_HEAP_CHECK=0
USE_HEAP_CHECK_LOCAL=0
ROOT_DIR="`pwd`"
BC_MODE="tetrinet"
	
# Default cliver options
CLIVER_MODE="training"
CLIVER_LIBC="uclibc"
OUTPUT_LLVM_ASSEMBLY=0
OUTPUT_LLVM_BITCODE=0
PRINT_INSTRUCTIONS=0
MAX_MEMORY=64000
SWITCH_TYPE="simple"
USE_TEE_BUF=1
DISABLE_OUTPUT=0
DEBUG_PRINT_EXECUTION_EVENTS=0
DEBUG_EXECUTION_TREE=0
DEBUG_ADDRESS_SPACE_GRAPH=0
DEBUG_STATE_MERGER=0
DEBUG_NETWORK_MANAGER=0
DEBUG_SOCKET=0
DEBUG_SEARCHER=0
PRINT_OBJECT_BYTES=0
EXTRA_CLIVER_OPTIONS=""

parse_tetrinet_ktest_filename()
{
	eval "basename $1 .ktest | awk -F_ '{ printf \$$2 }'"
}

tetrinet_parameters()
{
  local random_seed=$(parse_tetrinet_ktest_filename $1 2)
	local starting_height=$(parse_tetrinet_ktest_filename $1 2)
	local input_gen_type=$(parse_tetrinet_ktest_filename $1 3)
	local partial_type=$(parse_tetrinet_ktest_filename $1 4)
	local partial_rate=$(parse_tetrinet_ktest_filename $1 5)
	local player_name="$(parse_tetrinet_ktest_filename $1 7)"
	local server_address="$(parse_tetrinet_ktest_filename $1 8)"

	local bc_file_opts="-autostart "
	bc_file_opts+="-startingheight $starting_height "
	bc_file_opts+="-partialtype $partial_type "
	bc_file_opts+="-partialrate $partial_rate "
	bc_file_opts+="-inputgenerationtype 4 "
	bc_file_opts+="-seed $random_seed "
	bc_file_opts+=" $player_name $server_address "
	printf "%s" "$bc_file_opts"
}

xpilot_parameters()
{
	local GEOMETRY="800x600+100+100"
	local bc_file_opts=""
	bc_file_opts+=" -join -texturedWalls no -texturedDecor no -texturedObjects no "
	bc_file_opts+=" -fullColor no -geometry $GEOMETRY "
	bc_file_opts+=" -keyTurnLeft a -keyTurnRight d -keyThrust w localhost "

	printf "%s" "$bc_file_opts"
}

initialize_bc()
{
	case $BC_MODE in
		tetri*)
			KTEST_DIR="$DATA_DIR/network/tetrinet/last-run"
			BC_FILE="$TETRINET_ROOT/bin/tetrinet-klee.bc"
			;;
		xpilot*)
			# need to automatically set this var...
			if [ -n "${XPILOTHOST:+x}" ] 
				echo "set XPILOTHOST environment variable before running xpilot"
				exit
			fi
			KTEST_DIR="$DATA_DIR/network/xpilot-server/recent"
			BC_FILE="$XPILOT_ROOT/bin/xpilot-ng-x11.bc"
			;;
	esac
}

bc_parameters()
{
	case $BC_MODE in
		tetri*)
			tetrinet_parameters $1
			;;
		xpilot*)
			xpilot_parameters $1
			;;
	esac
}

initialize_cliver()
{
	CLIVER_BIN="$KLEE_ROOT/bin/cliver"

	BASE_OUTPUT_DIR=$DATA_DIR/$CLIVER_MODE/$(basename $BC_FILE .bc)

	CLIVER_OUTPUT_DIR=$BASE_OUTPUT_DIR/$RUN_PREFIX

	leval mkdir -p $CLIVER_OUTPUT_DIR
	leval ln -sfT $RUN_PREFIX $BASE_OUTPUT_DIR/recent
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
	cliver_params+="-debug-print-execution-events=$DEBUG_PRINT_EXECUTION_EVENTS "
	cliver_params+="-debug-execution-tree=$DEBUG_EXECUTION_TREE "
	cliver_params+="-debug-address-space-graph=$DEBUG_ADDRESS_SPACE_GRAPH " 
	cliver_params+="-debug-state-merger=$DEBUG_STATE_MERGER "
	cliver_params+="-debug-network-manager=$DEBUG_NETWORK_MANAGER "
	cliver_params+="-debug-socket=$DEBUG_SOCKET "
	cliver_params+="-debug-searcher=$DEBUG_SEARCHER "
	cliver_params+="-debug-print-instructions=$PRINT_INSTRUCTIONS "
	cliver_params+="-cliver-mode=$CLIVER_MODE "
	cliver_params+=" $EXTRA_CLIVER_OPTIONS "

	# BC specific cliver options
	case $BC_MODE in
		xpilot*)
			cliver_params+="-load=/usr/lib64/libSM.so -load=/usr/lib64/libICE.so "
			cliver_params+="-load=/usr/lib64/libXext.so  -load=/usr/lib64/libX11.so "
			cliver_params+="-load=/usr/lib64/libXxf86misc.so.1 "
			cliver_params+="-xpilot-socket=1 "
			;;
	esac

	printf "%s" "$cliver_params"
}

run_cliver()
{
 	if [ $USE_LSF -eq 1 ]; then
 		lbsub $CLIVER_BIN $@
 	elif [ $USE_GDB -eq 1 ]; then
 		geval $CLIVER_BIN-bin $@
 	elif [ $USE_HEAP_PROFILER -eq 1 ]; then
 		leval env HEAPPROFILE=$CLIVER_OUTPUT_DIR/cliver $CLIVER_BIN-bin $@
 	elif [ $USE_HEAP_CHECK -eq 1 ]; then
 		leval env HEAPCHECK=normal $CLIVER_BIN-bin $@
 	elif [ $USE_HEAP_CHECK_LOCAL -eq 1 ]; then
 		leval env HEAPCHECK=local $CLIVER_BIN-bin $@
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

		cliver_params+="$BC_FILE $(bc_parameters $i) "

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

		cliver_params+="$BC_FILE $(bc_parameters $i) "

		run_cliver $cliver_params

	done
}

main() 
{
  while getopts ":vr:j:b:lm:dgx:eh:" opt; do
    case $opt in
			b)
				BC_MODE="$OPTARG"
				;;
			x)
				EXTRA_CLIVER_OPTIONS="$OPTARG"
				;;
      l)
        USE_LSF=1
				;;
      
			g)
        USE_GDB=1
				;;
 
			h)
				case $OPTARG in
					heapprofile*)
						USE_HEAP_PROFILER=1
						;;
					heaplocal*)
						USE_HEAP_CHECK_LOCAL=1
						;;
					heapcheck*)
						USE_HEAP_CHECK=1
						;;
				esac
				;;

			e)
        DEBUG_PRINT_EXECUTION_EVENTS=1
				;;
			d)
				DEBUG_ADDRESS_SPACE_GRAPH=1
				DEBUG_STATE_MERGER=1
				DEBUG_NETWORK_MANAGER=1
				DEBUG_SOCKET=1
				DEBUG_SEARCHER=1
				DEBUG_EXECUTION_TREE=1
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
	initialize_bc
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

		testtraining )
			do_verification
			;;

		verif*)
			do_verification
			;;

	esac

  echo "[elapsed time: $(elapsed_time $start_time)]"
}

# Run main
main "$@"
