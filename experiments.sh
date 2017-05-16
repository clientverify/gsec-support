#!/bin/bash

###############################################################################
### experiments.sh : Run Training or Verification experiments
###############################################################################

# ---------------------------------------------------------------------------
# Terminology and Design Rationale
# ---------------------------------------------------------------------------
#
# This Andrew Chi's interpretation of Robby Cochran's experiment
# scripts, attempting to capture the design rationale. *Please* keep
# this documentation up to date, as it will provide any future readers
# with an entry point into our labyrinthine experimental setup.
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
#
# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
#
# This experiments script produces three kinds of output.
#
# 1. [logs] screen scraping done by the bash scripts
# 2. [klee-droppings] KLEE statistics, KLEE logs, LLVM disassembly (optional)
# 3. [results] processed results and plots generated by R scripts
#
# Each kind of output follows a different directory hierarchy plan, as
# described below.
#
# [logs]
# ------
#
# Path template: ${ROOT_DIR}/data/logs/${PROGNAME}_${DATETIME}.log
#
# The three scripts update.sh, experiments.sh, and cliver.sh each
# leave their own log files, named ${PROGNAME}_${DATETIME}.log.  Since
# experiments.sh calls cliver.sh, each run of experiments.sh creates
# one experiments log file but potentially many cliver log file. These
# log files contain the executed command line and can also capture
# stdout (and maybe stderr?) from child processes like klee.  A
# symlink of the form ${PROGNAME}_recent.log is provided for
# convenience.  The one exception to this is that cliver.sh can be run
# with the option '-i parallel', which enables multiple instances of
# KLEE to run simultaneously (e.g., 21 Gmail traces), each of which
# requires its own log file.  In this case, a *subdirectory* named
# cliver_parallel_${DATETIME} holds several log files (0.log, 1.log,
# 2.log,...), one for each instance of KLEE.  For convenience, a
# symlink "cliver_parallel_recent" points to the latest such
# subdirectory.
#
# [klee-droppings]
# ----------------
#
# Path template:
#
#   ${ROOT_DIR}/data/klee-droppings/${EXPERIMENT}/${CLIENT}/${DATE=DATATAG}
#
# The KLEE droppings tree is a collection of all of the directories
# that are usually named "klee-out-##" that are emitted by an
# invocation of KLEE.  Each innermost directory contains cliver.stats,
# run.stats, debut.txt, etc.  Note that the klee-droppings hierarchy
# takes the same form regardless of whether cliver.sh was run in the
# default sequential mode or with "-i parallel".
#
# The KLEE droppings are sorted into directory hierarchy first by
# experiment name, then by client program, and then by the network
# data.  For example,
#
#   IDDFS-nAES-1-opt/openssl-klee/ktest-timefix/gmail_spdy_stream00/
#
# In this example, "IDDFS-nAES-1-opt" refers to the KLEE
# configuration: "iterative-deepening depth first search, native-AES
# optimization, 1 thread, compilation optimized for single-threaded
# use". The next part of the path, "openssl-klee", refers to the
# client: OpenSSL s_client compiled to be run in KLEE.  The next part
# of the path, "ktest-timefix", is the data tag and refers to the
# network data that is being verified. The badly named "ktest-timefix"
# specifically means "21 Gmail sessions replayed through OpenSSL
# s_client/s_server and recorded as ktest files, with their timestamps
# fixed up."  Unfortunately, the network data ("ktest-timefix") is
# identified solely as a symlink to a ${DATETIME} directory.  That is,
# the directory "ktest-timefix" is actually just a symlink to a
# subdirectory named 2016-09-08.00:28:07 as shown below.
#
#   thew:~/cliver/data/klee-out/IDDFS-nAES-1-opt/openssl-klee$ ls -l
#   total 8
#   drwxr-xr-x ... 4096 Sep  7 15:14 2016-09-07.15:14:28
#   drwxr-xr-x ...   46 Sep  7 15:16 2016-09-07.15:16:18
#   drwxr-xr-x ...   47 Sep  7 15:16 2016-09-07.15:16:33
#   drwxr-xr-x ... 4096 Sep  8 00:28 2016-09-08.00:28:07
#   drwxr-xr-x ...   46 Sep  8 00:30 2016-09-08.00:29:57
#   drwxr-xr-x ...   47 Sep  8 00:30 2016-09-08.00:30:12
#   lrwxrwxrwx ...   19 Sep  8 00:29 heartbeat -> 2016-09-08.00:29:57
#   lrwxrwxrwx ...   19 Sep  8 00:30 heartbleed-only -> 2016-09-08.00:30:12
#   lrwxrwxrwx ...   19 Sep  8 00:28 ktest-timefix -> 2016-09-08.00:28:07
#
# Due to the naming of directories with dates only, it is tricky to
# tell which of the directories dated Sep 7 corresponds to heartbeat,
# heartbleed-only, and ktest-timefix.  Fortunately, further
# subdirectories inside (e.g., gmail_spdy_stream* as opposed to
# heartbeat_simple_stream00) will confirm what network logs were being
# verified. Finally, the innermost directory holds the files written
# by each run of KLEE, and hence our nickname "klee-droppings".
#
#   $ ls
#   cliver_stage.stats    debug.txt     run.stats
#   cliver.stats          info.txt      searcher_stage.graph
#   cliver.stats.summary  messages.txt  warnings.txt
#
# The cliver.stats file is the most important one (the only one?) used
# by this experiments script.  It is formatted as a CSV file with all
# the round-by-round statistics about the performance of the verifier.
#
# [results]
# ---------
#
# Statistics CSV files (experiments separate):
#
#   ${ROOT_DIR}/data/results/${CLIENT}/data/${DATATAG}/${EXPERIMENT}/${DATETIME}
#
# Plots and summary CSV files (experiments combined):
#
#   ${ROOT_DIR}/data/results/${CLIENT}/plots/${DATATAG}/${DATETIME}
#
# The results directories are generated by this script and subordinate
# R scripts.  Note that while the [klee-droppings] hierarchy is sorted
# first by experiment and second by client/datatag, the [results]
# hierarchy is sorted first by client/datatag and then by
# experiment. And in fact, for plotting, the graphs for different
# experiments are not separated into subdirectories at all.
#
# (1) When generating results, the first step is to copy the cliver.stats
# CSV files into a directory structure better grouped for generating
# plots, namely the template path with ${CLIENT}/data/${DATATAG}
# above.  For example, the file cliver.stats file from the example
# path in [klee-droppings] would be copied to:
#
#   data/results/openssl-klee/data/ktest-timefix/IDDFS-nAES-1-opt/\
#                 2016-09-08.00:28:07/gmail_spdy_stream00.csv
#
# In fact, all 21 cliver.stats files for that run would be copied to
# the same directory.
#
#   $ ls
#   gmail_spdy_stream00.csv  gmail_spdy_stream07.csv  gmail_spdy_stream14.csv
#   gmail_spdy_stream01.csv  gmail_spdy_stream08.csv  gmail_spdy_stream15.csv
#   gmail_spdy_stream02.csv  gmail_spdy_stream09.csv  gmail_spdy_stream16.csv
#   gmail_spdy_stream03.csv  gmail_spdy_stream10.csv  gmail_spdy_stream17.csv
#   gmail_spdy_stream04.csv  gmail_spdy_stream11.csv  gmail_spdy_stream18.csv
#   gmail_spdy_stream05.csv  gmail_spdy_stream12.csv  gmail_spdy_stream19.csv
#   gmail_spdy_stream06.csv  gmail_spdy_stream13.csv  gmail_spdy_stream20.csv
#
# (2) The second step is to generate the plots. This is done by the R
# script make_graphs.r (on the most recent data), which writes its
# output to:
#
#   data/results/openssl-klee/plots/ktest-timefix/2016-09-08.00:28:03
#
# Directory contents contain pdf or png plots, depending on a
# hardcoded option.  Note the discrepancy between the date/time here
# and the date/time in step (1) of generating results. While there is
# some correlation between the two, the R scripts do not actually
# parse the directory names to obtain the time, but instead use the
# start time of the top-level experiments.sh script (aka "run
# prefix"). This is because we are assembling plots from different
# runs of KLEE/Cliver (and different "experiments") in the same
# directory, so the timestamp from any particular run would not be
# meaningful.  Instead, we fall back to the timestamp of the top-level
# experiments.sh script, thereby giving a unique "run prefix" that can
# be used to identify an instance of the experiments suite.
#
# In addition, the make_graphs.r script drops some summary data in the
# plot output directory. The following files are written:
#
#   2016-09-08-00:59$ ls -l | grep -v .pdf
#   total 6952
#   -rw-r--r-- 1 achi compsci 5385131 Sep  8 01:01 processed_data.csv
#   -rw-r--r-- 1 achi compsci    4297 Sep  8 01:01 stat_table.tex
#   -rw-r--r-- 1 achi compsci    4340 Sep  8 01:01 summary_data.csv
#
# The most useful of these files is processed_data.csv, which is the
# combination of all of the data from the various cliver.stats files.
#
# Note: the R scripts do some correction on the timestamps to make
# them monotonic -- the way the Gmail timestamps are mapped from
# original tcpdump to ktest file can make it so that they are not
# monotonically increasing.  In addition, the R scripts remove the
# startup and shutdown times for KLEE, leaving only the round-by-round
# verification times.  The processed_data.csv file contains the
# corrected timestamps, not the originals.
#
# (3) The final step is write a nice little html file for each
# directory, enabling web browser viewing via the buildbot webpage.
# The html file lives outside the directory, with a name corresponding
# to the directory.
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
. $HERE/build_configs/gsec_common


