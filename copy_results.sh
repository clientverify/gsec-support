#!/bin/bash

# see http://www.davidpashley.com/articles/writing-robust-shell-scripts.html
set -u # Exit if uninitialized value is used 
set -e # Exit on non-true value
set -o pipefail # exit on fail of any command in a pipe

WRAPPER="`readlink -f "$0"`"
HERE="`dirname "$WRAPPER"`"

# Include gsec_common
. $HERE/gsec_common

VERBOSE_OUTPUT=1
ROOT_DIR="`pwd`"

usage()
{
  echo -e "$(basename $0)\n\nUSAGE:"
  echo -e "\t-s [source]\t\t\t(source directory to be recursively searched for debug.txt files)(REQUIRED)" 
  echo -e "\t-d [destination]\t\t(ssh://server:direcory to copy formated results)(REQUIRED)"
  echo -e "\t-h \t\t\t\t(help/usage)"
}


main()
{
  while getopts "s:d:h" opt; do
    case $opt in

      d)
        RESULTS_DESTINATION="$OPTARG"
        ;;

      s)
        RESULTS_SOURCE="$OPTARG"
        ;;

      h)
        usage
        exit
        ;;

    esac
  done

  #initialize_root_directories
  #initialize_logging $@
  #DRY_RUN=1

  #BASE_NAME="debug.txt"
  #for file in $( find $RESULTS_SOURCE -name $BASE_NAME ); do

  PATTERN="debug.txt"
  for dir in $RESULTS_SOURCE/* ; do
    for file in $( find -L $dir/recent -name $PATTERN ); do
      local stats_file="./.$(basename $0)-$RANDOM.txt"
      #echo $file
      #echo $stats_file
      
      #local dest=$RESULTS_DESTINATION/$(basename $dir)/$(basename $RESULTS_SOURCE)/$(basename $(dirname $file) ).txt
      local dest=$RESULTS_DESTINATION/$(basename $dir)/$(basename $RESULTS_SOURCE)/

      grep STATS $file > $stats_file
      if [[ $(wc -l $stats_file | awk '{print $1}' ) -gt 0 ]]; then
        echo "rsync -ave ssh $stats_file $dest"
        rsync -ave ssh $stats_file $dest
      else
        echo "error: $file is empty"
        rm $stats_file
      fi
      rm $stats_file
    done
  done

}

# Run main
main "$@"
