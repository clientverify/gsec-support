#!/bin/bash
#=============================================================================
# run.sh: batch script to generate ktest files from game client and to verify
# ktest files with nuklear
#=============================================================================

#=============================================================================

WRAPPER="`readlink -f "$0"`"
HERE="`dirname "$WRAPPER"`"

# Include gsec_common
. $HERE/gsec_common

ROOT_DIR="`pwd`"

# default config values
MODE="enumerate"
COUNT=0

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

BASE_DIR="$DATA_DIR/network/tetrinet"

# record start time
start_time=$(elapsed_time)

#=============================================================================
# configuration parameters
#=============================================================================
SERVER_ADDRESS="localhost"
PLAYER_NAME="p1"
KTEST_SUFFIX="ktest"
RECENT_LINK="last-run"

#PTYPE_VALUES=`seq 1 6`
PTYPE_VALUES=`seq 1`
#RATE_VALUES=`echo 1; seq 2 2 10`
RATE_VALUES=`echo 1`

MAX_ROUND=50
INPUT_GEN_TYPE=0

#=============================================================================
# game client and server paths
#=============================================================================
SERVER_BIN="tetrinet-server"
SERVER_OPT=" "
SERVER_COMMAND="$TETRINET_ROOT/bin/$SERVER_BIN $SERVER_OPT "

CLIENT_BIN="tetrinet-ktest"
CLIENT_OPT=" "
CLIENT_COMMAND="$TETRINET_ROOT/bin/$CLIENT_BIN $CLIENT_OPT "

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
# script path
#=============================================================================
SCRIPTS_ROOT=$BASE_DIR
SCRIPT=$SCRIPTS_ROOT"/run-nuklear.sh "
TMP_SCRIPT="/tmp/$RANDOM.sh"
cp $SCRIPT $TMP_SCRIPT
chmod +x $TMP_SCRIPT
SCRIPT=$TMP_SCRIPT

#=============================================================================
# enumerate all possible input moves with no simulated losses
#=============================================================================
if [[ $MODE == "enumerate" ]]
then
  echo "enumerating all possible input moves with no simulated losses"

  mkdir -p $LOG_DIR $KTEST_DIR 

  rm $DATA_DIR/$RECENT_LINK
  ln -sfT $DATA_DIR/$RUN_PREFIX $DATA_DIR/$RECENT_LINK

  INPUT_GEN_TYPE=2

  for ptype in $PTYPE_VALUES
  do
    for rate in $RATE_VALUES
    do 
      for i in `seq 0 $COUNT`
      do
        zpad_ptype=`printf "%02d" $ptype`
        zpad_rate=`printf "%02d" $rate`
        zpad_i=`printf "%02d" $i`
        #DESC="tetrinet_enumerate_inputs_"$zpad_i"_type-"$ptype"_rate-"$zpad_rate
        DESC=$MODE"_"$i"_"$INPUT_GEN_TYPE"_"$ptype"_"$rate"_"$MAX_ROUND"_"$PLAYER_NAME"_"$SERVER_ADDRESS
        KTEST_FILE=$KTEST_DIR/$DESC"."$KTEST_SUFFIX

        while ! [ -e $KTEST_FILE ] 
        do
          while ! [[ `pgrep $SERVER_BIN` ]] 
          do
            echo "starting server in background..."
            echo "$SERVER_COMMAND &> /dev/null &"
            exec $SERVER_COMMAND &> /dev/null &
            sleep 1
          done

          echo "creating $KTEST_FILE"
          OPTS=" -inputgenerationtype $INPUT_GEN_TYPE "
          #OPTS+="-maxround $MAX_ROUND "
          OPTS+="-log $LOG_DIR/$DESC.log -ktest $KTEST_FILE "
          OPTS+="-random -seed $i "
          OPTS+="-autostart -partialtype $ptype -partialrate $rate "
          OPTS+="-startingheight $i "
          #OPTS+="-slowmode "
          OPTS+="$PLAYER_NAME $SERVER_ADDRESS "

          echo "executing $CLIENT_COMMAND $OPTS"
          $CLIENT_COMMAND $OPTS

          echo "exiting. now killing server process. "
          pkill $SERVER_BIN
          sleep 1
        done
      done
    done
  done
else
  echo "not running game client"
fi

