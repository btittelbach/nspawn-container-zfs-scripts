#!/bin/zsh
. ${0:h}/include_config.sh

BASE=base-focal
LATEST_BASE_SNAP=( ${PATH_CONTAINER}${BASE}/.zfs/snapshot/<->-*(D[-1]:t) )
CONTAINER_NAME=${0:t:r:s/create_//}
RMFILES=( /etc/nginx/sites-enabled/default )
PACKAGES=( nginx php-fpm php-mysql php-pear php-gd php-curl php-apcu php-json php-mime-type php-bz2 php-intl php-mbstring php-zip geoip-database mysql-client dbus ca-certificates php-imagick wget unzip redis-server php-redis php-gmp php-bcmath inotify-tools )
PACKAGES+=(tesseract-ocr-deu tesseract-ocr-eng tesseract-ocr lrzip)
CREATEMIRROR_USER=
REQUIRE_SERVICE=systemd-nspawn@mysql.service
STARTONBOOT=1
NEXTCLOUD_HOST_DATA_DIR=/<TODO>/nextclouddata
NEXTCLOUD_HOST_CODE_DIR=/<TODO>/nextcloudcode
NSPAWN_CONFIG="
[Exec]
Boot=yes
PrivateUsers=no

[Network]
Private=yes
VirtualEthernet=yes
Zone=www

[Files]
ReadOnly=no
Volatile=no
Bind=${NEXTCLOUD_HOST_CODE_DIR}/custom_apps:/var/www/nextcloud/custom_apps
Bind=${NEXTCLOUD_HOST_DATA_DIR}:/var/www/nextcloud/data
Bind=/var/www/.well-known:/var/www/.well-known
"
UNIT_CONDITIONS=( ConditionDirectoryNotEmpty=$NEXTCLOUD_HOST_DATA_DIR ConditionDirectoryNotEmpty=$NEXTCLOUD_HOST_CODE_DIR )


. ${0:h}/include_create.sh

## enable the tmp fs size fix script
exec-incontainer "/bin/systemctl enable tmp-tmpfs-resize.service"

## make sure file exists, so PathReadWrite in systemd unit finds it
touch ${CONTAINER_CREATE_ROOT}/var/log/php7.4-fpm.log

NCVERSION=24.0.12
PHPPROMETHEUSEXPORTER=2.2.0
exec-incontainer "/usr/sbin/addgroup www-data redis"
exec-incontainer "mkdir /root/install; cd /root/install/; wget https://download.nextcloud.com/server/releases/nextcloud-$NCVERSION.zip https://download.nextcloud.com/server/releases/nextcloud-$NCVERSION.zip.asc https://github.com/hipages/php-fpm_exporter/releases/download/v2.2.0/php-fpm_exporter_${PHPPROMETHEUSEXPORTER}_linux_amd64"
gpg --verify $CONTAINER_CREATE_ROOT/root/install/nextcloud-$NCVERSION.zip.asc $CONTAINER_CREATE_ROOT/root/install/nextcloud-$NCVERSION.zip || {echo -e '\n\nFATAL: archive signature verification failed!' ; exit 7}
exec-incontainer "mv /root/install/php-fpm_exporter_${PHPPROMETHEUSEXPORTER}_linux_amd64 /usr/local/bin/php-fpm_exporter; chmod +x /usr/local/bin/php-fpm_exporter"
exec-incontainer "cd /var/www/; unzip /root/install/nextcloud-$NCVERSION.zip; rm -R /root/install/; chown -R www-data:www-data /var/www/nextcloud/;"
exec-incontainer "update-ca-certificates"


### in running container so data is mounted and mysql can be accessed
sed -i "s/'config_is_read_only' => true/'config_is_read_only' => false/i" $CONTAINER_CREATE_ROOT/var/www/nextcloud/config/config.php
execasuser-inrunningcontainer www-data "cd /var/www/nextcloud/; php occ upgrade -v"
sed -i "s/'config_is_read_only' => false/'config_is_read_only' => true/i" $CONTAINER_CREATE_ROOT/var/www/nextcloud/config/config.php

## handled via symlink in container_configs
##systemctl -M $CONTAINER_CREATE_NAME enable nextcloud-cron.timer prometheus-php-exporter.service

echo "======== Config DIFF Start ========"
diff -u ${CONFIGDIR}$CONTAINER_NAME/var/www/nextcloud/config/config.php $CONTAINER_CREATE_ROOT/var/www/nextcloud/config/config.php
echo "======== Config DIFF End ========"
echo "Save new config.php ??"
read -q && cp $CONTAINER_CREATE_ROOT/var/www/nextcloud/config/config.php ${CONFIGDIR}$CONTAINER_NAME/var/www/nextcloud/config/config.php

snapshotcontainer
deploycontainer

