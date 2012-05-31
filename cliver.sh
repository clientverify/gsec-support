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
VERBOSE_OUTPUT=1
MAKE_THREADS=4
USE_LSF=0
USE_INTERACTIVE_LSF=0
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
MAX_MEMORY=8000
WARN_MEMORY=6000
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
  # FORMAT: $MODE"_"$i"_"$INPUT_GEN_TYPE"_"$ptype"_"$rate"_"$MAX_ROUND"_"$PLAYER_NAME"_"$SERVER_ADDRESS
  local random_seed=$(parse_tetrinet_ktest_filename $1 2)
  local starting_height=$(parse_tetrinet_ktest_filename $1 2)
  local input_gen_type=$(parse_tetrinet_ktest_filename $1 3)
  local partial_type=$(parse_tetrinet_ktest_filename $1 4)
  local partial_rate=$(parse_tetrinet_ktest_filename $1 5)
  local player_name="$(parse_tetrinet_ktest_filename $1 7)"
  local server_address="$(parse_tetrinet_ktest_filename $1 8)"

  local bc_file_opts="-autostart "
  bc_file_opts+="-startingheight 0 "
  bc_file_opts+="-partialtype $partial_type "
  bc_file_opts+="-partialrate $partial_rate "
  bc_file_opts+="-inputgenerationtype 13 "
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
      KTEST_DIR="$DATA_DIR/network/tetrinet/recent"
      BC_FILE="$TETRINET_ROOT/bin/tetrinet-klee.bc"
      TRAINING_DIR="$DATA_DIR/training/tetrinet-klee/recent"
      ;;
    xpilot*)
      # need to automatically set this var...
      if test ! ${XPILOTHOST+defined}; then
        echo "set XPILOTHOST environment variable before running xpilot"
        exit
      fi
      KTEST_DIR="$DATA_DIR/network/xpilot-game/recent"
      BC_FILE="$XPILOT_ROOT/bin/xpilot-ng-x11.bc"
      TRAINING_DIR="$DATA_DIR/training/xpilot-ng-x11/recent"
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
  cliver_params+="-use-tee-buf=$USE_TEE_BUF "
  cliver_params+="-libc=$CLIVER_LIBC "
  cliver_params+="-switch-type=$SWITCH_TYPE "
  cliver_params+="-output-source=$OUTPUT_LLVM_ASSEMBLY "
  cliver_params+="-output-module=$OUTPUT_LLVM_BITCODE "
  cliver_params+="-max-memory=$MAX_MEMORY "
  cliver_params+="-state-trees-memory-limit=$WARN_MEMORY "
  cliver_params+="-always-print-object-bytes=$PRINT_OBJECT_BYTES " 
  cliver_params+="-debug-execution-tree=$DEBUG_EXECUTION_TREE "
  cliver_params+="-debug-address-space-graph=$DEBUG_ADDRESS_SPACE_GRAPH " 
  cliver_params+="-debug-state-merger=$DEBUG_STATE_MERGER "
  cliver_params+="-debug-network-manager=$DEBUG_NETWORK_MANAGER "
  cliver_params+="-debug-socket=$DEBUG_SOCKET "
  cliver_params+="-debug-searcher=$DEBUG_SEARCHER "
  #cliver_params+="-debug-print-instructions=$PRINT_INSTRUCTIONS "
  cliver_params+="-debug-print-execution-events=$DEBUG_PRINT_EXECUTION_EVENTS "
  #cliver_params+="-no-output=$DISABLE_OUTPUT "
  cliver_params+=" $EXTRA_CLIVER_OPTIONS "

  # BC specific cliver options
  case $BC_MODE in
    xpilot*)
      cliver_params+="-load=$ROOT_DIR/$XLIB_DIR/libSM.so "
      cliver_params+="-load=$ROOT_DIR/$XLIB_DIR/libICE.so "
      cliver_params+="-load=$ROOT_DIR/$XLIB_DIR/libX11.so "
      cliver_params+="-load=$ROOT_DIR/$XLIB_DIR/libXext.so "
      cliver_params+="-load=$ROOT_DIR/$XLIB_DIR/libXxf86misc.so.1 "
      cliver_params+="-no-xwindows "
      ;;
  esac

  printf "%s" "$cliver_params"
}

run_cliver()
{
  if [ $USE_LSF -eq 1 ]; then
    lbsub $CLIVER_BIN $@
  elif [ $USE_INTERACTIVE_LSF -eq 1 ]; then
    ibsub $CLIVER_BIN $@
  elif [ $USE_GDB -eq 1 ]; then
    geval $CLIVER_BIN-bin $@
    exit
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

    cliver_params+="-socket-log $i "
    cliver_params+="-output-dir $CLIVER_OUTPUT_DIR/$ktest_basename "
    cliver_params+="-copy-input-files-to-output-dir=1 "
    cliver_params+="-cliver-mode=$CLIVER_MODE "
    cliver_params+="-client-model=$BC_MODE "

    cliver_params+="$BC_FILE $(bc_parameters $i) "

    run_cliver $cliver_params

  done
}

