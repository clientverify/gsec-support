#!/bin/bash

slavedir="/playpen/buildbot/slave"
backupdir="/playpen/buildbot/slave/manual_backups"
builddirs="cve_2015_0205 debug fakepadding hmm "
builddirs+="parallel parallel-e parallel-ef parallel-games release"

datestr=$(date '+%Y%m%d')

cd "${slavedir}"
for f in ${builddirs}
do
    echo "Backing up ${slavedir}/$f/data to ${backupdir}"
    cd "$f"
    tar -czf "${backupdir}/${f}_datadir_${datestr}.tar.gz" data
    cd ..
done
