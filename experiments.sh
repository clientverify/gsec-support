#!/bin/bash

###############################################################################
### experiments.sh : Run Training or Verification experiments

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

    for (( j=0; j<${num_clients}; ++j ));
    do
      client=${CLIENT_LIST[$j]}
      data_tag=$(basename ${CLIENT_LIST_KTEST[$j]})

      ktest_dir=${CLIENT_LIST_KTEST[$j]}

      client_params=${CLIENT_LIST_PARAMETERS[$j]}
      extra_params=" -x \"${client_params} ${exp_params}\" "
      
      cliver_command="${CLIVERSH} -s -t $expType -c $client -b $data_tag -k $ktest_dir -o $expOutput ${CLIVER_PARAMETERS} $extra_params "
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
      stats_dir=${RESULTS_LOCATION}/$client/data/$expOutput/$data_id
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
    client=${CLIENT_LIST[$j]}
    leval ./gsec-support/make_graphs.r $RESULTS_LOCATION/$client ${CLIENT_LIST_R_BIN_WIDTH[$j]} ${EXPERIMENT_LIST_NAMES[@]}
  done
}

###############################################################################

generate_plot_pdf()
{
  lecho "Generating PDF"
  num_clients=${#CLIENT_LIST[@]}

  for (( j=0; j<${num_clients}; ++j ));
  do
    client=${CLIENT_LIST[$j]}
    RECENT_FULL_PATH=$(find ${RESULTS_LOCATION}/${client}/plots/* -type d -prune -exec ls -d {} \; | tail -1)
    RECENT=$(basename ${RECENT_FULL_PATH})
    PLOT_DIR=${RESULTS_LOCATION}/${client}/plots/${RECENT}
    HTML_DIR=${RESULTS_LOCATION}/${client}/plots
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
    client=${CLIENT_LIST[$j]}
    RECENT_FULL_PATH=$(find ${RESULTS_LOCATION}/${client}/plots/* -type d -prune -exec ls -d {} \; | tail -1)
    RECENT=$(basename ${RECENT_FULL_PATH})

    HTML_DIR=${RESULTS_LOCATION}/${client}/plots
    PLOT_DIR=${RESULTS_LOCATION}/${client}/plots/${RECENT}
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

  # check that the client config arrays are of equal length
  if [ "$num_clients" -ne "$clientListKtestLen" ] ||
     [  "$num_clients" -ne "$client_extra_params_len" ]; then
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
  generate_plot_pdf
}

# set up exit handler
trap on_exit EXIT

# record start time
start_time=$(elapsed_time)

# Run main
main "$@"
ERROR_EXIT=0