do_verification()
{
  for i in $KTEST_DIR/*ktest; do

    local ktest_basename=$(basename $i .ktest)
    local cliver_params="$(cliver_parameters)"

    cliver_params+="-socket-log $i "
    cliver_params+="-output-dir $CLIVER_OUTPUT_DIR/$ktest_basename "
    cliver_params+="-cliver-mode=$CLIVER_MODE "
    cliver_params+="-client-model=$BC_MODE "

    cliver_params+="$BC_FILE $(bc_parameters $i) "

    run_cliver $cliver_params

  done
}

do_ncross_verification()
{
  if [[ $(expr match $CLIVER_MODE "self") -gt 0 ]]; then
    NCROSS_MODE="self"
    CLIVER_MODE=${CLIVER_MODE#"self-"}
  elif [[ $(expr match $CLIVER_MODE "ncross") -gt 0 ]]; then
    NCROSS_MODE="ncross"
    CLIVER_MODE=${CLIVER_MODE#"ncross-"}
  else
    echo "Error: invalid mode $CLIVER_MODE"
    exit 1
  fi

  leval echo "CLIVER_MODE=$CLIVER_MODE"

  declare -a training_dirs=( $TRAINING_DIR/* )
  local num_dirs=${#training_dirs[@]}

  indices="$(seq 0 $(($num_dirs - 1)))"

  # Check that we trained on the same bc file used for verification
  for i in $indices; do
    local training_bc_file="${training_dirs[$i]}/input.bc" 
    if ! cmp $training_bc_file $BC_FILE > /dev/null; then
      echo "Error: $training_bc_file and $BC_FILE differ."
      exit 1
    fi 
  done

  for i in $indices; do
    leval echo "Cross validating ${training_dirs[$i]} with $(($num_dirs -1)) training sets"

    local ktest_file="${training_dirs[$i]}/socket_000.ktest"
    local ktest_basename=$(basename ${training_dirs[$i]})
    local cliver_params="$(cliver_parameters) "

    cliver_params+="-socket-log $ktest_file "
    cliver_params+="-output-dir $CLIVER_OUTPUT_DIR/$ktest_basename "
    cliver_params+="-cliver-mode=$CLIVER_MODE "
    cliver_params+="-client-model=$BC_MODE "

    for k in $indices; do
      if [[ $NCROSS_MODE == "ncross" ]] ; then
        if [ $i != $k ]; then
          cliver_params+=" -training-path-dir=${training_dirs[$k]}/ "
        fi 
      elif [[ $NCROSS_MODE == "self" ]] ; then
        if [ $i == $k ]; then
          cliver_params+=" -training-path-dir=${training_dirs[$k]}/ "
        fi 
      fi
    done

    cliver_params+="$BC_FILE $(bc_parameters $ktest_basename.ktest) "
    run_cliver $cliver_params
  done
}

usage()
{
  echo -e "$0\n\nUSAGE:"
  echo -e "\t-t [verify|training|ncross]\t\t(type of verification)(REQUIRED)" 
  echo -e "\t-c [xpilot|tetrinet]\t\t\t(client binary)(REQUIRED)"
  echo -e "\t-i [gdb|lsf|interactive]\t\t(run mode)"
  echo -e "\t-x [\"\"]\t\t\t\t\t(additional cliver options)"
  echo -e "\t-d [0|1|2]\t\t\t\t(debug level)"
  echo -e "\t-m [gigabytes]\t\t\t\t(maximum memory usage)"
  echo -e "\t-p [heapprofile|heaplocal|heapcheck]\t(memory profiling options)"
  echo -e "\t-r [dir]\t\t\t\t(alternative root directory)"
  echo -e "\t-n \t\t\t\t\t(dry run)"
  echo -e "\t-s \t\t\t\t\t(silent)"
  echo -e "\t-h \t\t\t\t\t(help/usage)"
}

main() 
{
  while getopts "t:c:x:i:p:d:r:m:nshv" opt; do
    case $opt in

      t)
        CLIVER_MODE="$OPTARG"
        ;;

      c)
        BC_MODE="$OPTARG"
        ;;

      x)
        EXTRA_CLIVER_OPTIONS="$OPTARG"
        ;;

      m)
        MAX_MEMORY=$(($OPTARG*1000))
        WARN_MEMORY=$(($MAX_MEMORY-($MAX_MEMORY/8)))
        ;;
      i)
        case $OPTARG in
          interactive*)
            USE_INTERACTIVE_LSF=1
            ;;
          gdb*)
            DISABLE_OUTPUT=1
            USE_GDB=1
            ;;
          lsf*)
            USE_LSF=1
            VERBOSE_OUTPUT=0
            ;;
        esac
        ;;
 
      p)
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

      d)
        # debug levels
        if [[ $OPTARG -ge 0 ]]; then
          DEBUG_SEARCHER=1
          DEBUG_NETWORK_MANAGER=1
        fi
        if [[ $OPTARG -ge 1 ]]; then
          DEBUG_EXECUTION_TREE=1
          DEBUG_STATE_MERGER=1
          DEBUG_ADDRESS_SPACE_GRAPH=1
        fi
        if [[ $OPTARG -ge 2 ]]; then
          DEBUG_SOCKET=1
          DEBUG_PRINT_EXECUTION_EVENTS=1
        fi
        ;;

      r)
        echo "Setting root dir to $OPTARG"
        ROOT_DIR="$OPTARG"
        ;;

      n)
        DRY_RUN=1
        ;;

      v)
        VERBOSE_OUTPUT=1
        ;;

      s)
        VERBOSE_OUTPUT=0
        ;;

      h)
        usage
        exit
        ;;
      :)
        echo "Option -$OPTARG requires an argument"
        usage
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

    self* )
      do_ncross_verification
      ;;

    ncross* )
      do_ncross_verification
      ;;

    training )
      do_training
      ;;

    edit*)
      do_verification
      ;;

    naive*)
      do_verification
      ;;

  esac
  echo "[elapsed time: $(elapsed_time $start_time)]"
}

# Run main
main "$@"
