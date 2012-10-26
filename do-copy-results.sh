#!/bin/bash

BASE_DIR=$PWD/data
DEST_HOST="rac@kudzoo.cs.unc.edu"
DEST_DIR="/home/rac/research/test.gsec/results.oakall"

KPREFIX_LENGTHS="64 256 "
CLUSTER_SIZES="8 16 32 256 512 1024"

for k_length in $KPREFIX_LENGTHS; do
  for cluster_size in $CLUSTER_SIZES; do
    echo "K = $k_length, edit dist = $edit_dist, cluster size = $cluster_size "
    ./gsec-support/copy_results.sh -b large -d $DEST_HOST:$DEST_DIR -s $BASE_DIR/self-$k_length-$cluster_size
    ./gsec-support/copy_results.sh -b large -d $DEST_HOST:$DEST_DIR -s $BASE_DIR/ch-$k_length-$cluster_size
    ./gsec-support/copy_results.sh -b large -d $DEST_HOST:$DEST_DIR -s $BASE_DIR/nc-$k_length-$cluster_size
  done
done


