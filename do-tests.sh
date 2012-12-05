#!/bin/bash

LSF_MEMORY_GB=24
DATA_TAG="NDSS2013"

#=======================================================================

# Wait until training is finished before we start running jobs
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
  local socket_event_cluster_sizes=$5

  local edit_dist="edit-dist-kprefix-row"

  echo "run_tests: {$client_types}, kprefix at {$kprefix_lengths}, clusters at {$cluster_sizes}, medoids at {$medoid_counts}"

  for client in $client_types; do
    #./gsec-support/cliver.sh -b $DATA_TAG -i lsf -m $LSF_MEMORY_GB -c $client -f \
    #    -t "self-$edit_dist" -o "self" \
    #    -x " -use-self-training "

    for k_length in $kprefix_lengths; do

      for c_size in $cluster_sizes; do
        for se_c_size in $socket_event_cluster_sizes; do

          ./gsec-support/cliver.sh -b $DATA_TAG -i threaded-lsf -m $LSF_MEMORY_GB -c $client -f \
              -t "check-$edit_dist" -o "hint-$c_size-$k_length" \
              -x "-use-clustering-hint -max-k-extension=$k_length -cluster-size=$c_size -socket-event-cluster-size=$se_c_size "

          for m_count in $medoid_counts; do

            ./gsec-support/cliver.sh -b $DATA_TAG -i threaded-lsf -m $LSF_MEMORY_GB -c $client -f \
                -t "ncross-$edit_dist" -o "msg-$c_size-$k_length-$m_count" \
                -x "-use-clustering -max-k-extension=$k_length -cluster-size=$c_size -socket-event-cluster-size=$se_c_size -max-medoids=$m_count "

            #./gsec-support/cliver.sh -b $DATA_TAG -i threaded-lsf -m $LSF_MEMORY_GB -c $client -f \
            #    -t "ncross-$edit_dist" -o "msg+hint-$c_size-$k_length-$m_count" \
            #    -x "-use-clustering-all -max-k-extension=$k_length -cluster-size=$c_size -socket-event-cluster-size=$se_c_size -max-medoids=$m_count "

          done
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
  local socket_event_cluster_sizes=$5

  local edit_dist="edit-dist-kprefix-row"

  echo "run_tests_timing {$client_types}, kprefix at {$kprefix_lengths}, clusters at {$cluster_sizes}, medoids at {$medoid_counts}"

  for client in $client_types; do
    #./gsec-support/cliver.sh -b $DATA_TAG -i lsf -m $LSF_MEMORY_GB -c $client \
    #    -t "self-$edit_dist" -o "self-t" \
    #    -x " -use-self-training "

    for k_length in $kprefix_lengths; do

      for c_size in $cluster_sizes; do
        for se_c_size in $socket_event_cluster_sizes; do

          ./gsec-support/cliver.sh -b $DATA_TAG -i threaded-lsf -m $LSF_MEMORY_GB -c $client \
              -t "check-$edit_dist" -o "hint-$c_size-$k_length-t" \
              -x "-use-clustering-hint -max-k-extension=$k_length -cluster-size=$c_size -socket-event-cluster-size=$se_c_size "

          for m_count in $medoid_counts; do

            ./gsec-support/cliver.sh -b $DATA_TAG -i threaded-lsf -m $LSF_MEMORY_GB -c $client \
                -t "ncross-$edit_dist" -o "msg-$c_size-$k_length-$m_count-t" \
                -x "-use-clustering -max-k-extension=$k_length -cluster-size=$c_size -socket-event-cluster-size=$se_c_size -max-medoids=$m_count "

            #./gsec-support/cliver.sh -b $DATA_TAG -i threaded-lsf -m $LSF_MEMORY_GB -c $client \
            #    -t "ncross-$edit_dist" -o "msg+hint-$c_size-$k_length-$m_count-t" \
            #    -x "-use-clustering-all -max-k-extension=$k_length -cluster-size=$c_size -socket-event-cluster-size=$se_c_size -max-medoids=$m_count "

          done
        done
      done
    done
  done
}

#=======================================================================
#=======================================================================

run_training "xpilot tetrinet"

sleep_until_jobs_finish

run_tests "xpilot tetrinet" "64" "256 65536" "8" "10"

sleep_until_jobs_finish

run_tests_timing "xpilot tetrinet" "64" "256 65536" "8" "10"

