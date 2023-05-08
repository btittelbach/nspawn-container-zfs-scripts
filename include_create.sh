#!/bin/zsh

## include number of allowed open files, so we don't run into problems with systemd-run because e.g. jira goobled up all allowed handles
ulimit -n $(($(ulimit -n)+256))

[[ -z ${CONTAINER_NAME} ]] && exit 1
CONTAINER_CREATE_NAME=${CONTAINER_NAME}-new
CONTAINER_CREATE_ROOT=${PATH_CONTAINER}${CONTAINER_CREATE_NAME}
CONTAINER_CREATE_ZFS=${ZFS_CONTAINERS}${CONTAINER_CREATE_NAME}



systemctl is-active systemd-nspawn@${CONTAINER_CREATE_NAME}.service && {print "ERROR: Temporary Container is running!!! stop with systemctl stop systemd-nspawn@${CONTAINER_CREATE_NAME}.service"; exit 1}
[[ -n ${CREATEMIRROR_USER} ]] && for SCUUID (${CREATEMIRROR_USER}) { id $SCUUID &>/dev/null || {print "System-User and System-Group '$SCUUID' must exist on local system"; exit 2} }

[[ -d ${PATH_CONTAINER}${CONTAINER_CREATE_NAME} ]] && {
  print "Temporary Container exists! Will destroy all snapshots and files inside (usually what you want) Continue?"
  read -q || exit 4
 }


