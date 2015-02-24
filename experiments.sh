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

# Include gsec_common
. $HERE/gsec_common


###############################################################################
# Global Variables
###############################################################################

EXP_CONFIG="" # experiment config file 

###############################################################################

on_exit()
{
  if [ $ERROR_EXIT -eq 1 ]; then
    echo "Error"
  fi
  if [ $ERROR_EXIT -eq 0 ]; then
    echo "Elapsed time: $(elapsed_time $start_time)"
  fi
}

###############################################################################

run_experiments()
{
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
      data_tag=${CLIENT_LIST_DATA_TAG[$j]}

      ./gsec-support/cliver.sh -t $expType -c $client -b $data_tag -x "$extra_params" -o $expOutput
    done

  done
}

###############################################################################

copy_results()
{
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
      data_tag=${CLIENT_LIST_DATA_TAG[$j]}

      ./gsec-support/copy_results.sh -s data/$expOutput -d ${RESULTS_LOCATION} -b $data_tag
    done


  done
}

###############################################################################

do_plots()
{
  clientListLen=${#CLIENT_LIST[@]}

  for (( j=0; j<${clientListLen}; ++j ));
  do
    client=${CLIENT_LIST[$j]}
    ./gsec-support/make_graphs.r $RESULTS_LOCATION/$client
  done
}

###############################################################################

generate_plot_html()
{
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

main() 
{
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

  echo "Reading experiment config file: ${EXP_CONFIG}"
  source ${EXP_CONFIG}

  # do the experiments specified in the config file
  run_experiments

  # copy the results to location specified in config file
  copy_results

  # create plots with R
  do_plots
  
  # create simple html for viewing plots
  generate_plot_html
}

# set up exit handler
trap on_exit EXIT

# record start time
start_time=$(elapsed_time)

# Run main
main "$@"
ERROR_EXIT=0

