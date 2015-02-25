#!/bin/bash

# see http://www.davidpashley.com/articles/writing-robust-shell-scripts.html
set -u # Exit if uninitialized value is used 
#set -e # Exit on non-true value
set -o pipefail # exit on fail of any command in a pipe

WRAPPER="`readlink -f "$0"`"
HERE="`dirname "$WRAPPER"`"

# Include gsec_common
. $HERE/gsec_common

VERBOSE_OUTPUT=1
ROOT_DIR="`pwd`"
DATA_TAG="recent"

usage()
{
  echo -e "$(basename $0)\n\nUSAGE:"
  echo -e "\t-s [source]\t\t\t(source directory(s) to be recursively searched for debug.txt files)(REQUIRED)" 
  echo -e "\t-d [destination]\t\t(ssh://server:direcory to copy formated results)(REQUIRED)"
  echo -e "\t-b [data tag]\t\t\t(name of subdirectory)(default=recent)"
  echo -e "\t-h \t\t\t\t(help/usage)"
}

RESULTS_SOURCE=""

main()
{
  while getopts "b:s:d:h" opt; do
    case $opt in

      b)
        DATA_TAG="$OPTARG"
        ;;

      d)
        RESULTS_DESTINATION="$OPTARG"
        ;;

      s)
        RESULTS_SOURCE+=" $OPTARG"
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

  OUTPUT_ROOT="./.$(basename $0)-$RANDOM"
  #echo $OUTPUT_ROOT

  pattern="debug.txt"
  for source in $RESULTS_SOURCE ; do
    #echo "source: "$source
    for client_dir in $source/* ; do
      local data_id=$(readlink $client_dir/$DATA_TAG)
      local output_dir=$OUTPUT_ROOT/$(basename $client_dir)/data/$(basename $source)/$data_id
      #echo "output_dir: "$output_dir
      #echo "client_dir: "$client_dir

      mkdir -p $output_dir

      for file in $( find -L $client_dir/$DATA_TAG -name $pattern); do

        local stats_file="$(basename $(dirname $file) ).txt"
        local dest=$output_dir/$stats_file
        #echo "grep STATS file=$file > dest=$dest"
        grep STATS $file | cut -d " " -f 2- > $dest
        #echo "done"

        if [[ $(wc -l $dest | awk '{print $1}' ) -eq 0 ]]; then
          echo "error: $file is empty"
          rm $dest
        fi

      done
    done
  done
  #rsync -ave ssh $OUTPUT_ROOT/* $RESULTS_DESTINATION
  cp -r $OUTPUT_ROOT/* $RESULTS_DESTINATION/
  rm -rf $OUTPUT_ROOT
}

# Run main
main "$@"