[[ ${#LATEST_BASE_SNAP} -ne 1 ]] && exit 1
[[ -d ${PATH_CONTAINER}${CONTAINER_CREATE_NAME} ]] && { zfs destroy -r ${CONTAINER_CREATE_ZFS} || exit 2 }
zfs clone ${ZFS_CONTAINERS}${BASE}@$LATEST_BASE_SNAP ${CONTAINER_CREATE_ZFS} || exit 3

#remove old config, so we can chroot in there with network access
rm -f /etc/systemd/nspawn/${CONTAINER_CREATE_NAME}.nspawn

[[ -n ${CREATEMIRROR_USER} ]] && for SCUUID in ${CREATEMIRROR_USER}; do
       ## add group/user with same gid / uid as system so they match owner of /var/lib/${SCUUID}
       local mirrorgid="$(id -g ${SCUUID})"
       local mirrorgroup="$(getent group $mirrorgid | cut -d: -f 1)"
       local mirrorhomedir="$(getent passwd $SCUUID | cut -d: -f 6)"
       local mirrorshell=($(getent passwd $SCUUID | cut -d: -f 7))
       [[ -n $mirrorshell ]] && mirrorshell=(-s "$mirrorshell")
       /usr/bin/systemd-nspawn  --machine=${CONTAINER_CREATE_NAME} --settings=false -- /usr/sbin/groupadd --system -g ${mirrorgid} ${mirrorgroup}
       /usr/bin/systemd-nspawn  --machine=${CONTAINER_CREATE_NAME} --settings=false -- /usr/sbin/useradd --system "$mirrorshell[@]" --home "$mirrorhomedir" -u $(id -u ${SCUUID}) -g $mirrorgid ${SCUUID}
done

[[ -n ${DEB_APTKEYS} ]] && { for APTKEY ("${DEB_APTKEYS[@]}") { print -- "$APTKEY" >| ${CONTAINER_CREATE_ROOT}/root/new.key ; /usr/bin/systemd-nspawn --machine=${CONTAINER_CREATE_NAME} --settings=false --as-pid2 -- apt-key add /root/new.key; rm -f ${CONTAINER_CREATE_ROOT}/root/new.key } || exit 5 }
[[ -n ${DEB_APTSOURCES} ]] && { \
  print -l -- ${DEB_APTSOURCES} > ${CONTAINER_CREATE_ROOT}/etc/apt/sources.list.d/extrasources.list \
  && /usr/bin/systemd-nspawn --machine=${CONTAINER_CREATE_NAME} --settings=false --setenv=DEBIAN_FRONTEND=noninteractive -- apt-get update || exit 2  \
 }

/usr/bin/systemd-nspawn --machine=${CONTAINER_CREATE_NAME} --settings=false --setenv=DEBIAN_FRONTEND=noninteractive -- apt-get update || exit 2
#/usr/bin/systemd-nspawn --machine=${CONTAINER_CREATE_NAME} --settings=false --setenv=DEBIAN_FRONTEND=noninteractive aptitude
/usr/bin/systemd-nspawn --machine=${CONTAINER_CREATE_NAME} --settings=false --as-pid2 --setenv=DEBIAN_FRONTEND=noninteractive -- apt-get install ${APTGETOPTIONS} --no-install-recommends --yes "${PACKAGES[@]}" || exit 3

for rmf ( "${RMFILES[@]}" ) rm -f ${CONTAINER_CREATE_ROOT}/"$rmf"
mkdir -p ${CONFIGDIR}$CONTAINER_NAME/
rsync -av -K ${CONFIGDIR}$CONTAINER_NAME/ ${CONTAINER_CREATE_ROOT}/ || exit 5
[[ -n $CREATEMIRROR_USERHOMEDIR ]] && chroot ${CONTAINER_CREATE_ROOT} chown ${CREATEMIRROR_USER}:${CREATEMIRROR_USER} -R "$CREATEMIRROR_USERHOMEDIR"


if [[ -n $REQUIRE_SERVICE ]]; then
mkdir -p /etc/systemd/system/systemd-nspawn@${CONTAINER_CREATE_NAME}.service.d/
echo "
[Unit]
After=${REQUIRE_SERVICE}
Requires=${REQUIRE_SERVICE}
" >| /etc/systemd/system/systemd-nspawn@${CONTAINER_CREATE_NAME}.service.d/requires.conf
fi

if [[ -n $UNIT_CONDITIONS ]]; then
mkdir -p /etc/systemd/system/systemd-nspawn@${CONTAINER_CREATE_NAME}.service.d/
echo "
[Unit]
${(F)UNIT_CONDITIONS}
" >| /etc/systemd/system/systemd-nspawn@${CONTAINER_CREATE_NAME}.service.d/unitconditions.conf
fi


[[ -d /etc/systemd/nspawn ]] || mkdir /etc/systemd/nspawn
echo "$NSPAWN_CONFIG" >| /etc/systemd/nspawn/${CONTAINER_CREATE_NAME}.nspawn


##machinectl start $CONTAINER_CREATE_NAME
##sleep 1
##machinectl stop $CONTAINER_CREATE_NAME
##privuidbase=$(ls -n -d ${CONTAINER_CREATE_ROOT}/bin | cut -d' ' -f3)
local -a newusers
local -A newusers_gid
local -A newusers_uid
local -A newusers_home
local -A newusers_shell
for newuser in ${(f)$(diff -u --suppress-common-lines ${PATH_CONTAINER}${BASE}/etc/passwd ${CONTAINER_CREATE_ROOT}/etc/passwd | sed '/^[^+]/d;/^+++/d;s/^+\+//')}; do
  local -a ua
  ua=(${(s/:/)newuser})
  newusers+=($ua[1])
  newusers_uid[$ua[1]]=$ua[3]
  newusers_gid[$ua[1]]=$ua[4]
  newusers_home[$ua[1]]=$ua[6]
  newusers_shell[$ua[1]]=$ua[7]
done


wait-until-nspawn-is-done() {
	sleep 1
	#while [[ $(lsof +D ${CONTAINER_CREATE_ROOT} 2>/dev/null | wc -l) -gt 0 ]]; do sleep 2; done
	sleep 10
}

exec-incontainer() {
	local cmds=${(j:; :)${(f)1}}
	/usr/bin/systemd-nspawn --machine=${CONTAINER_CREATE_NAME} --settings=false --as-pid2  -- /bin/bash -xc "$cmds"
	wait-until-nspawn-is-done
}

execasuser-incontainer() {
	local user=$1
	local cmds=${(j:; :)${(f)2}}
	/usr/bin/systemd-nspawn --machine=${CONTAINER_CREATE_NAME} --settings=false --as-pid2 -- /bin/su "$user" -s /bin/bash --login -c "set -x; $cmds"
	wait-until-nspawn-is-done
}

execasuser-inrunningcontainer() {
	local user=$1
	local cmds=${(j:; :)${(f)2}}
    	systemctl is-active systemd-nspawn@${CONTAINER_CREATE_NAME}.service || machinectl start ${CONTAINER_CREATE_NAME}
	for ((waitsec=0;waitsec<15;waitsec++)); do
    		systemctl is-active systemd-nspawn@${CONTAINER_CREATE_NAME}.service && break || sleep 2
	done
	sleep 6 ## wait until dbus is online
    	systemctl is-active systemd-nspawn@${CONTAINER_CREATE_NAME}.service || { machinectl stop ${CONTAINER_CREATE_NAME}; exit 6 }
	/usr/bin/systemd-run --machine=${CONTAINER_CREATE_NAME} --tty -- /bin/su "$user" -s /bin/bash -c "set -x; $cmds" || {machinectl stop ${CONTAINER_CREATE_NAME};  exit 7}
	machinectl poweroff ${CONTAINER_CREATE_NAME} || exit 8
	for ((waitsec=0;waitsec<30;waitsec++)); do
    		systemctl is-active systemd-nspawn@${CONTAINER_CREATE_NAME}.service || break
	done
	wait-until-nspawn-is-done
}

snapshotcontainer() {
	zfs snapshot ${CONTAINER_CREATE_ZFS}@$(date +%Y-%m-%d) || zfs snapshot ${ZFS_CONTAINERS}${CONTAINER_NAME}@$(date +%Y-%m-%d)
}

zfsdestroysnapshots() {
	for snapshot in $(zfs list -H -t snapshot $1 -o name | grep "^$1"); do
		zfs destroy "$snapshot"
	done
}

deploycontainer() {
    machinectl stop ${CONTAINER_CREATE_NAME}

    if [[ -d /etc/systemd/system/systemd-nspawn@${CONTAINER_CREATE_NAME}.service.d ]]; then
        mkdir -p /etc/systemd/system/systemd-nspawn@${CONTAINER_NAME}.service.d/
        rsync -va -K /etc/systemd/system/systemd-nspawn@${CONTAINER_CREATE_NAME}.service.d/ /etc/systemd/system/systemd-nspawn@${CONTAINER_NAME}.service.d/
        rm -Rf /etc/systemd/system/systemd-nspawn@${CONTAINER_CREATE_NAME}.service.d/
    fi

    systemctl is-active systemd-nspawn@${CONTAINER_NAME}.service
    isrunning=$?
    [[ $isrunning -eq 0 ]] && {
	print "Target Container is running! Will stop. Continue?"
	read -q || exit 5
        machinectl stop ${CONTAINER_NAME}
        for ((i=0;i<15;i++)); do if systemctl is-active systemd-nspawn@${CONTAINER_NAME}.service then sleep 1 else break; done
        if systemctl is-active systemd-nspawn@${CONTAINER_NAME}.service; then machinectl terminate ${CONTAINER_NAME}; fi
        for ((i=0;i<8;i++)); do if systemctl is-active systemd-nspawn@${CONTAINER_NAME}.service then sleep 1 else break; done
    }
    wait-until-nspawn-is-done
    
    [[ -d ${PATH_CONTAINER}${CONTAINER_NAME} ]] && {
	  #print "Target Container exists! Will destroy snapshots, backup latest as .old and replace. Previous .old will be destroyed (usually what you want) Continue?"
	  #read -q || exit 4
          zfs list -o name | grep -q "^${ZFS_CONTAINERS}${CONTAINER_NAME}.old" && zfs destroy -r ${ZFS_CONTAINERS}${CONTAINER_NAME}.old || echo "no .old snapshot"
	  zfsdestroysnapshots ${ZFS_CONTAINERS}${CONTAINER_NAME} 
    	  zfs rename ${ZFS_CONTAINERS}${CONTAINER_NAME} ${ZFS_CONTAINERS}${CONTAINER_NAME}.old || exit 10
    }
    
    zfs rename ${CONTAINER_CREATE_ZFS} ${ZFS_CONTAINERS}${CONTAINER_NAME} || exit 10
    mv /etc/systemd/nspawn/${CONTAINER_CREATE_NAME}.nspawn /etc/systemd/nspawn/${CONTAINER_NAME}.nspawn
    
    [[ $STARTONBOOT -eq 1 ]] && machinectl enable ${CONTAINER_NAME}

    [[ $isrunning -eq 0 ]] && machinectl start ${CONTAINER_NAME}
}

