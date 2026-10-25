# Same vulnerable build, but behind PHP-FPM + nginx.
#
# Worth a separate lab: FPM reads the POST body from sapi_activate(), i.e.
# before module RINIT, and skips module RSHUTDOWN when startup never finished.
# The upload-progress handler therefore runs with the previous request's
# session globals still in place, which is the shape CVE-2026-109619 describes.
FROM docker.io/library/php:8.4.26-fpm

ARG BASE=unused
ARG MEMORY_LIMIT=32M
ARG POST_MAX_SIZE=64M
ARG UPLOAD_MAX_FILESIZE=64M

RUN apt-get update && apt-get install -y --no-install-recommends nginx \
 && rm -rf /var/lib/apt/lists/*

COPY php.ini /usr/local/etc/php/php.ini
RUN sed -i \
      -e "s|@MEMORY_LIMIT@|${MEMORY_LIMIT}|" \
      -e "s|@POST_MAX_SIZE@|${POST_MAX_SIZE}|" \
      -e "s|@UPLOAD_MAX_FILESIZE@|${UPLOAD_MAX_FILESIZE}|" \
      -e "s|@MAX_INPUT_VARS@|10000|" \
      -e "s|@MAX_INPUT_NESTING_LEVEL@|64|" \
      -e "s|@SESSION_UPLOAD_PROGRESS@|1|" \
      -e "s|@DISPLAY_ERRORS@|Off|" \
      /usr/local/etc/php/php.ini

COPY pool.conf /usr/local/etc/php-fpm.d/zz-lab.conf
RUN sed -i \
      -e "s|@MEMORY_LIMIT@|${MEMORY_LIMIT}|" \
      -e "s|@POST_MAX_SIZE@|${POST_MAX_SIZE}|" \
      -e "s|@UPLOAD_MAX_FILESIZE@|${UPLOAD_MAX_FILESIZE}|" \
      /usr/local/etc/php-fpm.d/zz-lab.conf

COPY nginx.conf /etc/nginx/nginx.conf
COPY www/ /var/www/html/
COPY start.sh /start.sh
RUN chmod +x /start.sh \
 && mkdir -p /var/lib/php/sessions /run \
 && chown -R www-data:www-data /var/www/html /var/lib/php/sessions

EXPOSE 80
CMD ["/start.sh"]
