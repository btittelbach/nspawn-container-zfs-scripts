#!/bin/bash

PHP_WWW_CONF_FILE=/etc/php/7.4/fpm/pool.d/www.conf 
PHP_SERVICE=php7.4-fpm.service
PROMETHEUS_SERVICE=prometheus-php-exporter.service

if systemctl is-active $PROMETHEUS_SERVICE && systemctl is-active $PHP_SERVICE; then

    num_conn_refused_1min=$(( $(journalctl --since "-1m" -eu $PROMETHEUS_SERVICE | grep "connect: connection refused" | wc -l ) ))
    max_children=$(( $(grep '^pm.max_children' $PHP_WWW_CONF_FILE | tail -n 1 | sed 's/.*= *\([0-9]\+\).*/\1/' ) ))

    if [[ $num_conn_refused_1min -gt $max_children ]]; then
	echo Restarting PHPFPM, since $num_conn_refused_1min > $max_children
        systemctl restart $PHP_SERVICE
    fi

fi

