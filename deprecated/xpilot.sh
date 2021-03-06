#!/bin/bash

WRAPPER="`readlink -f "$0"`"
HERE="`dirname "$WRAPPER"`"

# Include gsec_common
. $HERE/gsec_common

# default config values
ROOT_DIR="`pwd`"
VERBOSE_OUTPUT=0
MODE="game"
COUNT=0
COUNT_START=0
MAX_ROUND=0
DATA_TAG="recent"
FPS=25
USE_LLI=0

usage()
{
  echo -e "$0\n\nUSAGE:"
  echo -e "\t-m [game|server|client|record|playback]\t(mode) default=game, starts server in background and client in record mode" 
  echo -e "\t-x number\t\t\t\t(number of client rounds)"
  echo -e "\t-c number\t\t\t\t(count of instances)"
  echo -e "\t-s number\t\t\t\t(count start (skip instances))"
  echo -e "\t-f number\t\t\t\t(xpilot frames per second (FPS))"
  echo -e "\t-o tag\t\t\t\t\t(name of record directory)"
  echo -e "\t-r dir\t\t\t\t\t(root directory)"
  echo -e "\t-l \t\t\t\t\t(use interpreter (lli) instead of native execution)"
  echo -e "\t-h \t\t\t\t\t(help/usage)"
}

#=============================================================================
# need to automatically set this var...
if test ! ${XPILOTHOST+defined}; then
  echo "ERROR: set XPILOTHOST environment variable before running client"
  usage
  exit
fi
#=============================================================================

while getopts ":vr:j:t:c:m:x:o:f:s:hl" opt; do
  case $opt in
    v)
      VERBOSE_OUTPUT=1
      ;;

    m)
      MODE="$OPTARG"
      ;;

    x)
      MAX_ROUND=$OPTARG
      ;;

    c)
      COUNT=$OPTARG
      ;;

    s)
      COUNT_START=$OPTARG
      ;;

    f)
      FPS=$OPTARG
      ;;
 
    o)
      DATA_TAG="$OPTARG"
      ;;
 
    r)
      echo "Setting root dir to $OPTARG"
      ROOT_DIR="$OPTARG"
      ;;
    h)
      usage
      exit
      ;;
    l)
      echo "Using lli interpreter instead of native code"
      ;;

    :)
      echo "Option -$OPTARG requires an argument"
      usage
      exit
      ;;

  esac
done

initialize_root_directories
initialize_logging $@

#BASE_DIR="$DATA_DIR/network/xpilot-$MODE"
BASE_DIR="$DATA_DIR/network/xpilot-ng-x11"

RECORD_DIR="$DATA_DIR/network/xpilot-record"

# record start time
start_time=$(elapsed_time)

#=============================================================================
# configuration parameters
#=============================================================================
SERVER_ADDRESS="localhost"
PLAYER_NAME="p1"
KTEST_SUFFIX="ktest"
GEOMETRY="800x600+100+100"
RECORD_FILE="input.rec"

#=============================================================================
# game client and server paths
#=============================================================================
SERVER_BIN="xpilot-ng-server"
SERVER_COMMAND="$XPILOT_ROOT/bin/$SERVER_BIN $SERVER_OPT "

CLIENT_BIN="xpilot-ng-x11"
CLIENT_OPT=" "
CLIENT_COMMAND="$XPILOT_ROOT/bin/$CLIENT_BIN $CLIENT_OPT "

if [ ${USE_LLI} -eq 1 ]; then
  CLIENT_BC="$XPILOT_ROOT/bin/$CLIENT_BIN-run-opt.bc"
  CLIENT_COMMAND="$XPILOT_ROOT/bin/lli -force-interpreter -load=/usr/lib/x86_64-linux-gnu/libX11.so $CLIENT_BC $CLIENT_OPT "
fi

#=============================================================================
# output paths
#=============================================================================

DATA_DIR=$BASE_DIR
KTEST_DIR=$DATA_DIR/$RUN_PREFIX

