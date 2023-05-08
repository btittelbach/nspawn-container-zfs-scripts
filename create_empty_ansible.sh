#!/bin/zsh
. ${0:h}/include_config.sh

BASE=base-bullseye
LATEST_BASE_SNAP=( ${PATH_CONTAINER}${BASE}/.zfs/snapshot/<->-*(D[-1]:t) )
CONTAINER_NAME=${0:t:r:s/create_//}
RMFILES=( )
PACKAGES=( dbus ca-certificates systemd openssh-server python3 sudo )
CREATEMIRROR_USER=( )
REQUIRE_SERVICE=
STARTONBOOT=1
NSPAWN_CONFIG="
[Exec]
Boot=yes
PrivateUsers=no

[Network]
Private=yes
VirtualEthernet=yes
Zone=www

[Files]
"
UNIT_CONDITIONS=( )
DEB_APTKEYS=( )
DEB_APTSOURCES=( )


. ${0:h}/include_create.sh

## copy authorized keys from root
mkdir -m 700 -p ${CONTAINER_CREATE_ROOT}/root/.ssh
cp -a ~root/.ssh/authorized_keys ${CONTAINER_CREATE_ROOT}/root/.ssh


snapshotcontainer
deploycontainer
zfs set quota=4G ${ZFS_CONTAINERS}${CONTAINER_NAME}

