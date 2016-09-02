#!/bin/bash

###############################################################################
### experiments.sh : Run Training or Verification experiments
#
# Terminology and Design Rationale
#
# This Andrew Chi's interpretation of Robby Cochran's experiment
# scripts, attempting to capture (or reverse engineer) the design
# rationale :-)
#
# Typical usage:
# $ ./gsec-support/experiments.sh -c gsec-support/buildbot/experiments_config
#
# At a high level, we run N experiments against each of M clients, for
# a total of (N * M) sets of results.
#
# Experiment - Each "experiment" represents a build/configuration of
# *KLEE* (not the client to be verified). For example, running KLEE in
# release mode with 16 threads, native AES optimizations, and dropS2C.
# Note that those last two features are (unfortunately) built into the
# KLEE source code and are enabled as KLEE options, even though they
# are specific to the OpenSSL client.  But since they are KLEE
# options, they are associated with the experiment, not the client.
#
# Client - Each "client" comprises an ordered pair of the form
# (program/args, network data).  The "network data" (ktest files) are
# behaviorally verified against the "program/args" (LLVM bitcode and
# its comand-line arguments).  For example, we could verify 21 Gmail
# network traces against an OpenSSL s_client configured to offer only
# a particular AES-GCM ciphersuite.  Another example would be
# verifying a single Heartbleed attack network trace against an
# OpenSSL s_client configured to complete the handshake, send a single
# Heartbeat, and exit.
#
# There is some subtlety here.  In some cases, an experiment's
# particular configuration needs to touch the (bitcode) client's
# command line arguments. For example, to designate the maximum amount
# of simulated padding for putative TLS 1.3, the variable
# EXPERIMENT_LIST_BITCODE_PARAMETERS can contain the option
# "--fake-padding 128", which is inserted as a bitcode argument.
# Conversely, sometimes the client's particular configuration needs to
# touch the verifier's (KLEE) command line arguments.  For example, to
# designate that the Heartbleed attack network trace is expected to
# fail verification, the variable CLIENT_LIST_PARAMETERS can contain
# "--legitimate-socket-log=false", which is inserted as a KLEE
# argument.
#
# The command line parameters to KLEE and the client (whether openssl,
# tetrinet, or xpilot) are NOT fully determined by this script and the
# experiments_config file.  Many of the default options for both KLEE
# and the particular clients are hard-coded into the cliver.sh script,
# which is invoked by this experiments.sh script (N * M) times, each
# time adding different *additional* command line arguments
# corresponding to the particular experiment and the particular
# client.  Think of the cliver.sh script as hard-coding the base
# command line arguments for KLEE and the three client programs; the
# experiments.sh script varies and adds any additional options as
# appropriate for each particular experiment.
###############################################################################

# see http://www.davidpashley.com/articles/writing-robust-shell-scripts.html
set -u # Exit if uninitialized value is used 
set -e # Exit on non-true value
set -o pipefail # exit on fail of any command in a pipe

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ERROR_EXIT=1
PROG=$(basename $0)

# gsec_common required variables
ROOT_DIR="`pwd`"
VERBOSE_OUTPUT=0

# Include gsec_common
. $HERE/gsec_common


###############################################################################
# Global Variables
###############################################################################

EXP_CONFIG="" # experiment config file 
CLIVERSH="./gsec-support/cliver.sh"
PLOTS_ONLY=0

###############################################################################
# Variables that can be defined in config file
# NB: *_LIST variables with equiv prefix must be the same length

EXPERIMENT_LIST=()
EXPERIMENT_LIST_NAMES=()
EXPERIMENT_LIST_PARAMETERS=()

CLIVER_PARAMETERS=""

CLIENT_LIST=()
CLIENT_LIST_KTEST=()
CLIENT_LIST_PARAMETERS=()

RESULTS_LOCATION=""

###############################################################################

on_exit()
{
  if [ $ERROR_EXIT -eq 1 ]; then
    lecho "Error"
  fi
  if [ $ERROR_EXIT -eq 0 ]; then
    lecho "Elapsed time: $(elapsed_time $start_time)"
  fi
  exit $ERROR_EXIT
}

###############################################################################

