#!/bin/bash

LSF_MEMORY_GB=24
DATA_TAG="large-extra"

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

run_training()
{
  local client_types=$1
  echo "run_training {$client_types}"
  for client in $client_types; do
    ./gsec-support/cliver.sh -f -t training -c $client -i threaded-lsf -m $LSF_MEMORY_GB -b $DATA_TAG
  done
}

#=======================================================================

run_tests()
{
  local client_types=$1
  local kprefix_lengths=$2
  local cluster_sizes=$3
  local medoid_counts=$4

  local edit_dist="edit-dist-kprefix-row"

  echo "run_tests: {$client_types}, kprefix at {$kprefix_lengths}, clusters at {$cluster_sizes}, medoids at {$medoid_counts}"

  for client in $client_types; do
    #./gsec-support/cliver.sh -f -t "self-$edit_dist" -o "self" -c $client -i lsf -m $LSF_MEMORY_GB -x " -use-self-training " -b $DATA_TAG 

    for k_length in $kprefix_lengths; do
      for cluster_size in $cluster_sizes; do
        ./gsec-support/cliver.sh -f -t "check-$edit_dist" -o "hint-$cluster_size-$k_length" -c $client -i threaded-lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -use-clustering-hint -cluster-size=$cluster_size " -b $DATA_TAG
        for max_medoid_count in $medoid_counts; do
          ./gsec-support/cliver.sh -f -t "ncross-$edit_dist" -o "msg-$cluster_size-$k_length-$max_medoid_count" -c $client -i threaded-lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -use-clustering -cluster-size=$cluster_size -max-medoids=$max_medoid_count " -b $DATA_TAG
          ./gsec-support/cliver.sh -f -t "ncross-$edit_dist" -o "msg+hint-$cluster_size-$k_length-$max_medoid_count" -c $client -i threaded-lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -use-clustering-all -cluster-size=$cluster_size -max-medoids=$max_medoid_count " -b $DATA_TAG
        done
      done
    done
  done
}

#=======================================================================

run_tests_timing()
{
  local client_types=$1
  local kprefix_lengths=$2
  local cluster_sizes=$3
  local medoid_counts=$4

  local edit_dist="edit-dist-kprefix-row"

  echo "run_tests_timing {$client_types}, kprefix at {$kprefix_lengths}, clusters at {$cluster_sizes}, medoids at {$medoid_counts}"

  for client in $client_types; do
    #./gsec-support/cliver.sh -t "self-$edit_dist" -o "self-t" -c $client -i lsf -m $LSF_MEMORY_GB -x " -use-self-training " -b $DATA_TAG 

    for k_length in $kprefix_lengths; do
      for cluster_size in $cluster_sizes; do
        #./gsec-support/cliver.sh -t "check-$edit_dist" -o "hint-$cluster_size-$k_length-t" -c $client -i threaded-lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -use-clustering-hint -cluster-size=$cluster_size " -b $DATA_TAG
        for max_medoid_count in $medoid_counts; do
          ./gsec-support/cliver.sh -t "ncross-$edit_dist" -o "msg-$cluster_size-$k_length-$max_medoid_count-t" -c $client -i threaded-lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -use-clustering -cluster-size=$cluster_size -max-medoids=$max_medoid_count " -b $DATA_TAG
          #./gsec-support/cliver.sh -t "ncross-$edit_dist" -o "msg+hint-$cluster_size-$k_length-$max_medoid_count-t" -c $client -i threaded-lsf -m $LSF_MEMORY_GB -x " -max-k-extension=$k_length -use-clustering-all -cluster-size=$cluster_size -max-medoids=$max_medoid_count " -b $DATA_TAG
        done
      done
    done
  done
}

#=======================================================================
#=======================================================================

#run_training "xpilot tetrinet"

# Wait until training is finished before we start running jobs
sleep_until_jobs_finish

run_tests "xpilot tetrinet" "64" "256" "8"

#run_tests_timing "xpilot" "64" "65536" "8"

#run_tests "xpilot tetrinet" "64" "65536" "8 16"

