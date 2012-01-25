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

cliver_training()
{
  echo "[cliver training]"
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

  initialize_logging

  # record start time
  start_time=$(elapsed_time)

  cliver_training

  echo "Elapsed time: $(elapsed_time $start_time)"
}

# Run main
main "$@"
