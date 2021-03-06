#!/bin/bash

################################################################################
# cliver.sh - helper script for cliver. 
#
# - Handles parameters for openssl, boringssl, xpilot and tetrinet clients
# - Several modes for verifying ktest network logs
#   - naive: BFS search for a valid execution path for a given network log
#   - training: same as naive but output execution fragments
#   - ncross: uses output from training mode to guide verification with a
#     basic cross-validation setup 
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
. $HERE/build_configs/gsec_common

# Default command line options
VERBOSE_OUTPUT=0
MAKE_THREADS=4
USE_LSF=0
USE_PARALLEL=0
USE_LSF_THREADED=0
USE_INTERACTIVE_LSF=0
USE_GDB=0
USE_HEAP_PROFILER=0
USE_HEAP_CHECK=0
USE_HEAP_CHECK_LOCAL=0
USE_SINGLE_THREADED_KLEE=0
ROOT_DIR="`pwd`"
BC_MODE="tetrinet"
KTEST_DIR=""
XARGS_MAX_PROCS=0 # for running in parallel mode with xargs
SINGLE_KTEST_INPUT=""
KTEST_FILE_TYPE="binary" # binary or text

HMM_PREFIX="hmm_"
HMM_TRAINING_MODE="ncross"
HMM_TRAIN_FLAGS=" -f -v -m Ruzicka -t mJaccard -d exact "

# Default cliver options
CLIVER_BIN_FILE="cliver"
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

# Debug Flags
DEBUG_PRINT_EXECUTION_EVENTS=0
DEBUG_EXECUTION_TREE=0
DEBUG_ADDRESS_SPACE_GRAPH=0
DEBUG_STATE_MERGER=0
DEBUG_NETWORK_MANAGER=0
DEBUG_SOCKET=0
DEBUG_SEARCHER=0

PRINT_OBJECT_BYTES=0
EXTRA_CLIVER_OPTIONS=""
EXTRA_BITCODE_OPTIONS=""

# HMM parameters
HMM_FRAG_CLUSTER_SZ=512
HMM_MSG_CLUSTER_SZ=64

# Global Variables
CLIVER_JOBS=()

parse_ktest_filename()
{
  eval "basename $1 .ktest | awk -F_ '{ printf \$$2 }'"
}

testclientserver_parameters()
{
  # FORMAT: testclientserver_"index"_"messageCount"_"basketSize"_"encrypted{0,1}
  local index=$(parse_ktest_filename $1 2)
  local message_count=$(parse_ktest_filename $1 3)
  local basket_size=$(parse_ktest_filename $1 4)
  local encrypted=$(parse_ktest_filename $1 5)
  local bc_file_opts=""
  bc_file_opts+=" ${EXTRA_BITCODE_OPTIONS} "
  bc_file_opts+=" -m ${message_count} -b ${basket_size} -e ${encrypted} "
  printf "%s" "$bc_file_opts"
}

tetrinet_parameters()
{
  # FORMAT: $MODE"_"$i"_"$INPUT_GEN_TYPE"_"$ptype"_"$rate"_"$MAX_ROUND"_"$PLAYER_NAME"_"$SERVER_ADDRESS
  local random_seed=$(parse_ktest_filename $1 2)
  local starting_height=$(parse_ktest_filename $1 2)
  local input_gen_type=$(parse_ktest_filename $1 3)
  local partial_type=$(parse_ktest_filename $1 4)
  local partial_rate=$(parse_ktest_filename $1 5)
  local max_round=$(parse_ktest_filename $1 6)
  local player_name="$(parse_ktest_filename $1 7)"
  local server_address="$(parse_ktest_filename $1 8)"

  local bc_file_opts="-autostart "
  bc_file_opts+="-startingheight 0 "
  bc_file_opts+="-partialtype $partial_type "
  bc_file_opts+="-partialrate $partial_rate "
  bc_file_opts+="-inputgenerationtype 64 "
  bc_file_opts+="-maxround $max_round "
  bc_file_opts+="-seed $random_seed "
  bc_file_opts+=" $player_name $server_address "
  printf "%s" "$bc_file_opts"
}

xpilot_parameters()
{
  local GEOMETRY="800x600+100+100"
  local bc_file_opts=""

  bc_file_opts+=" ${EXTRA_BITCODE_OPTIONS} "
  bc_file_opts+=" -join -texturedWalls no -texturedDecor no -texturedObjects no "
  bc_file_opts+=" -fullColor no -geometry $GEOMETRY "
  bc_file_opts+=" -keyTurnLeft a -keyTurnRight d -keyThrust w localhost "

  printf "%s" "$bc_file_opts"
}

