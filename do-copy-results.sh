#!/bin/bash

SCRIPT=./gsec-support/verify_and_copy.sh
BASE_DIR=$PWD/data
DEST_HOST="rac@kudzoo.cs.unc.edu"
DEST_DIR="/home/rac/research/test.gsec/results/"
TRAINING_DIR="data/training"

#KPREFIX_LENGTHS="8 16 64 128 256"
KPREFIX_LENGTHS="64"
#KPREFIX_LENGTHS="16"
#CLUSTER_SIZES="4096"
CLUSTER_SIZES="256 65536"
#MEDOID_COUNTS="4 8 16"
#MEDOID_COUNTS="8 16"
MEDOID_COUNTS="8"
DATA_TAG="NDSS2013"

#for k_length in $KPREFIX_LENGTHS; do
#  for cluster_size in $CLUSTER_SIZES; do
#    echo "K = $k_length, edit dist = $edit_dist, cluster size = $cluster_size "
#    ./gsec-support/copy_results.sh -b large -d $DEST_HOST:$DEST_DIR -s $BASE_DIR/self-$k_length-$cluster_size
#    ./gsec-support/copy_results.sh -b large -d $DEST_HOST:$DEST_DIR -s $BASE_DIR/ch-$k_length-$cluster_size
#    ./gsec-support/copy_results.sh -b large -d $DEST_HOST:$DEST_DIR -s $BASE_DIR/nc-$k_length-$cluster_size
#  done
#done

#echo "Copying results from self verification"
#eval $SCRIPT -b $DATA_TAG -d $DEST_HOST:$DEST_DIR -v $TRAINING_DIR -s $BASE_DIR/self
#eval $SCRIPT -b $DATA_TAG -d $DEST_HOST:$DEST_DIR -v $TRAINING_DIR -s $BASE_DIR/self-t

#echo "Copying results from naive verification"
#eval $SCRIPT -b $DATA_TAG -d $DEST_HOST:$DEST_DIR -v $TRAINING_DIR -s $BASE_DIR/naive
#eval $SCRIPT -b $DATA_TAG -d $DEST_HOST:$DEST_DIR -v $TRAINING_DIR -s $BASE_DIR/naive-t

for k_length in $KPREFIX_LENGTHS; do
  for cluster_size in $CLUSTER_SIZES; do
    eval $SCRIPT -b $DATA_TAG -d $DEST_HOST:$DEST_DIR -v $TRAINING_DIR -s $BASE_DIR/hint-$cluster_size-$k_length
    eval $SCRIPT -b $DATA_TAG -d $DEST_HOST:$DEST_DIR -v $TRAINING_DIR -s $BASE_DIR/hint-$cluster_size-$k_length-t
    for max_medoid_count in $MEDOID_COUNTS; do
      eval $SCRIPT -b $DATA_TAG -d $DEST_HOST:$DEST_DIR -v $TRAINING_DIR -s $BASE_DIR/msg-$cluster_size-$k_length-$max_medoid_count
      eval $SCRIPT -b $DATA_TAG -d $DEST_HOST:$DEST_DIR -v $TRAINING_DIR -s $BASE_DIR/msg-$cluster_size-$k_length-$max_medoid_count-t
      #eval $SCRIPT -b $DATA_TAG -d $DEST_HOST:$DEST_DIR -v $TRAINING_DIR -s $BASE_DIR/msg+hint-$cluster_size-$k_length-$max_medoid_count
      #eval $SCRIPT -b $DATA_TAG -d $DEST_HOST:$DEST_DIR -v $TRAINING_DIR -s $BASE_DIR/msg+hint-$cluster_size-$k_length-$max_medoid_count-t
    done
  done
done

 
