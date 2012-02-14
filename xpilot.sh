#!/bin/bash

WRAPPER="`readlink -f "$0"`"
HERE="`dirname "$WRAPPER"`"

# Include gsec_common
. $HERE/gsec_common

# default config values
ROOT_DIR="`pwd`"
VERBOSE_OUTPUT=0
MODE="client"
COUNT=0

#=============================================================================
# need to automatically set this var...
if [ -n "${XPILOTHOST:+x}" ] 
	echo "set XPILOTHOST environment variable before running client"
	exit
fi
#=============================================================================

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
initialize_logging $@

BASE_DIR="$DATA_DIR/network/xpilot-$MODE"

RECORD_DIR="$DATA_DIR/network/xpilot-record"

# record start time
start_time=$(elapsed_time)

#=============================================================================
# configuration parameters
#=============================================================================
SERVER_ADDRESS="localhost"
PLAYER_NAME="p1"
KTEST_SUFFIX="ktest"
RECENT_LINK="recent"
GEOMETRY="800x600+100+100"
RECORD_FILE="input.rec"

#=============================================================================
# game client and server paths
#=============================================================================
SERVER_BIN="xpilot-ng-server-x86"
SERVER_OPT=" "
SERVER_COMMAND="$XPILOT_ROOT/bin/$SERVER_BIN $SERVER_OPT "

CLIENT_BIN="xpilot-ng-x11-x86"
CLIENT_OPT=" "
CLIENT_COMMAND="$XPILOT_ROOT/bin/$CLIENT_BIN $CLIENT_OPT "

#=============================================================================
# output paths
#=============================================================================

DATA_DIR=$BASE_DIR
KTEST_DIR=$DATA_DIR/$RUN_PREFIX

#=============================================================================
# Default options 
#=============================================================================
CLIENT_OPTIONS=""
CLIENT_OPTIONS+=" -join -texturedWalls no -texturedDecor no -texturedObjects no "
CLIENT_OPTIONS+=" -fullColor no -geometry $GEOMETRY "
CLIENT_OPTIONS+=" -keyTurnLeft a -keyTurnRight d -keyThrust w "

SERVER_OPTIONS=""
SERVER_OPTIONS+=" -ktestFileName \"$KTEST_DIR/xpilot.ktest\" "

#=============================================================================
# Xpilot execution
#=============================================================================

make_xpilot_dirs()
{
	mkdir -p $KTEST_DIR 
	rm $DATA_DIR/$RECENT_LINK
	ln -sfT $DATA_DIR/$RUN_PREFIX $DATA_DIR/$RECENT_LINK
}

case "$MODE" in 
	server)
		make_xpilot_dirs
		leval $SERVER_COMMAND $SERVER_OPTIONS
		;;
	client)
		leval $CLIENT_COMMAND -join $CLIENT_OPTIONS $SERVER_ADDRESS
		;;
	record)
		make_xpilot_dirs
		CLIENT_OPTIONS+=" -recordInputFile $KTEST_DIR/$RECORD_FILE "
		leval $CLIENT_COMMAND -join $CLIENT_OPTIONS $SERVER_ADDRESS
		;;
	playback)
		CLIENT_OPTIONS+=" -playInputFile $RECORD_DIR/$RECENT_LINK/$RECORD_FILE "
		leval $CLIENT_COMMAND -join $CLIENT_OPTIONS $SERVER_ADDRESS
		;;
esac

leval xset r on


