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

###############################################################################
# Variables that can be defined in config file

EXPERIMENT_LIST=()
EXPERIMENT_LIST_OUTPUT=()
CLIENT_LIST=()
CLIENT_LIST_KTEST=()
CLIENT_LIST_DATA_TAG=()
CLIENT_LIST_EXTRA_PARAMETERS=()
CLIENT_LIST_EXTRA_PARAMETERS=()
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
}

###############################################################################

run_experiments()
{
  lecho "Running Cliver Experiments"

  clientListLen=${#CLIENT_LIST[@]}
  expListLen=${#EXPERIMENT_LIST[@]}

  for (( i=0; i<${expListLen}; ++i ));
  do

    expType=${EXPERIMENT_LIST[$i]}
    expOutput=${EXPERIMENT_LIST_OUTPUT[$i]}

    for (( j=0; j<${clientListLen}; ++j ));
    do
      client=${CLIENT_LIST[$j]}
      extra_params=${CLIENT_LIST_EXTRA_PARAMETERS[$j]}
      #data_tag=${CLIENT_LIST_DATA_TAG[$j]}
      data_tag=$(basename ${CLIENT_LIST_KTEST[$j]})

      ktest_dir=${CLIENT_LIST_KTEST[$j]}
      
      cliver_command="./gsec-support/cliver.sh -s -t $expType -c $client -b $data_tag -k $ktest_dir -x \"$extra_params\" -o $expOutput"
      lecho "EXEC: ${cliver_command}"
      eval ${cliver_command}
    done
  done
}

###############################################################################

copy_results()
{
  lecho "Copying Cliver Output"

  clientListLen=${#CLIENT_LIST[@]}
  expListLen=${#EXPERIMENT_LIST[@]}

  for (( i=0; i<${expListLen}; ++i ));
  do

    expType=${EXPERIMENT_LIST[$i]}
    expOutput=${EXPERIMENT_LIST_OUTPUT[$i]}

    for (( j=0; j<${clientListLen}; ++j ));
    do
      client=${CLIENT_LIST[$j]}
      extra_params=${CLIENT_LIST_EXTRA_PARAMETERS[$j]}
      #data_tag=${CLIENT_LIST_DATA_TAG[$j]}
      data_tag=$(basename ${CLIENT_LIST_KTEST[$j]})

      leval ./gsec-support/copy_results.sh -s data/$expOutput -d ${RESULTS_LOCATION}/ -b $data_tag
    done
  done
}

###############################################################################

do_plots()
{
  lecho "Plotting Cliver Data"
  clientListLen=${#CLIENT_LIST[@]}

  for (( j=0; j<${clientListLen}; ++j ));
  do
    client=${CLIENT_LIST[$j]}
    leval ./gsec-support/make_graphs.r $RESULTS_LOCATION/$client
  done
}

###############################################################################

generate_plot_html()
{
  lecho "Generating HTML"
  clientListLen=${#CLIENT_LIST[@]}

  for (( j=0; j<${clientListLen}; ++j ));
  do
    client=${CLIENT_LIST[$j]}
    RECENT=$(ls -t ${RESULTS_LOCATION}/${client}/plots/ | head -1)
    HTML_DIR=$RESULTS_LOCATION/$client/plots
    PLOT_DIR=${RESULTS_LOCATION}/${client}/plots/${RECENT}
    echo "<html><head><title>Cliver Plots: $RECENT</title></head><body>" > ${HTML_DIR}/$RECENT.html
    for fullPathPlot in ${PLOT_DIR}/*
    do
      local plot=$(basename $fullPathPlot)
      echo "<img src=\"./$RECENT/$plot\" width=50%></br>$plot</br></br>" >> ${HTML_DIR}/$RECENT.html
    done
    echo "</body></html>" >> ${HTML_DIR}/$RECENT.html
  done
}

###############################################################################

load_config()
{
  lecho "Loading Experiment Config File: ${EXP_CONFIG}"

  source ${EXP_CONFIG}

  # check the configuration file

  expListLen=${#EXPERIMENT_LIST[@]}
  expListOutputLen=${#EXPERIMENT_LIST_OUTPUT[@]}

  if [ "$expListLen" -ne "$expListOutputLen" ]; then
    echo "${PROG}: EXPERIMENT_LIST* vars not equal lengths"
    exit
  fi

  clientListLen=${#CLIENT_LIST[@]}
  clientListKtestLen=${#CLIENT_LIST_KTEST[@]}
  #clientListDataTagLen=${#CLIENT_LIST_DATA_TAG[@]}
  clientListExtraParametersLen=${#CLIENT_LIST_EXTRA_PARAMETERS[@]}

     #[ "$clientListLen" -ne "$clientListDataTagLen" ] ||
  if [ "$clientListLen" -ne "$clientListKtestLen" ] ||
     [  "$clientListLen" -ne "$clientListExtraParametersLen" ]; then
    echo "CLIENT_LIST* variables not equal lengths"
    echo "${PROG}: CLIENT_LIST* vars not equal lengths"
    exit
  fi
}

###############################################################################

sync_ktest_data()
{
  lecho "Syncing Ktest Data"

  clientListLen=${#CLIENT_LIST[@]}

  for (( i=0; i<${clientListLen}; ++i ));
  do
    local ktestSrc=${CLIENT_LIST_KTEST[$i]}
    local ktestDst=$DATA_DIR/network/${CLIENT_LIST[$i]}/
    mkdir -p $ktestDst
    #rsync -ave ssh $ktestSrc $ktestDst
    lecho cp -r $ktestSrc $ktestDst
    leval cp -r $ktestSrc $ktestDst
  done
}

###############################################################################

main() 
{
  initialize_root_directories
  initialize_logging $@

  while getopts "c:" opt; do
    case $opt in
      c)
        EXP_CONFIG=$OPTARG
        ;;
      :)
        echo "Option -$OPTARG requires an argument"
        exit
        ;;
    esac
  done

  # source "config" file and sanity check array lengths
  load_config

  # copy ktest data
  sync_ktest_data

  ## do the experiments specified in the config file
  run_experiments

  ## copy the results to location specified in config file
  copy_results

  ## create plots with R
  do_plots

  ## create simple html for viewing plots
  generate_plot_html
}

# set up exit handler
trap on_exit EXIT

# record start time
start_time=$(elapsed_time)

# Run main
main "$@"
ERROR_EXIT=0

