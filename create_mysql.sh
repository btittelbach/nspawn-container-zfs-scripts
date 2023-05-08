#!/bin/zsh        
. ${0:h}/include_config.sh

BASE=base-bullseye
LATEST_BASE_SNAP=( ${PATH_CONTAINER}${BASE}/.zfs/snapshot/<->-*(D[-1]:t) )
CONTAINER_NAME=${0:t:r:s/create_//}
RMFILES=( /etc/nginx/sites-enabled/default )
PACKAGES=( apparmor dbus systemd dbus-user-session mariadb-server )
CREATEMIRROR_USER=(mysql)
REQUIRE_SERVICE=
STARTONBOOT=1
NSPAWN_CONFIG="
[Exec]
Boot=yes
PrivateUsers=no

[Network]
Zone=www

[Files]
Bind=/var/lib/mysql
Volatile=no
"
UNIT_CONDITIONS=( ConditionDirectoryNotEmpty=/var/lib/mysql RequiresMountsFor=/var/lib/mysql )

. ${0:h}/include_create.sh

snapshotcontainer
deploycontainer