openssl_parameters()
{

  local IP="127.0.0.1"
  local PORT="4433"
  local bc_file_opts=""

  bc_file_opts+=" s_client -no_special_cmds -CAfile $OPENSSL_CERTS_DIR/TA.crt "
  bc_file_opts+=" ${EXTRA_BITCODE_OPTIONS} "

  ## Use this to add extra BC parameters from the commandline
  if test ${CLIVER_BC_PARAMS+defined}; then
    
    bc_file_opts+=" ${CLIVER_BC_PARAMS} "
  fi

  bc_file_opts+=" -connect $IP:$PORT "

  printf "%s" "$bc_file_opts"
}

bssl_parameters()
{
  local IP="127.0.0.1"
  local PORT="4433"
  local bc_file_opts=""

  bc_file_opts+=" client "
  bc_file_opts+=" ${EXTRA_BITCODE_OPTIONS} "

  ## Use this to add extra BC parameters from the commandline
  if test ${CLIVER_BC_PARAMS+defined}; then
    bc_file_opts+=" ${CLIVER_BC_PARAMS} "
  fi

  bc_file_opts+=" -connect $IP:$PORT "

  printf "%s" "$bc_file_opts"
}

initialize_bc()
{
  # Alternative to using recent link in KTEST_DIR and TRAINING_DIR
  if test ! ${DATA_TAG+defined}; then
    DATA_TAG="recent"
  fi

  case $BC_MODE in
    openssl*)
      if [ -z "$KTEST_DIR" ] ; then
        KTEST_DIR="$DATA_DIR/network/openssl/$DATA_TAG"
      fi
      OPENSSL_CERTS_DIR="$KTEST_DIR/certs"
      BC_FILE="$OPENSSL_ROOT/bin/${BC_MODE}.bc"
      TRAINING_DIR="$DATA_DIR/training/openssl-klee/$DATA_TAG"
      ;;
    bssl*)
      if [ -z "$KTEST_DIR" ] ; then
        KTEST_DIR="$DATA_DIR/network/bssl/$DATA_TAG"
      fi
      BC_FILE="$BORINGSSL_ROOT/bin/${BC_MODE}.bc"
      TRAINING_DIR="$DATA_DIR/training/bssl-klee/$DATA_TAG"
      ;;
    tetri*)
      if [ -z "$KTEST_DIR" ] ; then
        KTEST_DIR="$DATA_DIR/network/tetrinet-klee/$DATA_TAG"
      fi
      BC_FILE="$TETRINET_ROOT/bin/${BC_MODE}.bc"
      TRAINING_DIR="$DATA_DIR/klee-droppings/training/${BC_MODE}/$DATA_TAG"
      ;;
    xpilot*)
      # HACK_HOSTNAME and XPILOTHOST handle this for now...
      ## need to automatically set this var...
      #if test ! ${XPILOTHOST+defined}; then
      #  echo "set XPILOTHOST environment variable before running xpilot"
      #  exit
      #fi
      if [ -z "$KTEST_DIR" ] ; then
        KTEST_DIR="$DATA_DIR/network/xpilot-ng-x11/$DATA_TAG"
      fi
      BC_FILE="$XPILOT_ROOT/bin/${BC_MODE}.bc"
      TRAINING_DIR="$DATA_DIR/training/${BC_MODE}/$DATA_TAG"
      ;;
    testclientserver*)
      if [ -z "$KTEST_DIR" ] ; then
        KTEST_DIR="$DATA_DIR/network/testclientserver/$DATA_TAG"
      fi
      BC_FILE="$XPILOT_ROOT/bin/${BC_MODE}.bc"
      TRAINING_DIR="$DATA_DIR/training/${BC_MODE}/$DATA_TAG"
      ;;
  esac
}

bc_parameters()
{
  case $BC_MODE in
    openssl*)
      openssl_parameters $1
      ;;
    bssl*)
      bssl_parameters $1
      ;;
    tetri*)
      tetrinet_parameters $1
      ;;
    xpilot*)
      xpilot_parameters $1
      ;;
    testclientserver*)
      testclientserver_parameters $1
      ;;
  esac
}

initialize_cliver()
{
  if [ $USE_SINGLE_THREADED_KLEE -eq 1 ]; then
    CLIVER_BIN="$KLEE_ROOT/bin/klee-st -cliver "
  else
    CLIVER_BIN="$KLEE_ROOT/bin/klee -cliver "
  fi

  HMM_TRAIN_BIN="$KLEE_ROOT/bin/hmmtrain "

  if test ${SPECIAL_OUTPUT_DIR+defined}; then
    BASE_OUTPUT_DIR=$DATA_DIR/$SPECIAL_OUTPUT_DIR/$(basename $BC_FILE .bc)
  else
    BASE_OUTPUT_DIR=$DATA_DIR/$CLIVER_MODE/$(basename $BC_FILE .bc)
  fi

  CLIVER_OUTPUT_DIR=$BASE_OUTPUT_DIR/$RUN_PREFIX

  leval mkdir -p $CLIVER_OUTPUT_DIR
  leval ln -sfT $RUN_PREFIX $BASE_OUTPUT_DIR/$DATA_TAG
}