run_experiments()
{
  lecho "Running Cliver Experiments"

  num_clients=${#CLIENT_LIST[@]}
  num_experiments=${#EXPERIMENT_LIST[@]}

  for (( i=0; i<${num_experiments}; ++i ));
  do

    expType=${EXPERIMENT_LIST[$i]}
    expOutput=${EXPERIMENT_LIST_NAMES[$i]}
    exp_params=${EXPERIMENT_LIST_PARAMETERS[$i]}

    if [ -n "${EXPERIMENT_LIST_CLIVER_PARAMETERS[$i]}" ]; then
      exp_cliver_params=${EXPERIMENT_LIST_CLIVER_PARAMETERS[$i]}
    else
      exp_cliver_params=" "
    fi
    if [ -n "${EXPERIMENT_LIST_BITCODE_PARAMETERS[$i]}" ]; then
      exp_bitcode_params=${EXPERIMENT_LIST_BITCODE_PARAMETERS[$i]}
    else
      exp_bitcode_params=" "
    fi

    for (( j=0; j<${num_clients}; ++j ));
    do
      client=${CLIENT_LIST[$j]}
      data_tag=$(basename ${CLIENT_LIST_KTEST[$j]})

      ktest_dir=${CLIENT_LIST_KTEST[$j]}

      bitcode_params=
      if [ -n "${CLIENT_LIST_BITCODE_PARAMETERS[$j]}" ]; then
        bitcode_params="-l \"${CLIENT_LIST_BITCODE_PARAMETERS[$j]} $exp_bitcode_params \""
      fi

      client_params=${CLIENT_LIST_PARAMETERS[$j]}
      extra_params=" -x \"${client_params} ${exp_params}\" "
      
      cliver_command="${CLIVERSH} -t $expType -c $client -b $data_tag -k $ktest_dir -o $expOutput $exp_cliver_params ${CLIVER_PARAMETERS} ${bitcode_params} $extra_params "
      lecho "EXEC: ${cliver_command}"
      eval ${cliver_command}
    done
  done
}

###############################################################################

copy_results()
{
  lecho "Copying Cliver Output"

  num_clients=${#CLIENT_LIST[@]}
  num_experiments=${#EXPERIMENT_LIST[@]}

  for (( i=0; i<${num_experiments}; ++i ));
  do

    expType=${EXPERIMENT_LIST[$i]}
    expOutput=${EXPERIMENT_LIST_NAMES[$i]}

    for (( j=0; j<${num_clients}; ++j ));
    do
      client=${CLIENT_LIST[$j]}

      # Directory that holds output of all cliver.sh experiments
      # with this expOutput and client name pair (i.e., data/naive/openssl)
      client_data_path=${DATA_DIR}/${expOutput}/${client}

      # the symlink created by cliver.sh is set to $data_tag
      data_tag=$(basename ${CLIENT_LIST_KTEST[$j]})

      # the symlink created by cliver.sh will point to dir named $data_id
      data_id=$(readlink ${client_data_path}/${data_tag})

      # stats directory will all of the experiment data (past and present)
      stats_dir=${RESULTS_LOCATION}/$client/data/${data_tag}/$expOutput/$data_id
      leval mkdir -p ${stats_dir}

      pattern="cliver.stats"
      for file in $( find -L ${client_data_path}/${data_id} -name $pattern); do
        stats_file="$(basename $(dirname $file) ).csv"
        lecho "Stats: Lines: $(wc -l $file)"
        leval cp ${file} ${stats_dir}/${stats_file}
      done
    done
  done
}

###############################################################################

do_plots()
{
  lecho "Plotting Cliver Data"
  num_clients=${#CLIENT_LIST[@]}

  for (( j=0; j<${num_clients}; ++j ));
  do
    local client=${CLIENT_LIST[$j]}

    # the symlink created by cliver.sh is set to $data_tag
    local data_tag=$(basename ${CLIENT_LIST_KTEST[$j]})

    leval ./gsec-support/make_graphs.r $RESULTS_LOCATION/$client ${data_tag} ${CLIENT_LIST_R_BIN_WIDTH[$j]} ${EXPERIMENT_LIST_NAMES[@]}
  done
}

###############################################################################

generate_plot_pdf()
{
  lecho "Generating PDF"
  num_clients=${#CLIENT_LIST[@]}

  for (( j=0; j<${num_clients}; ++j ));
  do
    # the symlink created by cliver.sh is set to $data_tag
    local data_tag=$(basename ${CLIENT_LIST_KTEST[$j]})

    local client=${CLIENT_LIST[$j]}
    RECENT_FULL_PATH=$(find ${RESULTS_LOCATION}/${client}/plots/${data_tag}/* -type d -prune -exec ls -d {} \; | tail -1)
    RECENT=$(basename ${RECENT_FULL_PATH})
    PLOT_DIR=${RESULTS_LOCATION}/${client}/plots/${data_tag}/${RECENT}
    leval ./gsec-support/make_plot_pdf.sh ${PLOT_DIR}
  done
}

###############################################################################

generate_plot_html()
{
  lecho "Generating HTML"
  num_clients=${#CLIENT_LIST[@]}

  for (( j=0; j<${num_clients}; ++j ));
  do
    # the symlink created by cliver.sh is set to $data_tag
    local data_tag=$(basename ${CLIENT_LIST_KTEST[$j]})

    client=${CLIENT_LIST[$j]}
    RECENT_FULL_PATH=$(find ${RESULTS_LOCATION}/${client}/plots/${data_tag}/* -type d -prune -exec ls -d {} \; | tail -1)
    RECENT=$(basename ${RECENT_FULL_PATH})

    PLOT_DIR=${RESULTS_LOCATION}/${client}/plots/${data_tag}/${RECENT}
    HTML_DIR=${RESULTS_LOCATION}/${client}/plots/${data_tag}/
    htmlfile=${HTML_DIR}/$RECENT.html
    jquery="http://ajax.googleapis.com/ajax/libs/jquery/1/jquery.js"
    jsdir="http://cs.unc.edu/~rac/js/galleria"

    echo "<html><head><title>Cliver Plots: $RECENT</title>" > $htmlfile
    echo "<script src=\"${jquery}\"></script>" >> $htmlfile
    echo "<script src=\"${jsdir}/galleria.js\"></script>" >> $htmlfile
    echo "<script src=\"${jsdir}/config.js\"></script>" >> $htmlfile
    echo "</head><body><div class=\"galleria\">" >> $htmlfile
    for fullPathPlot in ${PLOT_DIR}/*
    do
      local plot=$(basename $fullPathPlot)
      echo "<img src=\"./$RECENT/$plot\" data-title=\"$plot\">" >> $htmlfile
    done
    echo "</div></body></html>" >> $htmlfile
  done
}

###############################################################################

load_config()
{
  lecho "Loading Experiment Config File: ${EXP_CONFIG}"

  # source the configuration file
  source ${EXP_CONFIG}

  num_experiments=${#EXPERIMENT_LIST[@]}
  expListOutputLen=${#EXPERIMENT_LIST_NAMES[@]}
  exp_extra_params_len=${#EXPERIMENT_LIST_PARAMETERS[@]}

  # check that the exp config arrays are of equal length
  if [ "$num_experiments" -ne "$expListOutputLen" ]; then
    echo "${PROG}: EXPERIMENT_LIST* vars not equal lengths"
    exit
  fi

  if [ "$num_experiments" -ne "$exp_extra_params_len" ]; then
    echo "${PROG}: EXPERIMENT_LIST* vars not equal lengths"
    exit
  fi

  num_clients=${#CLIENT_LIST[@]}
  clientListKtestLen=${#CLIENT_LIST_KTEST[@]}
  client_extra_params_len=${#CLIENT_LIST_PARAMETERS[@]}
  client_bitcode_params_len=${#CLIENT_LIST_BITCODE_PARAMETERS[@]}

  # check that the client config arrays are of equal length
  if [ "$num_clients" -ne "$clientListKtestLen" ] ||
     [ "$num_clients" -ne "$client_extra_params_len" ] ||
     [ "$num_clients" -ne "$client_bitcode_params_len" ]; then
    echo "${PROG}: CLIENT_LIST* vars not equal lengths"
    exit
  fi

  lecho "Clients: ${CLIENT_LIST[@]}"
  lecho "Experiments: ${EXPERIMENT_LIST_NAMES[@]}"

  # KTest config checks
  for (( j=0; j<${num_clients}; ++j ));
  do
    client=${CLIENT_LIST[$j]}
    client_ktest=${CLIENT_LIST_KTEST[$j]}
    # check that ktest dir exists
    if ! [ -e ${client_ktest} ]; then
      echo "${PROG}: ${client_ktest} doesn't exist or isn't readable"; exit
    fi

    # check that ktest dir contains ktest files
    ktest_count=$(find ${client_ktest} -follow -maxdepth 1 -name "*.ktest" | wc -l)
    if [ "${ktest_count}" -eq "0" ]; then
      echo "${PROG}: ${client_ktest} contains no ktest files"; exit
    else
      lecho "Using ${ktest_count} ktest files from ${client_ktest}"
    fi
  done

}

###############################################################################

main() 
{
  while getopts "c:vp" opt; do
    case $opt in
      c)
        EXP_CONFIG=$OPTARG
        ;;
      v)
        VERBOSE_OUTPUT=1
        ;;
      p)
        lecho "Only Generating Plots"
        PLOTS_ONLY=1
        ;;
      :)
        echo "Option -$OPTARG requires an argument"
        exit
        ;;
    esac
  done

  initialize_root_directories
  initialize_logging $@

  # source "config" file and sanity check array lengths
  load_config

  # do the experiments specified in the config file
  if [ ${PLOTS_ONLY} -eq "0" ]; then
    run_experiments
  fi

  # copy the results to location specified in config file
  copy_results

  # create plots with R
  do_plots

  # create simple html for viewing plots
  generate_plot_html

  # create simple pdf for viewing plots
  #generate_plot_pdf
}

# set up exit handler
trap on_exit EXIT

# record start time
start_time=$(elapsed_time)

# Run main
main "$@"
ERROR_EXIT=0

