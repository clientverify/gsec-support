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
  echo -e "\t-h \t\t\t\t(help/usage)"
}

RESULTS_SOURCE=""

main()
{
  while getopts "b:s:d:v:h" opt; do
    case $opt in

      b)
        DATA_TAG="$OPTARG"
        ;;

      d)
        RESULTS_DESTINATION="$OPTARG"
        ;;

      s)
        RESULTS_SOURCE+="$OPTARG "
        ;;

      v)
        VERIFY_BC_DIR+="$OPTARG"
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
  NETWORK_DATA_ROOT="./data/network"

  #echo "== DATA_TAG=$DATA_TAG"
  #echo "== Copying socket log files in $NETWORK_DATA_ROOT"
  if [[ ! -d "$NETWORK_DATA_ROOT" || $(ls -l $NETWORK_DATA_ROOT | wc -l) -eq 0 ]]; then
    echo "== Error: $NETWORK_DATA_ROOT doesn't exist"
  else
    for client_dir in $NETWORK_DATA_ROOT/* ; do
      local data_id=$(readlink $client_dir/$DATA_TAG)
      #local output_dir=$OUTPUT_ROOT/$(basename $client_dir)/socketlogs/$data_id-$DATA_TAG
      local output_dir=$OUTPUT_ROOT/$(basename $client_dir)/socketlogs/
      mkdir -p $output_dir
      local pattern="*client_socket.log"
      local count=0
      if [ -d "$client_dir/$DATA_TAG" ]; then
        for file in $( find -L $client_dir/$DATA_TAG -name $pattern); do
          cp $file $output_dir/
          let count=$count+1
        done
      fi
      #echo "Copied $count socket log files in $client_dir/$DATA_TAG"
    done
  fi

  #echo "== Reading files in $RESULTS_SOURCE"
  local pattern="debug.txt"
  for source in $RESULTS_SOURCE ; do
    #echo "source: "$source
    if [[ ! -d "$source" || $(ls -l $source | wc -l) -eq 0 ]]; then
      echo "Error: $source is empty"
    else
      for client_dir in $source/* ; do
        local data_id=$(readlink $client_dir/$DATA_TAG)
        local base_output_dir=$(basename $client_dir)/data/$(basename $source)
        local output_dir=$OUTPUT_ROOT/$base_output_dir/$data_id
        local client_base_dir="$(basename $client_dir)"
        #echo "output_dir: "$output_dir
        #echo "client_dir: "$client_dir

        mkdir -p $output_dir

        no_empty_files=true
        local count=0
        if [ -d "$client_dir/$DATA_TAG" ]; then
          for file in $( find -L $client_dir/$DATA_TAG -name $pattern); do

            if $no_empty_files ; then 
              local stats_file="$(basename $(dirname $file) ).txt"
              local dest=$output_dir/$stats_file
              #echo "grep STATS file=$file > dest=$dest"
              #grep STATS $file > $dest
              #grep STATS $file | awk '{for (i=2;i<=NF;i++) { printf("%d ",$i); } print "";}' > $dest

              #Grep STATS line and remove first field ('STATS')
              grep STATS $file | cut -c7- > $dest

              if [[ $(wc -l $dest | awk '{print $1}' ) -eq 0 ]]; then
                echo "Skipping $base_output_dir, Empty file: "$(basename $(dirname $file) ) 
                no_empty_files=false
                rm $dest

              #elif test ${VERIFY_BC_DIR+defined}; then
              #  local tmp_dir="$(basename $(dirname $file) )"
              #  local training_bc_file="$VERIFY_BC_DIR/$client_base_dir/$DATA_TAG/$tmp_dir/final.bc" 
              #  local verify_bc_file="$client_dir/$DATA_TAG/$tmp_dir/final.bc"
              #  #echo "comparing $verify_bc_file and $training_bc_file"
              #  if ! cmp $training_bc_file $verify_bc_file &> /dev/null; then
              #    echo "cmp failed on $verify_bc_file "
              #    rm $dest
              #    no_empty_files=false
              #  fi 
              fi

              let count=$count+1
            fi
          done
        fi
        if  [[ $no_empty_files == false || $count -eq 0 ]] ; then 
          echo "No result files for $base_output_dir"
          #echo "rm -rf $OUTPUT_ROOT/$base_output_dir"
          rm -rf $OUTPUT_ROOT/$base_output_dir
        else
          echo "$count result files for $base_output_dir"
        fi
      done
    fi
  done
  #echo "== Sending results to $RESULTS_DESTINATION"
  if [[ ! -d "$OUTPUT_ROOT" || $(ls -l $OUTPUT_ROOT| wc -l) -eq 0 ]]; then
    echo "Error: $OUTPUT_ROOT is empty"
  else
    rsync -q -ave ssh $OUTPUT_ROOT/* $RESULTS_DESTINATION
  fi
  rm -rf $OUTPUT_ROOT
}

# Run main
main "$@"