cliver_parameters()
{
  local cliver_params=""

  cliver_params+="-emit-all-errors -debug-stderr "
  cliver_params+="-optimize -disable-inlining -disable-internalize -strip-debug "
  cliver_params+="-check-div-zero=0 -check-overshift=0 "
  cliver_params+="-use-forked-solver=0 "
  #cliver_params+="-use-query-log=solver:pc "
  #cliver_params+="-suppress-external-warnings=false "
  #cliver_params+="-all-external-warnings=true "
  cliver_params+="-use-call-paths=0 "
  cliver_params+="-use-cex-cache=0 "
  cliver_params+="-use-canonicalization=1 "
  cliver_params+="-output-istats=0 "

  cliver_params+="-use-tee-buf=$USE_TEE_BUF "
  cliver_params+="-libc=$CLIVER_LIBC "
  cliver_params+="-switch-type=$SWITCH_TYPE "
  cliver_params+="-output-source=$OUTPUT_LLVM_ASSEMBLY "
  cliver_params+="-output-module=$OUTPUT_LLVM_BITCODE "

  ### XXX FIX ME XXX ###
  # This is disabled for now because klee's memory check is inefficient
  #cliver_params+="-max-memory=$MAX_MEMORY "

  if [ $PRINT_OBJECT_BYTES -eq 1 ]; then
    cliver_params+="-always-print-object-bytes " 
  fi

  if [ $DEBUG_SEARCHER -eq 1 ]; then
    cliver_params+="-debug-searcher "
  fi

  if [ $DEBUG_EXECUTION_TREE -eq 1 ]; then
    cliver_params+="-debug-execution-tree "
  fi

  if [ $DEBUG_ADDRESS_SPACE_GRAPH -eq 1 ]; then
    cliver_params+="-debug-address-space-graph " 
  fi

  if [ $DEBUG_STATE_MERGER -eq 1 ]; then
    cliver_params+="-debug-state-merger "
  fi

  if [ $DEBUG_NETWORK_MANAGER -eq 1 ]; then
    cliver_params+="-debug-network-manager "
  fi

  if [ $DEBUG_SOCKET -eq 1 ]; then
    cliver_params+="-debug-socket "
  fi

  if [ $PRINT_INSTRUCTIONS -eq 1 ]; then
    cliver_params+="-debug-print-instructions "
  fi

  if [ $DEBUG_PRINT_EXECUTION_EVENTS -eq 1 ]; then
    cliver_params+="-debug-print-execution-events "
  fi

  if [ $DISABLE_OUTPUT -eq 1 ]; then
    cliver_params+="-no-output=1 "
  fi

  cliver_params+=" $EXTRA_CLIVER_OPTIONS "

  # BC specific cliver options
  case $BC_MODE in
    xpilot*)
      cliver_params+="-posix-runtime "
      cliver_params+="-client-model=xpilot "
      cliver_params+="-load=$ROOT_DIR/$XLIB_DIR/libSM.so "
      cliver_params+="-load=$ROOT_DIR/$XLIB_DIR/libICE.so "
      cliver_params+="-load=$ROOT_DIR/$XLIB_DIR/libX11.so "
      cliver_params+="-load=$ROOT_DIR/$XLIB_DIR/libXext.so "
      cliver_params+="-load=$ROOT_DIR/$XLIB_DIR/libXxf86misc.so.1 "
      cliver_params+="-no-xwindows "
      ;;
    tetrinet*)
      cliver_params+="-posix-runtime "
      cliver_params+="-client-model=tetrinet "
      ;;
    openssl*)
      cliver_params+="-cloud9-posix-runtime "
      ;;
    bssl*)
      cliver_params+="-cloud9-posix-runtime "
      ;;
    testclientserver*)
      cliver_params+="-posix-runtime "
      ;;
  esac

  printf "%s" "$cliver_params"
}

cliver_ktest_parameters()
{
  local binary_ktest_file=$1
  if [[ $KTEST_FILE_TYPE == "binary" ]]; then
      printf "%s" "-socket-log ${binary_ktest_file} "
  else # text
      local params=""
      local binary_basename=$(basename "$binary_ktest_file")
      local parentdir=$(dirname "$binary_ktest_file")
      local txtfile="${binary_basename}.txt"
      local keyfile="${binary_basename}.key"
      params+="-socket-log-text=${parentdir}/text/${txtfile} "
      params+="-tls-master-secret-file=${parentdir}/keys/${keyfile} "
      printf "%s" "${params}"
  fi
}

