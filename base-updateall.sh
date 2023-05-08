#!/bin/zsh
. ${0:h}/include_config.sh

for base in ${PATH_CONTAINER}base-*(/) ; do
  chroot $base apt-get update
  chroot $base apt-get upgrade
  zfs snapshot ${ZFS_CONTAINERS}${base:t}@$(date +%Y-%m-%d)
done