###############################################################################
# Global Variables
###############################################################################

EXP_CONFIG="" # experiment config file
EXTRA_BUILD_CONFIG="" # extra build config file (if any)
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
      
      cliver_command="${CLIVERSH} -t $expType -c $client -b $data_tag -k $ktest_dir -o klee-droppings/$expOutput $exp_cliver_params ${CLIVER_PARAMETERS} ${bitcode_params} $extra_params "
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

      # Directory that holds output (klee droppings) of all cliver.sh
      # experiments using this client.  For example,
      # data/IDDFS-nAES-1-opt/openssl-klee
      client_data_path=${DATA_DIR}/klee-droppings/${expOutput}/${client}

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

  # Individual client plots.  A single client (e.g., OpenSSL) can be
  # run on several different datasets (ktest-timefix, heartbeat,
  # heartbleed) under different "experiments" (IDDFS-nAES-1-opt,
  # IDDFS-nAES-1-opt-dropS2C,...).  Each client/dataset pair gets one
  # output directory of plots.

  for (( j=0; j<${num_clients}; ++j ));
  do
    local client=${CLIENT_LIST[$j]}

    # the symlink created by cliver.sh is set to $data_tag
    local data_tag=$(basename ${CLIENT_LIST_KTEST[$j]})

    leval ./gsec-support/make_graphs.r $RESULTS_LOCATION/$client \
          ${data_tag} ${CLIENT_LIST_R_BIN_WIDTH[$j]} \
          ${RUN_PREFIX} ${EXPERIMENT_LIST_NAMES[@]}
  done

  # Cross-client comparison plots.  These comparison plots are
  # generated whenever there are different clients (e.g., OpenSSL vs
  # BoringSSL) running the same data tag (e.g., ktest-timefix) and the
  # same "experiment" (e.g., IDDFS-nAES-1-opt).
  #
  # Implementation notes: (1) Currently, the comparison plots require
  # the bin widths for the various clients to match (e.g., all set to
  # 30), though this is not a fundamental limitation and could be
  # changed in the future.  (2) We simply take the processed_data.csv
  # files from the individual client plot directories instead of going
  # back and re-compiling the data.

  local CROSS_CLIENT_ROOT="${RESULTS_LOCATION}/cross-client"
  local target_data_dir="${CROSS_CLIENT_ROOT}/data/${RUN_PREFIX}"
  local target_plots_dir="${CROSS_CLIENT_ROOT}/plots/${RUN_PREFIX}"
  mkdir -p "${target_data_dir}" "${target_plots_dir}"
  lecho "Collating processed data in ${target_data_dir}"

  for (( j=0; j<${num_clients}; ++j ));
  do
    local client=${CLIENT_LIST[$j]}
    local data_tag=$(basename ${CLIENT_LIST_KTEST[$j]})
    local bin_width=${CLIENT_LIST_R_BIN_WIDTH[$j]}
    local target_filename="${client}__${data_tag}__${bin_width}.csv"

    local plots_dir="$RESULTS_LOCATION/$client/plots/$data_tag/$RUN_PREFIX"
    local processed_data="${plots_dir}/processed_data.csv"
    leval cp "${processed_data}" "${target_data_dir}/${target_filename}"
  done

  lecho "Generating cross-client comparison plots"
  leval ./gsec-support/make_crossclient_graphs.r "${CROSS_CLIENT_ROOT}" \
        "${RUN_PREFIX}" ${EXPERIMENT_LIST_NAMES[@]}

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

    PLOT_DIR=${RESULTS_LOCATION}/${client}/plots/${data_tag}/${RUN_PREFIX}
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

    PLOT_DIR=${RESULTS_LOCATION}/${client}/plots/${data_tag}/${RUN_PREFIX}
    HTML_DIR=${RESULTS_LOCATION}/${client}/plots/${data_tag}/
    htmlfile=${HTML_DIR}/${RUN_PREFIX}.html
    jquery="http://ajax.googleapis.com/ajax/libs/jquery/1/jquery.js"
    jsdir="http://cs.unc.edu/~rac/js/galleria"

    echo "<html><head><title>Cliver Plots: ${RUN_PREFIX}</title>" > $htmlfile
    echo "<script src=\"${jquery}\"></script>" >> $htmlfile
    echo "<script src=\"${jsdir}/galleria.js\"></script>" >> $htmlfile
    echo "<script src=\"${jsdir}/config.js\"></script>" >> $htmlfile
    echo "</head><body><div class=\"galleria\">" >> $htmlfile
    for fullPathPlot in ${PLOT_DIR}/*
    do
      local plot=$(basename $fullPathPlot)
      echo "<img src=\"./${RUN_PREFIX}/$plot\" data-title=\"$plot\">" >> $htmlfile
    done
    echo "</div></body></html>" >> $htmlfile
  done
}

###############################################################################

# are all parameters passed to this function distinct?
all_distinct()
{
    local n=$#
    local args=("$@")
    local distinct_status=1  # 1 if all distinct, 0 if duplicate found
    for (( i = 0; i < n; i++ )); do
        for (( j = i + 1; j < n; j++ )); do
            if [ "${args[$i]}" == "${args[$j]}" ]; then
                 distinct_status=0 # failure: duplicate found
            fi
        done
    done
    echo ${distinct_status}
}

###############################################################################

load_config()
{
  lecho "Experiments Start Time and Run Prefix: ${RUN_PREFIX}"
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

  lecho "Experiments: ${EXPERIMENT_LIST_NAMES[@]}"
  lecho "Clients: ${CLIENT_LIST[@]}"

  # KTest config checks
  client_datatag_pairs=()
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
      local data_tag=$(basename ${CLIENT_LIST_KTEST[$j]})
      client_datatag_pairs+=("${client}:${data_tag}")
      lecho "Client ${j}: ${client} using data '${data_tag}' -- ${ktest_count} ktest files from ${client_ktest}"
    fi
  done

  distinct_status=$(all_distinct "${client_datatag_pairs[@]}")
  if [ "$distinct_status" -ne 1 ]; then
      echo "${PROG}: client/data tag pairs must all be distinct"
      exit
  fi
}

###############################################################################

main() 
{
  while getopts "c:e:vp" opt; do
    case $opt in
      e) # variables supplementing or overriding gsec_common
        EXTRA_BUILD_CONFIG=$OPTARG
        source ${EXTRA_BUILD_CONFIG}
        ;;
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