run_cliver()
{
  # Save each cliver command and parameters
  local cliver_params="$@"
  CLIVER_JOBS+=( "${CLIVER_BIN} ${cliver_params}" )

  if [ $USE_LSF -eq 1 ]; then
    if [ $USE_LSF_THREADED -eq 1 ]; then
      ltbsub $CLIVER_BIN $@
    else
      lbsub $CLIVER_BIN $@
    fi
  elif [ $USE_INTERACTIVE_LSF -eq 1 ]; then
    ibsub $CLIVER_BIN $@
    #gibsub $CLIVER_BIN-bin $@
  elif [ $USE_GDB -eq 1 ]; then
    #geval $CLIVER_BIN-bin $@
    geval $CLIVER_BIN $@
    exit
  elif [ $USE_HEAP_PROFILER -eq 1 ]; then
    leval env HEAPPROFILE=$CLIVER_OUTPUT_DIR/cliver $CLIVER_BIN-bin $@
  elif [ $USE_HEAP_CHECK -eq 1 ]; then
    leval env HEAPCHECK=normal $CLIVER_BIN-bin $@
  elif [ $USE_HEAP_CHECK_LOCAL -eq 1 ]; then
    leval env HEAPCHECK=local $CLIVER_BIN-bin $@
  elif [ $USE_PARALLEL -eq 1 ]; then
    return
  else
    #leval $CLIVER_BIN-bin $@
    leval $CLIVER_BIN $@
  fi
}

