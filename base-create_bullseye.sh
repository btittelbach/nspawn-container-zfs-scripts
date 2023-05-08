#!/bin/zsh
. ${0:h}/include_config.sh

BASE=base-bullseye
DEBIAN_VERSION=bullseye
[[ -d ${PATH_CONTAINER}$BASE ]] && zfs destroy -r ${ZFS_CONTAINERS}$BASE
zfs create -o acltype=posixacl ${ZFS_CONTAINERS}$BASE
grml-debootstrap --force --grmlrepos --nokernel -r $DEBIAN_VERSION --nopassword --nointerfaces -t ${PATH_CONTAINER}$BASE --mirror http://ftp.at.debian.org/debian
mount ${PATH_CONTAINER}${BASE} -o remount,rw
cp /etc/apt/sources.list ${PATH_CONTAINER}$BASE/etc/apt/
cp /etc/timezone  ${PATH_CONTAINER}${BASE}/etc/
ln -sf /usr/share/zoneinfo/Europe/Vienna ${PATH_CONTAINER}${BASE}/etc/localtime
chroot ${PATH_CONTAINER}${BASE} apt update
chroot ${PATH_CONTAINER}${BASE} apt install apt-transport-https
chroot ${PATH_CONTAINER}${BASE} apt full-upgrade
chroot ${PATH_CONTAINER}${BASE} apt-get --allow-remove-essential --yes purge e2fsprogs
chroot ${PATH_CONTAINER}${BASE} aptitude purge "~c"
chroot ${PATH_CONTAINER}${BASE} systemctl disable networking.service
chroot ${PATH_CONTAINER}${BASE} systemctl enable systemd-networkd.service
zfs snapshot ${ZFS_CONTAINERS}$BASE@$(date +%Y-%m-%d)
