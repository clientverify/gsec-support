#!/bin/bash

LSF_MEMORY_GB=48
#CLIENT_TYPES="tetrinet xpilot"
#CLIENT_TYPES="xpilot"
CLIENT_TYPES="tetrinet"
EDIT_DIST_TYPES="edit-dist-row edit-dist-kprefix-row edit-dist-kprefix-hash"
#KPREFIX_TYPES="edit-dist-kprefix-row edit-dist-kprefix-hash"
KPREFIX_TYPES="edit-dist-kprefix-row"
#KPREFIX_TYPES="edit-dist-kprefix-hash"
#KPREFIX_LENGTHS="256 512 1024 16384"
#KPREFIX_LENGTHS="2048"
#KPREFIX_LENGTHS="256 1024"
KPREFIX_LENGTHS="256"
#CLUSTER_SIZES="8 16 32 64 256 512 1024"
#CLUSTER_SIZES="64 256 4096"
CLUSTER_SIZES="4096"
MEDOID_COUNTS="4 8"

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

#for client in $CLIENT_TYPES; do
#  echo "Training -- Client: $client"
#  ./gsec-support/cliver.sh -f -t training -c $client -i lsf -m $LSF_MEMORY_GB -b $DATA_TAG
#done

# Wait until training is finished before we start running jobs
#sleep_until_jobs_finish

CLIENT_TYPES="tetrinet xpilot"

for edit_dist in $KPREFIX_TYPES; do

  for client in $CLIENT_TYPES; do
    echo "Verification(self): -- Client: $client"
    ./gsec-support/cliver.sh -f -t "self-$edit_dist" -o "self" -c $client -i lsf -m $LSF_MEMORY_GB -x " -use-self-training " -b $DATA_TAG 
  done

  for client in $CLIENT_TYPES; do
    echo "Verification(cluster): -- Client: $client"
    for k_length in $KPREFIX_LENGTHS; do
      for cluster_size in $CLUSTER_SIZES; do
        for max_medoid_count in $MEDOID_COUNTS; do
          echo "K = $k_length, edit dist = $edit_dist, cluster size = $cluster_size "
          ./gsec-support/cliver.sh -f -t "check-$edit_dist" -o "ch-$cluster_size-$k_length-$max_medoid_count" -c $client -i lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -use-clustering-hint -cluster-size=$cluster_size -max-medoids=$max_medoid_count " -b $DATA_TAG
          ./gsec-support/cliver.sh -f -t "ncross-$edit_dist" -o "nc-$cluster_size-$k_length-$max_medoid_count" -c $client -i lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -use-clustering      -cluster-size=$cluster_size -max-medoids=$max_medoid_count " -b $DATA_TAG
        done
      done
    done
  done
done

for client in $CLIENT_TYPES; do
  echo "Client: $client"
  ./gsec-support/cliver.sh -f -t naive -o "naive" -c $client -i lsf -m $LSF_MEMORY_GB -b $DATA_TAG -x " -search-mode=pq "
  #./gsec-support/cliver.sh -t naive -o "random" -c $client -i lsf -m $LSF_MEMORY_GB -b $DATA_TAG -x " -disable-et-tree=1 -search-mode=random "
done