#=============================================================================
# Default options 
#=============================================================================
CLIENT_OPTIONS=""
CLIENT_OPTIONS+="-join -texturedWalls no -texturedDecor no -texturedObjects no "
CLIENT_OPTIONS+="-fullColor no -geometry $GEOMETRY "
CLIENT_OPTIONS+="-keyTurnLeft a -keyTurnRight d -keyThrust w "

if [[ $MAX_ROUND -gt 0 ]]; then
  CLIENT_OPTIONS+="-quitRound $MAX_ROUND "
fi

SERVER_OPTIONS=""
SERVER_OPTIONS+="-ktestFileName \"$KTEST_DIR/xpilot.ktest\" "
SERVER_OPTIONS+="-FPS $FPS "

#=============================================================================
# Xpilot execution
#=============================================================================

make_xpilot_dirs()
{
  mkdir -p $KTEST_DIR 
  rm $DATA_DIR/$DATA_TAG
  ln -sfT $DATA_DIR/$RUN_PREFIX $DATA_DIR/$DATA_TAG
  cd $KTEST_DIR
}

case "$MODE" in 
  game)
    make_xpilot_dirs
    for i in `seq $COUNT_START $COUNT` ; do

      SERVER_OPTIONS=""
      SERVER_OPTIONS+=" -ktestFileName \"$KTEST_DIR/xpilot_$i.ktest\" "
      SERVER_OPTIONS+="-FPS $FPS "
      while ! [[ `pgrep -f $SERVER_BIN` ]] 
      do
        echo "starting server in background..."
        echo "$SERVER_COMMAND $SERVER_OPTIONS &> /dev/null &"
        eval $SERVER_COMMAND $SERVER_OPTIONS &> /dev/null &
        sleep 5
      done

      echo "starting client..."
      echo "$CLIENT_COMMAND $CLIENT_OPTIONS $SERVER_ADDRESS"
      eval $CLIENT_COMMAND $CLIENT_OPTIONS $SERVER_ADDRESS
      sleep 5

      ## Commands below not needed because we now store timing data
      ## in the ktest file
      #mv $KTEST_DIR/net_server.log "$KTEST_DIR"/"xpilot_"$i"_server.log" ;
      #mv $KTEST_DIR/net_client.log "$KTEST_DIR"/"xpilot_"$i"_client.log" ;

      #grep -a MSGINFO "$KTEST_DIR"/"xpilot_"$i"_server.log" > "$KTEST_DIR"/"xpilot_"$i"_server_socket.log" ;
      #grep -a MSGINFO "$KTEST_DIR"/"xpilot_"$i"_client.log" > "$KTEST_DIR"/"xpilot_"$i"_client_socket.log" ;

      ## check socket log is correct length
      #LEN=$(wc -l "$KTEST_DIR"/"xpilot_"$i"_server_socket.log" | awk '{print $1}')
      #if [[ $LEN -lt $MAX_ROUND ]]; then
      #  echo "ERROR: $KTEST_DIR/xpilot_$i_server_socket.log has only $LEN entries"
      #  exit
      #fi

      #mv $KTEST_DIR/interleave "$KTEST_DIR"/"interleave_$i.log" ;

    done
    ;;
  server)
    make_xpilot_dirs
    leval $SERVER_COMMAND $SERVER_OPTIONS
    ;;
  client)
    make_xpilot_dirs
    leval $CLIENT_COMMAND -join $CLIENT_OPTIONS $SERVER_ADDRESS
    ;;
  record)
    make_xpilot_dirs
    CLIENT_OPTIONS+=" -recordInputFile $KTEST_DIR/$RECORD_FILE "
    leval $CLIENT_COMMAND -join $CLIENT_OPTIONS $SERVER_ADDRESS
    ;;
  playback)
    CLIENT_OPTIONS+=" -playInputFile $RECORD_DIR/$DATA_TAG/$RECORD_FILE "
    leval $CLIENT_COMMAND -join $CLIENT_OPTIONS $SERVER_ADDRESS
    ;;
esac

#cd -
leval xset r on


