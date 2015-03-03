#!/bin/bash

# Snapshot and clean the following list of directories:
# build, gsec-support, local, src

# If data/logs/update_recent.log exists, then move the current
# directories into a "snapshot" with the same timestamp as the directory
# pointed to by update_recent.log.  Otherwise, just delete the directories.

logsymlink="data/logs/update_recent.log"
snaproot="data/snapshots"
regex="update_(.*).log"

if [[ -L "$logsymlink" ]]
then
    logfilename=$(readlink "$logsymlink")
    echo $logfilename
    [[ "$logfilename" =~ $regex ]]
    timestamp="${BASH_REMATCH[1]}"
    echo "Detected log symlink: ${logsymlink}"
    echo "Symlink dereference:  ${logfilename}"
    snapdir="${snaproot}/snapshot_${timestamp}"

    echo "Moving directories to snapshot: ${snapdir}"
    mkdir -p "${snapdir}"
    mv -v build gsec-support local src "${snapdir}/"
else
    echo "No symlink detected at ${logsymlink}"
    echo "Removing directories without taking a snapshot."
    echo "rm -rf build gsec-support local src"
    rm -rf build gsec-support local src
fi
