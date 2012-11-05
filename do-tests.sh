#!/bin/bash

LSF_MEMORY_GB=48
#CLIENT_TYPES="xpilot tetrinet"
#CLIENT_TYPES="xpilot"
CLIENT_TYPES="tetrinet"
EDIT_DIST_TYPES="edit-dist-row edit-dist-kprefix-row edit-dist-kprefix-hash"
#KPREFIX_TYPES="edit-dist-kprefix-row edit-dist-kprefix-hash"
KPREFIX_TYPES="edit-dist-kprefix-row"
#KPREFIX_TYPES="edit-dist-kprefix-hash"
#KPREFIX_LENGTHS="256 512 1024 16384"
#KPREFIX_LENGTHS="2048"
KPREFIX_LENGTHS="64"
#CLUSTER_SIZES="8 16 32 64 256 512 1024"
CLUSTER_SIZES="64 256 4096"

DATA_TAG="large"

#=======================================================================

sleep_until_jobs_finish()
{
  STATUS=$( { bjobs; } 2>&1 )
  while [ "$STATUS" != "No unfinished job found" ]; do
    STATUS=$( { bjobs; } 2>&1 )
    sleep 60
  done
}

#=======================================================================

for client in $CLIENT_TYPES; do
  echo "Training -- Client: $client"
  ./gsec-support/cliver.sh -t training -c $client -i lsf -m $LSF_MEMORY_GB -b $DATA_TAG -d 1
done

# Wait until training is finished before we start running jobs
sleep_until_jobs_finish

for client in $CLIENT_TYPES; do
  echo "Verification: -- Client: $client"

  # DEBUG TESTING
  for edit_dist in $KPREFIX_TYPES; do
    for k_length in $KPREFIX_LENGTHS; do

      ./gsec-support/cliver.sh  -t "self-$edit_dist" -o "self" -c $client -i lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -use-clustering-hint -cluster-size=2147483648 " -b $DATA_TAG

      for cluster_size in $CLUSTER_SIZES; do
        echo "K = $k_length, edit dist = $edit_dist, cluster size = $cluster_size "
        ./gsec-support/cliver.sh  -t "check-$edit_dist" -o "ch-$cluster_size" -c $client -i lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -use-clustering-hint -cluster-size=$cluster_size " -b $DATA_TAG
        ./gsec-support/cliver.sh  -t "ncross-$edit_dist" -o "nc-$cluster_size" -c $client -i lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -use-clustering      -cluster-size=$cluster_size " -b $DATA_TAG
      done

      #./gsec-support/cliver.sh  -t "ncross-$edit_dist" -o "nc-$k_length-$edit_dist"    -c $client -i interactive -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -filter-training-usage=1 " -b $DATA_TAG

      #./gsec-support/cliver.sh  -t "ncross-$edit_dist" -o "nc-$k_length-$edit_dist-an"    -c $client -i lsf -m $LSF_MEMORY_GB -x " -aggressive-naive=1 -max-k-extension=$k_length -filter-training-usage=1 " -b $DATA_TAG
      #./gsec-support/cliver.sh  -t "ncross-$edit_dist" -o "nc-$k_length-$edit_dist-f1"    -c $client -i lsf -m $LSF_MEMORY_GB -x " -medoid-count=1 -max-k-extension=$k_length -filter-training-usage=1 " -b $DATA_TAG
      #./gsec-support/cliver.sh  -t "ncross-$edit_dist" -o "nc-$k_length-$edit_dist-f2"    -c $client -i lsf -m $LSF_MEMORY_GB -x " -medoid-count=2 -max-k-extension=$k_length -filter-training-usage=1 " -b $DATA_TAG
      #./gsec-support/cliver.sh -t "ncross-$edit_dist" -o "nc-$k_length-$edit_dist"      -c $client -i lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length " -b $DATA_TAG
      #./gsec-support/cliver.sh -t "verify-$edit_dist" -o "v-$k_length-$edit_dist"       -c $client -i lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length " -b $DATA_TAG
      #./gsec-support/cliver.sh -d 1 -t "check-$edit_dist"  -o "ch-$k_length-$edit_dist"      -c $client -i lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length " -b $DATA_TAG
      #./gsec-support/cliver.sh -t "ncross-$edit_dist" -o "nc-$k_length-$edit_dist-full" -c $client -i lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -edit-distance-at-clone-only=0 "
      #./gsec-support/cliver.sh -t "check-$edit_dist"  -o "ch-$k_length-$edit_dist-full" -c $client -i lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -edit-distance-at-clone-only=0 "
    done
  done

  #./gsec-support/cliver.sh -t naive -c $client -i lsf -m $LSF_MEMORY_GB -b $DATA_TAG

  # SELF TEST
  ##for edit_dist in $EDIT_DIST_TYPES; do
  #for edit_dist in $KPREFIX_TYPES; do
  #  ./gsec-support/cliver.sh -t self-$edit_dist -o self-$edit_dist -c $client -i lsf -m $LSF_MEMORY_GB -b $DATA_TAG
  #done

  #for edit_dist in $EDIT_DIST_TYPES; do
  #  ./gsec-support/cliver.sh -t all-$edit_dist -c $client -i lsf -m $LSF_MEMORY_GB
  #done
done

#LSF_MEMORY_GB=64

for client in $CLIENT_TYPES; do
  echo "Client: $client"
  #./gsec-support/cliver.sh -t naive -o "random" -c $client -i lsf -m $LSF_MEMORY_GB -b $DATA_TAG -x " -disable-et-tree=1 -search-mode=random "
done

