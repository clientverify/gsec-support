#!/bin/bash

# see http://www.davidpashley.com/articles/writing-robust-shell-scripts.html
set -u # Exit if uninitialized value is used 
set -e # Exit on non-true value
set -o pipefail # exit on fail of any command in a pipe

WRAPPER="`readlink -f "$0"`"
HERE="`dirname "$WRAPPER"`"

# Include gsec_common
. $HERE/gsec_common


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

  DATA_FILE="debug.txt"
  for i in $(find $RESULTS_SOURCE -name $DATA_FILE); do
    echo $i
  done

}

# Run main
main "$@"
