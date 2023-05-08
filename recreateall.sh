#!/bin/zsh
. ${0:h}/include_config.sh

export DEBIAN_FRONTEND=noninteractive
for c in ${PATH_CONTAINER}*~${PATH_CONTAINER}base-*(/); do
	systemctl is-active systemd-nspawn@{c:t}.service
	local ISACTIVE=$?
	systemctl is-enabled systemd-nspawn@{c:t}.service
	local ISENABLED=$?
	machinectl stop ${c:t}
	sleep 2
	machinectl terminale ${c:t}
	zfs destroy -r ${ZFS_CONTAINERS}bak_${c:t}
	zfs rename ${ZFS_CONTAINERS}${c:t} ${ZFS_CONTAINERS}bak_${c:t}
	./create_${c:t}.sh && [[ $ISACTIVE -eq 0 ]] \
	&& machinectl start ${c:t} \
	&& machinectl status ${c:t}
	[[ $ISENABLED -eq 0 ]] && systemctl enable systemd-nspawn@${c:t}.service || systemctl disable systemd-nspawn@${c:t}.service
done
