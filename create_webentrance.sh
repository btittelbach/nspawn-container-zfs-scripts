#!/bin/zsh
. ${0:h}/include_config.sh

BASE=base-bullseye
LATEST_BASE_SNAP=( /var/lib/machines/${BASE}/.zfs/snapshot/<->-*(D[-1]:t) )
CONTAINER_NAME=${0:t:r:s/create_//}
RMFILES=( /etc/nginx/sites-enabled/default )
PACKAGES=( nginx dbus fail2ban netfilter-persistent )
CREATEMIRROR_USER=
REQUIRE_SERVICE=
STARTONBOOT=1
NSPAWN_CONFIG="
[Exec]
Boot=yes
PrivateUsers=no

[Network]
Zone=www
VirtualEthernetExtra=vb-webentr-pub:wan0

[Files]
BindReadOnly=/var/www/.well-known:/var/www/.well-known
Volatile=no
"

### add net-interface vb-webentr-pub to bridge br-eth0:
echo"
[Match]
Name=vb-webentr-pub

[Network]
Bridge=br-eth0
" > /etc/systemd/network/80-vb-webentr-pub.network
systemctl daemon-reload


wget 'https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt' -O ${CONFIGDIR}${CONTAINER_NAME}/etc/ssl/letsencrypt.pem || exit 3
. ${0:h}/include_create.sh

systemctl -M $CONTAINER_CREATE_NAME enable fail2ban

snapshotcontainer
deploycontainer
