#!/bin/zsh 
setopt extendedglob
. ${0:h}/include_config.sh

upgrade_systemdrun() {
	systemd-run -M "${c:t}" --setenv=DEBIAN_FRONTEND=noninteractive --wait --pty /usr/bin/apt-get update && \
	systemd-run -M "${c:t}" --setenv=DEBIAN_FRONTEND=noninteractive --wait --pty /usr/bin/apt-get upgrade --no-install-recommends --yes
}

update_chroot() {
	export DEBIAN_FRONTEND=noninteractive
	chroot "${c}" apt-get update && \
	chroot "${c}" apt-get upgrade --no-install-recommends --yes

}

REBOOTLATER=()

deleteoldsnapshots() {
        for s in $(zfs list -t snapshot -o name | grep preupgrade); do zfs destroy "$s"; done
}

rememberforrestart() {
        systemctl is-active systemd-nspawn@${1}.service && \
        machinectl poweroff ${1} && REBOOTLATER+=(${1})

}

checkforconfigchanges() {
	for f (${CONFIGDIR}$1/**/*(.)) echo "$f" "${f:s%${CONFIGDIR}%${PATH_CONTAINER}/%}"
}

restartmachines() {
	for r in "$REBOOTLATER[@]"; do
        	while systemctl is-active systemd-nspawn@${r}.service; do 
			echo "!!! ${r} still running, terminating..."
			machinectl terminate ${r}
			sleep 4
		done
		zfs snapshot ${ZFS_CONTAINERS}${r}@$(date +"%Y-%m-%d")
		machinectl start ${r} 
	done
}

deleteoldsnapshots
for c in ${PATH_CONTAINER}*~${PATH_CONTAINER}base-*~${PATH_CONTAINER}*.old*(/); do
	echo
        echo "apt-get upgrading $c"
	echo
        zfs snapshot ${ZFS_CONTAINERS}${c:t}@$(date +"preupgrade-%s")
        { upgrade_systemdrun || update_chroot } && \
        rememberforrestart ${c:t}
	echo "---- listing diff to possible config changes ----"
	checkforconfigchanges ${c:t}
done

sleep 15
restartmachines
echo "------------------------------------------------------"
echo "Stuff that should be running:"
print -l $REBOOTLATER
echo "------------------------------------------------------"
echo ""
echo ""
echo ""
sleep 2
echo "------------------------------------------------------"
echo "Stuff that is running:"
machinectl
echo "------------------------------------------------------"

