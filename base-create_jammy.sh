#!/bin/zsh
. ${0:h}/include_config.sh

BASE=base-jammy
UBUNTU_VERSION=jammy
[[ -d ${PATH_CONTAINER}$BASE ]] && zfs destroy -r ${ZFS_CONTAINERS}$BASE
zfs create -o acltype=posixacl ${ZFS_CONTAINERS}$BASE
debootstrap $UBUNTU_VERSION ${PATH_CONTAINER}$BASE http://ubuntu.anexia.at/ubuntu

mkdir -p ${PATH_CONTAINER}${BASE}/etc/apt/
echo "deb http://ubuntu.anexia.at/ubuntu/ $UBUNTU_VERSION universe main multiverse restricted
deb http://security.ubuntu.com/ubuntu/ ${UBUNTU_VERSION}-security universe main multiverse restricted
" >! ${PATH_CONTAINER}${BASE}/etc/apt/sources.list
cp -a /etc/timezone  ${PATH_CONTAINER}${BASE}/etc/
ln -sf /usr/share/zoneinfo/Europe/Vienna ${PATH_CONTAINER}${BASE}/etc/localtime

/usr/bin/systemd-nspawn --machine=${BASE} --settings=false --setenv=DEBIAN_FRONTEND=noninteractive -- /usr/bin/apt-get --yes --allow-remove-essential purge e2fsprogs resolvconf sudo
cp -v -L --remove-destination /etc/resolv.conf ${PATH_CONTAINER}${BASE}/etc/resolv.conf
/usr/bin/systemd-nspawn --machine=${BASE} --settings=false --setenv=DEBIAN_FRONTEND=noninteractive -- /usr/bin/apt-get update
/usr/bin/systemd-nspawn --machine=${BASE} --settings=false --setenv=DEBIAN_FRONTEND=noninteractive -- /usr/bin/apt-get --yes install --allow-unauthenticated aptitude software-properties-common 
/usr/bin/systemd-nspawn --machine=${BASE} --settings=false --setenv=DEBIAN_FRONTEND=noninteractive -- /usr/bin/apt-get --yes upgrade
/usr/bin/systemd-nspawn --machine=${BASE} --settings=false --setenv=DEBIAN_FRONTEND=noninteractive -- systemctl disable ondemand.service
/usr/bin/systemd-nspawn --machine=${BASE} --settings=false --setenv=DEBIAN_FRONTEND=noninteractive -- systemctl disable networking.service
/usr/bin/systemd-nspawn --machine=${BASE} --settings=false --setenv=DEBIAN_FRONTEND=noninteractive -- systemctl enable systemd-networkd.service

zfs snapshot ${ZFS_CONTAINERS}${BASE}@$(date +%Y-%m-%d)
