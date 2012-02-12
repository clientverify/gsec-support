#!/bin/bash

WRAPPER="`readlink -f "$0"`"
HERE="`dirname "$WRAPPER"`"

# Include gsec_common
. $HERE/gsec_common

ROOT_DIR="`pwd`"

# default config values

while getopts ":vr:j:t:c:m:" opt; do
  case $opt in
    v)
      VERBOSE_OUTPUT=1
      ;;

    m)
      MODE="$OPTARG"
      ;;

    c)
      COUNT=$OPTARG
      ;;

    r)
      echo "Setting root dir to $OPTARG"
      ROOT_DIR="$OPTARG"
      ;;

    :)
      echo "Option -$OPTARG requires an argument"
      exit
      ;;

  esac
done

initialize_root_directories

BASE_DIR="$DATA_DIR/network/xpilot-$MODE"

# record start time
start_time=$(elapsed_time)

#=============================================================================
# configuration parameters
#=============================================================================
SERVER_ADDRESS="localhost"
PLAYER_NAME="p1"
KTEST_SUFFIX="ktest"
RECENT_LINK="last-run"
GEOMETRY="800x600+100+100"

#=============================================================================
# game client and server paths
#=============================================================================
SERVER_BIN="xpilot-ng-server-x86"
SERVER_OPT=" "
SERVER_COMMAND="$XPILOT_ROOT/bin/$SERVER_BIN $SERVER_OPT "

CLIENT_BIN="xpilot-ng-server-x86"
CLIENT_OPT=" "
CLIENT_COMMAND="$XPILOT_ROOT/bin/$CLIENT_BIN $CLIENT_OPT "

#=============================================================================
# output paths
#=============================================================================

DATA_DIR=$BASE_DIR
RESULTS_DIR=$BASE_DIR/"results"

RUN_PREFIX=$(date +%F.%T)
LOG_DIR=$DATA_DIR/$RUN_PREFIX
KTEST_DIR=$DATA_DIR/$RUN_PREFIX
OUT_DIR=$RESULTS_DIR/$RUN_PREFIX

#=============================================================================
# Default options 
#=============================================================================
CLIENT_OPTIONS=""
CLIENT_OPTIONS+=" -texturedWalls no -texturedDecor no -texturedObjects no "
CLIENT_OPTIONS+=" -fullColor no -geometry $GEOMETRY "
CLIENT_OPTIONS+=" -keyTurnLeft a -keyTurnRight d -keyThrust w "

#=============================================================================
# Xpilot execution
#=============================================================================

case "$MODE":
	server*)
		leval $SERVER_BIN
		;;
	client*)
		leval $CLIENT_BIN -join $CLIENT_OPTIONS $SERVER_ADDRESS
		;;
	record*)
		CLIENT_OPTIONS+=" -recordInputFile $KTEST_DIR/input.record "
		leval $CLIENT_BIN -join $CLIENT_OPTIONS $SERVER_ADDRESS
		;;
	playback*)
		leval $CLIENT_BIN -join $CLIENT_OPTIONS $SERVER_ADDRESS
		;;
esac