do_training()
{
  lecho "==== Training Verification ===="
  for i in $KTEST_DIR/*ktest; do
    local ktest_basename=$(basename $i .ktest)
    local cliver_params="$(cliver_parameters)"
    cliver_params+=$(cliver_ktest_parameters "$i")
    cliver_params+="-output-dir $CLIVER_OUTPUT_DIR/$ktest_basename "
    cliver_params+="-copy-input-files-to-output-dir=1 "
    cliver_params+="-cliver-mode=$CLIVER_MODE "

    case $BC_MODE in
      xpilot*)
        cliver_params+="-use-recv-processing-flag "
        ;;
    esac

    cliver_params+="$BC_FILE $(bc_parameters $i) "

    ## execute cliver
    execute_time=$(elapsed_time)
    run_cliver $cliver_params
    lecho "${ktest_basename} $(elapsed_time $execute_time)"
  done
}

check_equiv_training_bc()
{
  declare -a training_dirs=( $TRAINING_DIR/* )
  local num_dirs=${#training_dirs[@]}

  indices="$(seq 0 $(($num_dirs - 1)))"

  local in_fn="input.bc"
  local opt_fn="final.bc"

  # Check that we trained on the same bc file used for verification
  for i in $indices; do
    local dir_i="${training_dirs[$i]}" 

    if ! cmp $dir_i/$in_fn $BC_FILE > /dev/null; then
      echo "Warning: $BC_FILE has changed since training"
    fi 

    for j in $indices; do

      local dir_j="${training_dirs[$j]}" 

      if ! cmp $dir_i/$in_fn $dir_j/$in_fn > /dev/null; then
        echo "Error: $dir_i/$in_fn and $dir_j/$in_fn differ."
        exit 1
      fi 
      if ! cmp $dir_i/$opt_fn $dir_j/$opt_fn > /dev/null; then
        echo "Error: $dir_i/$opt_fn and $dir_j/$opt_fn differ."
        exit 1
      fi 

    done
  done
}

do_verification()
{
  lecho "==== Naive Verification ===="
  for i in $KTEST_DIR/*ktest; do
    local ktest_basename=$(basename $i .ktest)
    local cliver_params="$(cliver_parameters)"

    if [ -n "$SINGLE_KTEST_INPUT" ]; then
      if [ $SINGLE_KTEST_INPUT != ${ktest_basename} ]; then
        continue;
      fi
    fi

    cliver_params+=$(cliver_ktest_parameters "$i")
    cliver_params+="-output-dir $CLIVER_OUTPUT_DIR/$ktest_basename "
    cliver_params+="-cliver-mode=$CLIVER_MODE "

    cliver_params+="$BC_FILE $(bc_parameters $i) "

    ## execute cliver
    execute_time=$(elapsed_time)
    run_cliver $cliver_params
    lecho "${ktest_basename} $(elapsed_time $execute_time)"
  done
}

do_ncross_verification()
{
  if [[ $(expr match $CLIVER_MODE "self") -gt 0 ]]; then
    NCROSS_MODE="self"
    CLIVER_MODE=${CLIVER_MODE#"self-"}
  elif [[ $(expr match $CLIVER_MODE "check") -gt 0 ]]; then
    NCROSS_MODE="check"
    CLIVER_MODE=${CLIVER_MODE#"check-"}
  elif [[ $(expr match $CLIVER_MODE "ncross") -gt 0 ]]; then
    NCROSS_MODE="ncross"
    CLIVER_MODE=${CLIVER_MODE#"ncross-"}
  elif [[ $(expr match $CLIVER_MODE "all") -gt 0 ]]; then
    NCROSS_MODE="all"
    CLIVER_MODE=${CLIVER_MODE#"all-"}
  else
    echo "Error: invalid mode $CLIVER_MODE"
    exit 1
  fi

  lecho "==== Cluster/Edit Distance Verification ${NCROSS_MODE} ${CLIVER_MODE} ===="

  declare -a training_dirs=( $TRAINING_DIR/* )

  # remove any subdirectories that are hmm data
  local training_dirs=(${training_dirs[@]//*${HMM_PREFIX}*})

  local num_dirs=${#training_dirs[@]}

  indices="$(seq 0 $(($num_dirs - 1)))"

  # Check that we trained on the same bc file used for verification
  #check_equiv_training_bc

  for i in $indices; do

    local ktest_file="${training_dirs[$i]}/socket_000.ktest"
    local ktest_basename=$(basename ${training_dirs[$i]})
    local cliver_params="$(cliver_parameters) "

    if [ -n "$SINGLE_KTEST_INPUT" ]; then
      if [ $SINGLE_KTEST_INPUT != ${ktest_basename} ]; then
        continue;
      fi
    fi

    cliver_params+=$(cliver_ktest_parameters "$ktest_file")
    cliver_params+="-output-dir $CLIVER_OUTPUT_DIR/$ktest_basename "
    cliver_params+="-cliver-mode=$CLIVER_MODE "

    #if [[ $NCROSS_MODE == "self" ]] ; then
    #  cliver_params+="-use-self-training "
    #else
      cliver_params+="-use-clustering "
    #fi

    case $BC_MODE in
      xpilot*)
        cliver_params+="-use-recv-processing-flag "
        ;;
    esac

    for k in $indices; do
      if [[ $NCROSS_MODE == "ncross" ]] ; then
        if [ $i != $k ]; then
          cliver_params+=" -training-path-dir=${training_dirs[$k]}/ "
        fi 
        # enable to support self-training checks during verificiation
        if [ $i == $k ]; then
          cliver_params+=" -self-training-path-dir=${training_dirs[$k]}/ "
        fi
      elif [[ $NCROSS_MODE == "self" ]] ; then
        if [ $i == $k ]; then
          cliver_params+=" -training-path-dir=${training_dirs[$k]}/ "
          #cliver_params+=" -self-training-path-dir=${training_dirs[$k]}/ "
        fi 
      elif [[ $NCROSS_MODE == "check" ]] ; then
        if [ $i != $k ]; then
          cliver_params+=" -training-path-dir=${training_dirs[$k]}/ "
        fi 
        if [ $i == $k ]; then
          cliver_params+=" -self-training-path-dir=${training_dirs[$k]}/ "
        fi 
      elif [[ $NCROSS_MODE == "all" ]] ; then
        cliver_params+=" -training-path-dir=${training_dirs[$k]}/ "
      fi
    done

    cliver_params+="$BC_FILE $(bc_parameters $ktest_basename.ktest) "

    ## execute cliver
    execute_time=$(elapsed_time)
    run_cliver $cliver_params
    lecho "${ktest_basename} $(elapsed_time $execute_time)"
  done
}

do_training_verification()
{

  if [[ $(expr match $CLIVER_MODE "verify") -gt 0 ]]; then
    VERIFY_MODE="verify"
    CLIVER_MODE=${CLIVER_MODE#"verify-"}
  else
    echo "Error: invalid mode $CLIVER_MODE"
    exit 1
  fi

  declare -a training_dirs=( $TRAINING_DIR/* )

  # remove any subdirectories that are hmm data
  local training_dirs=(${training_dirs[@]//*${HMM_PREFIX}*})

  local num_dirs=${#training_dirs[@]}
  indices="$(seq 0 $(($num_dirs - 1)))"

  declare -a ktest_files=( $KTEST_DIR/*.ktest )
  local ktest_num_dirs=${#ktest_files[@]}
  ktest_indices="$(seq 0 $(($ktest_num_dirs - 1)))"


  # Check that we trained on the same bc file used for verification
  for i in $indices; do
    local training_bc_file="${training_dirs[$i]}/input.bc" 
    if ! cmp $training_bc_file $BC_FILE > /dev/null; then
      echo "Error: $training_bc_file and $BC_FILE differ."
      exit 1
    fi 
  done

  for i in $ktest_indices; do
    local ktest_file="${ktest_files[$i]}"
    local ktest_basename=$(basename ${ktest_files[$i]})
    
    local cliver_params="$(cliver_parameters) "

    cliver_params+=$(cliver_ktest_parameters "$ktest_file")
    cliver_params+="-output-dir $CLIVER_OUTPUT_DIR/$ktest_basename "
    cliver_params+="-cliver-mode=$CLIVER_MODE "


    for k in $indices; do
      cliver_params+=" -training-path-dir=${training_dirs[$k]}/ "
    done

    cliver_params+="$BC_FILE $(bc_parameters $ktest_basename.ktest) "

    ## execute cliver
    execute_time=$(elapsed_time)
    run_cliver $cliver_params
    lecho "${ktest_basename} $(elapsed_time $execute_time)"
  done
}

do_hmm_training()
{
  # training types: all tpath files, n-cross (n=1), self

  lecho "==== HMM Training: $HMM_TRAINING_MODE ===="

  # Read all subdirectories in the training dir
  declare -a training_dirs=( $TRAINING_DIR/* )

  # remove any subdirectories that are old hmm data
  local training_dirs=(${training_dirs[@]//*${HMM_PREFIX}*})
  local num_dirs=${#training_dirs[@]}
  indices="$(seq 0 $(($num_dirs - 1)))"

  # Check that we trained on the same bc file used for verification
  #check_equiv_training_bc

  # Iterate through each training set (only once for "all" mode)
  for i in $indices; do

    # session index is either "all" or the training set index
    local session=$(basename ${training_dirs[$i]})
    local session_index=${session##*[[:punct:]|[:alpha:]]}
    local session_prefix=${session:0:$((${#session}-${#session_index}))}

    if [[ ${HMM_TRAINING_MODE} == "self" ]] ; then
      session_index="self_"${session##*[[:punct:]|[:alpha:]]}
    elif [[ ${HMM_TRAINING_MODE} == "all" ]] ; then
      session_index="all"
    fi

    lecho "${HMM_PREFIX}${session_index}"

    local hmm_dir="${TRAINING_DIR}/${HMM_PREFIX}${session_index}"
    local tpath_list_file="${hmm_dir}/input_list.txt"
    local hmm_file="${hmm_dir}/hmm.txt"
    leval mkdir -p ${hmm_dir}


    ### make training file
    for k in $indices; do
      if [[ ${HMM_TRAINING_MODE} == "ncross" ]] ; then
        if [ $i != $k ]; then
          find -L "${training_dirs[$k]}" -name '*.tpath' >> ${tpath_list_file}
        fi
      elif [[ ${HMM_TRAINING_MODE} == "self" ]] ; then
        if [ $i == $k ]; then
          find -L "${training_dirs[$k]}" -name '*.tpath' >> ${tpath_list_file}
        fi
      elif [[ ${HMM_TRAINING_MODE} == "all" ]] ; then
        find -L "${training_dirs[$k]}" -name '*.tpath' >> ${tpath_list_file}
      fi
    done

    ## drop xpilot headers
    hmm_xpilot_flag=
    case $BC_MODE in
      xpilot*)
        hmm_xpilot_flag=-x
        ;;
    esac

    ## execute hmm training
    leval ${HMM_TRAIN_BIN} ${HMM_TRAIN_FLAGS} ${hmm_xpilot_flag}  \
      ${tpath_list_file} ${session_prefix} ${HMM_FRAG_CLUSTER_SZ} \
      ${HMM_MSG_CLUSTER_SZ} ${hmm_dir} ${hmm_file}

    if [[ ${HMM_TRAINING_MODE} == "all" ]] ; then
      break;
    fi

  done
}

do_hmm_verification()
{
  CLIVER_MODE=${CLIVER_MODE#"hmm-"}

  if [[ $(expr match $CLIVER_MODE "self") -gt 0 ]]; then
    NCROSS_MODE="self"
    CLIVER_MODE=${CLIVER_MODE#"self-"}
  elif [[ $(expr match $CLIVER_MODE "check") -gt 0 ]]; then
    NCROSS_MODE="check"
    CLIVER_MODE=${CLIVER_MODE#"check-"}
  elif [[ $(expr match $CLIVER_MODE "ncross") -gt 0 ]]; then
    NCROSS_MODE="ncross"
    CLIVER_MODE=${CLIVER_MODE#"ncross-"}
  elif [[ $(expr match $CLIVER_MODE "all") -gt 0 ]]; then
    NCROSS_MODE="all"
    CLIVER_MODE=${CLIVER_MODE#"all-"}
  else
    echo "Error: invalid mode $CLIVER_MODE"
    exit 1
  fi

  lecho "==== HMM Verification ${NCROSS_MODE} ${CLIVER_MODE} ===="

  declare -a training_dirs=( $TRAINING_DIR/* )

  # remove any subdirectories that are hmm data
  local training_dirs=(${training_dirs[@]//*${HMM_PREFIX}*})

  local num_dirs=${#training_dirs[@]}

  indices="$(seq 0 $(($num_dirs - 1)))"

  # Check that we trained on the same bc file used for verification
  #check_equiv_training_bc

  for i in $indices; do

    local session=$(basename ${training_dirs[$i]})

    # session index is either "all" or the training set index
    local session_index=${session##*[[:punct:]|[:alpha:]]}
    local hmm_index=${session##*[[:punct:]|[:alpha:]]}

    ## get session prefix (e.g., "xpilot_"
    local session_prefix=${session:0:$((${#session}-${#session_index}))}

    if [[ ${NCROSS_MODE} == "self" ]] ; then
      hmm_index="self_"${session##*[[:punct:]|[:alpha:]]}
    elif [[ ${NCROSS_MODE} == "all" ]] ; then
      hmm_index="all"
    fi

    local hmm_dir="${TRAINING_DIR}/${HMM_PREFIX}${hmm_index}"
    local hmm_file="${hmm_dir}/hmm.txt"

    local ktest_file="${training_dirs[$i]}/socket_000.ktest"
    local ktest_basename=$(basename ${training_dirs[$i]})
    local cliver_params="$(cliver_parameters) "

    cliver_params+=$(cliver_ktest_parameters "$ktest_file")
    cliver_params+="-output-dir $CLIVER_OUTPUT_DIR/$ktest_basename "
    cliver_params+="-cliver-mode=$CLIVER_MODE "
    cliver_params+="-use-hmm "

    case $BC_MODE in
      xpilot*)
        cliver_params+="-use-recv-processing-flag "
        ;;
    esac

    ## add training file path to parameters
    cliver_params+="-hmm-training-file=${hmm_file} "

    ## add bc file to parameters
    cliver_params+="$BC_FILE $(bc_parameters $ktest_basename.ktest) "

    ## execute cliver
    execute_time=$(elapsed_time)
    run_cliver $cliver_params
    lecho "${ktest_basename} ${hmm_file} $(elapsed_time $execute_time)"

  done
}

###############################################################################

on_exit()
{
  if [ $ERROR_EXIT -eq 1 ]; then
    lecho "Elapsed time: $(elapsed_time $start_time)"
    lecho "Error"
  fi
  if [ $ERROR_EXIT -eq 0 ]; then
    lecho "Elapsed time: $(elapsed_time $start_time)"
  fi
  exit $ERROR_EXIT
}

###############################################################################

usage()
{
  echo -e "$0\n\nUSAGE:"
  echo -e "\t-t [verify|training|ncross]\t\t(type of verification)(REQUIRED)" 
  echo -e "\t-c [xpilot|tetrinet|openssl|bssl]\t\t(client binary)(REQUIRED)"
  echo -e "\t-i [gdb|lsf|interactive]\t\t(run mode)"
  echo -e "\t-b [\"\"]\t\t\t\t\t(name of ktest dir in data/network/[client-type]/ dir)"
  echo -e "\t-k [\"\"]\t\t\t\t\t(full path to ktest directory)"
  echo -e "\t-x [\"\"]\t\t\t\t\t(additional cliver options)"
  echo -e "\t-l [\"\"]\t\t\t\t\t(additional cLient binary options)"
  echo -e "\t-d [0|1|2]\t\t\t\t(debug level)"
  echo -e "\t-m [gigabytes]\t\t\t\t(maximum memory usage)"
  echo -e "\t-p [heapprofile|heaplocal|heapcheck]\t(memory profiling options)"
  echo -e "\t-r [dir]\t\t\t\t(alternative root directory)"
  echo -e "\t-T \t\t\t\t\t(KTestText: use text/*.ktest.txt & keys/*.ktest.key)"
  echo -e "\t-e \t\t\t\t\t(extra build config file: supplements gsec_common)"
  echo -e "\t-n \t\t\t\t\t(dry run)"
  echo -e "\t-s \t\t\t\t\t(silent)"
  echo -e "\t-h \t\t\t\t\t(help/usage)"
}

###############################################################################

run_parallel_jobs()
{
  if [ $USE_PARALLEL -eq 1 ]; then
    num_jobs=${#CLIVER_JOBS[@]}

    lecho "Executing ${num_jobs} jobs in parallel"

    # Execute all the cliver jobs in parallel using xargs
    for (( i=0; i<${num_jobs}; ++i)) ;
    do
      echo "${CLIVER_JOBS[$i]} > ${PARALLEL_LOG_DIR}/${i}.log 2>&1" ;
    done | ## execute in parallel with xargs
      ( xargs -I{} --max-procs ${XARGS_MAX_PROCS} bash -c '{ {}; }' )
  fi
}

###############################################################################

main() 
{
  while getopts "b:k:t:o:c:e:x:i:j:l:p:d:r:m:y:nshvfT" opt; do
    case $opt in
      b)
        DATA_TAG="$OPTARG"
        ;;

      e) # variables supplementing or overriding gsec_common
        EXTRA_BUILD_CONFIG=$OPTARG
        source ${EXTRA_BUILD_CONFIG}
        ;;

      k)
        KTEST_DIR="$OPTARG"
        ;;

      f)
        USE_TEE_BUF=0
        EXTRA_CLIVER_OPTIONS+=" -minimal-output "
        CLIVER_BIN_FILE="cliver-opt"
        ;;

      t)
        CLIVER_MODE="$OPTARG"
        ;;

      o)
        SPECIAL_OUTPUT_DIR="$OPTARG"
        ;;

      c)
        BC_MODE="$OPTARG"
        ;;

      x)
        EXTRA_CLIVER_OPTIONS+="$OPTARG"
        ## check for --use-threads=1
        #if [[ ${EXTRA_CLIVER_OPTIONS} =~ use-threads=1[^[:digit:]]+ ]]; then
        #  lecho "using single threaded KLEE (klee-st)"
        #  USE_SINGLE_THREADED_KLEE=1
        #fi
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
          parallel*)
            USE_PARALLEL=1
            VERBOSE_OUTPUT=0
            ;;
          threaded-lsf*)
            USE_LSF=1
            USE_LSF_THREADED=1
            VERBOSE_OUTPUT=0
            ;;
        esac
        ;;

      j)
        XARGS_MAX_PROCS=$OPTARG
        ;;

      l)
        EXTRA_BITCODE_OPTIONS+="$OPTARG"
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
          DEBUG_EXECUTION_TREE=1
        fi
        if [[ $OPTARG -ge 1 ]]; then
          DEBUG_STATE_MERGER=1
          DEBUG_ADDRESS_SPACE_GRAPH=1
          DEBUG_SOCKET=1
        fi
        if [[ $OPTARG -ge 2 ]]; then
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

      y)
        # only run experiments on a single ktest file (subset of input)
        SINGLE_KTEST_INPUT="$OPTARG"
        ;;

      v)
        VERBOSE_OUTPUT=1
        ;;

      s)
        USE_SINGLE_THREADED_KLEE=1
        ;;

      T)
        KTEST_FILE_TYPE="text" # default is "binary"
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

  #echo "[cliver mode: $CLIVER_MODE]"
  #echo "Params: $@"

  initialize_root_directories
  initialize_logging $@
  initialize_bc

  # check ktest files exist
  local ktest_count=$(find ${KTEST_DIR} -follow -maxdepth 1 -name "*.ktest" 2>/dev/null | wc -l)
  if [ "${ktest_count}" -eq "0" ]; then
    echo "${PROG}: ${KTEST_DIR} contains no ktest files"; exit
  else
    lecho "Using ${ktest_count} ktest files from ${KTEST_DIR}"
  fi

  initialize_cliver

  if [ $USE_LSF -eq 1 ]; then
    initialize_lsf
  fi

  if [ ${USE_SINGLE_THREADED_KLEE} -eq 1 ]; then
    if [[ ${EXTRA_CLIVER_OPTIONS} =~ use-threads=[^1] ]]; then
      echo "invalid thread count for single threaded mode (-s)"; exit
    fi
    if [[ ${EXTRA_CLIVER_OPTIONS} =~ use-threads=1[[:digit:]]+ ]]; then
      lecho "invalid thread count for single threaded mode (-s)"; exit
    fi
  fi

  if [ $USE_PARALLEL -eq 1 ]; then
    initialize_parallel
  fi

  # record start time
  start_time=$(elapsed_time)

  case $CLIVER_MODE in

    self* )
      do_ncross_verification
      run_parallel_jobs
      ;;

    check* )
      do_ncross_verification
      run_parallel_jobs
      ;;

    all* )
      do_ncross_verification
      run_parallel_jobs
      ;;

    ncross* )
      do_ncross_verification
      run_parallel_jobs
      ;;

    hmm* )
      do_hmm_verification
      run_parallel_jobs
      ;;

    verify* )
      do_training_verification
      run_parallel_jobs
      ;;

    training )
      # set up training jobs
      do_training
      # run to generate tpath files
      run_parallel_jobs
      ## run hmmtrain on generated tpath files
      #HMM_TRAINING_MODE="all"
      #do_hmm_training
      #HMM_TRAINING_MODE="self"
      #do_hmm_training
      #HMM_TRAINING_MODE="ncross"
      #do_hmm_training
      ;;

    edit*)
      do_verification
      run_parallel_jobs
      ;;

    naive*)
      do_verification
      run_parallel_jobs
      ;;

  esac

  if [ $USE_LSF -eq 0 ]; then
    lecho "${PROG}: elapsed time: $(elapsed_time $start_time)"
  fi
}

# set up exit handler
trap on_exit EXIT

# record start time
start_time=$(elapsed_time)

# Run main
main "$@"
ERROR_EXIT=0
