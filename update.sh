#!/bin/zsh 
setopt extendedglob
. ${0:h}/include_config.sh

local M=$1
[[ -z $M ]] && { echo "Pls give machine name"; exit 1 }

upgrade_systemdrun_interactive() {
	systemd-run -M "${c:t}"  --wait --pty /usr/bin/apt update && \
	systemd-run -M "${c:t}"  --wait --pty /usr/bin/apt upgrade --no-install-recommends --yes
}

upgrade_systemdrun() {
	systemd-run -M "${c:t}" --setenv=DEBIAN_FRONTEND=noninteractive --wait --pty /usr/bin/apt-get update && \
	systemd-run -M "${c:t}" --setenv=DEBIAN_FRONTEND=noninteractive --wait --pty /usr/bin/apt-get upgrade --no-install-recommends --yes
}

update_chroot() {
	export DEBIAN_FRONTEND=noninteractive
	chroot "${c}" apt-get update && \
	chroot "${c}" apt-get upgrade --no-install-recommends --yes

}

update_chroot_interactive() {
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
	echo "rsync -van ${CONFIGDIR}$1/ ${PATH_CONTAINER}$1/"
	echo
	rsync -van ${CONFIGDIR}$1/ ${PATH_CONTAINER}$1/ | less
	for f (${CONFIGDIR}$1/**/*(.N)) { diff -qu "$f" "${f:s%${CONFIGDIR}%${PATH_CONTAINER}%}" || { diff -u "$f" "${f:s%${CONFIGDIR}%${PATH_CONTAINER}%}" | less ; echo "Save new ${f:t}?" && cp -vi "${f:s%${CONFIGDIR}%${PATH_CONTAINER}%}" "$f" }}
}

checkfordpkgconfigupdates() {
	for f (${PATH_CONTAINER}$1/**/*.dpkg-*(.N)) vimdiff -u "${f:r}" "${f}" && rm -vi "${f}"
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

for c in ${PATH_CONTAINER}$M; do
        echo "apt-get upgrading $c"
        zfs snapshot ${ZFS_CONTAINERS}${c:t}@$(date +"preupgrade-%s")
        { upgrade_systemdrun_interactive || update_chroot_interactive } && \
	checkfordpkgconfigupdates && \
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