#=============================================================================
# generate ktest files from game client
#=============================================================================
if [[ $MODE == "game" || $MODE == "all" ]]
then
  echo "running game client"

  mkdir -p $LOG_DIR $KTEST_DIR 

  rm $DATA_DIR/$RECENT_LINK
  ln -sfT $DATA_DIR/$RUN_PREFIX $DATA_DIR/$RECENT_LINK

  for ptype in $PTYPE_VALUES
  do
    for rate in $RATE_VALUES
    do 
      for i in `seq 0 $COUNT`
      do
        zpad_ptype=`printf "%02d" $ptype`
        zpad_rate=`printf "%02d" $rate`
        zpad_i=`printf "%02d" $i`
        #DESC="tetrinet_"$zpad_i"_type-"$ptype"_rate-"$zpad_rate
        DESC=$MODE"_"$i"_"$INPUT_GEN_TYPE"_"$ptype"_"$rate"_"$MAX_ROUND"_"$PLAYER_NAME"_"$SERVER_ADDRESS
        KTEST_FILE=$KTEST_DIR/$DESC"."$KTEST_SUFFIX

        while ! [ -e $KTEST_FILE ] 
        do
          while ! [[ `pgrep $SERVER_BIN` ]] 
          do
            echo "starting server in background..."
            echo "$SERVER_COMMAND &> /dev/null &"
            exec $SERVER_COMMAND &> /dev/null &
            sleep 1
          done

          echo "creating $KTEST_FILE"

          OPTS=""
          OPTS+="-inputgenerationtype $INPUT_GEN_TYPE "
          OPTS+="-maxround $MAX_ROUND "
          OPTS+="-log $LOG_DIR/$DESC.log -ktest $KTEST_FILE "
          OPTS+="-random -seed $i "
          OPTS+="-autostart -partialtype $ptype -partialrate $rate "
          OPTS+="$PLAYER_NAME $SERVER_ADDRESS "

          echo "executing $CLIENT_COMMAND $OPTS"
          $CLIENT_COMMAND $OPTS 

          echo "exiting. now killing server process. "
          pkill $SERVER_BIN
          sleep 1
        done
      done
    done
  done
else
  echo "not running game client"
fi

#=============================================================================
# user mode
#=============================================================================
if [[ $MODE == "user" ]]
then

  mkdir -p $LOG_DIR $KTEST_DIR 

  rm $DATA_DIR/$RECENT_LINK
  ln -sfT $DATA_DIR/$RUN_PREFIX $DATA_DIR/$RECENT_LINK

  for ptype in $PTYPE_VALUES
  do
    for rate in $RATE_VALUES
    do 
      for i in `seq 0 $COUNT`
      do
        zpad_ptype=`printf "%02d" $ptype`
        zpad_rate=`printf "%02d" $rate`
        zpad_i=`printf "%02d" $i`
        #DESC="tetrinet_"$zpad_i"_type-"$ptype"_rate-"$zpad_rate
        DESC=$MODE"_"$i"_"$INPUT_GEN_TYPE"_"$ptype"_"$rate"_"$MAX_ROUND"_"$PLAYER_NAME"_"$SERVER_ADDRESS
        KTEST_FILE=$KTEST_DIR/$DESC"."$KTEST_SUFFIX

        while ! [ -e $KTEST_FILE ] 
        do
          while ! [[ `pgrep $SERVER_BIN` ]] 
          do
            echo "starting server in background..."
            echo "$SERVER_COMMAND &> /dev/null &"
            exec $SERVER_COMMAND &> /dev/null &
            sleep 1
          done

          echo "creating $KTEST_FILE"

          OPTS=" -inputgenerationtype $INPUT_GEN_TYPE "
          OPTS+="-maxround $MAX_ROUND "
          OPTS+="-log $LOG_DIR/$DESC.log -ktest $KTEST_FILE "
          #OPTS+="-random -seed $i -slowmode"
          OPTS+=" -autostart -partialtype $ptype -partialrate $rate"
          OPTS+=" $PLAYER_NAME $SERVER_ADDRESS "

          echo "executing $CLIENT_COMMAND $OPTS"
          $CLIENT_COMMAND $OPTS

          echo "exiting. now killing server process. "
          pkill $SERVER_BIN
          sleep 1
        done
      done
    done
  done
else
  echo "not running game client"
fi


#=============================================================================
# verify ktest files
#=============================================================================
if [[ $MODE == "test" || $MODE == "all" ]]
then
  echo "running test"

  if [[ $MODE != "all" ]] ; then
    KTEST_DIR=$DATA_DIR/$RECENT_LINK/ktest
  fi

  mkdir -p $OUT_DIR

  rm $RESULTS_DIR/$RECENT_LINK
  ln -sf $OUT_DIR $RESULTS_DIR/$RECENT_LINK

  for ptype in $PTYPE_VALUES
  do
    for rate in $RATE_VALUES
    do 
      for i in `seq 1 $COUNT`
      do
        zpad_ptype=`printf "%02d" $ptype`
        zpad_rate=`printf "%02d" $rate`
        zpad_i=`printf "%02d" $i`
        DESC="tetrinet_"$zpad_i"_type-"$ptype"_rate-"$zpad_rate
        KTEST_FILE=$KTEST_DIR/$DESC"."$KTEST_SUFFIX

        OPTS=" -autostart -partialtype $ptype -partialrate $rate"
        OPTS+=" $PLAYER_NAME $SERVER_ADDRESS "

        echo "verifying $KTEST_FILE"
        bash $SCRIPT release $KTEST_FILE $DESC $OUT_DIR "$OPTS" &
        sleep 1
      done

      echo "waiting for $COUNT jobs to finish"
      wait
    done
  done
else
  echo "not running test"
fi
#=============================================================================
#=============================================================================

echo "Elapsed time: $(elapsed_time $start_time)"

