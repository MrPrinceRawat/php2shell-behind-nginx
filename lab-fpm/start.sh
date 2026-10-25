#!/bin/sh
# nginx in front of PHP-FPM, both in this container; FPM has a single worker.
php-fpm -y /usr/local/etc/php-fpm.conf --fpm-config /usr/local/etc/php-fpm.d/zz-lab.conf --daemonize
exec nginx -c /etc/nginx/nginx.conf -g 'daemon off;'
