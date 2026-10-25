# Vulnerable lab for php2shell (CVE-2026-109618 / CVE-2026-109619)
#
# BASE default is the last 8.4 release before the fix; build with
# --build-arg BASE=php:8.4.27-apache for the patched control.
#
# SAPI: mod_php (php:*-apache) -- PHP itself rates the risk highest here,
# because the attack path is reachable *before* application code runs.
#
# Two config profiles:
#   stock  -- PHP production defaults (memory_limit 128M, post_max_size 8M)
#   tight  -- what shared hosting actually ships: a finite, low memory_limit
#             next to a generous post_max_size. This is the configuration in
#             which the OOM half of the bug is reachable.
ARG BASE=docker.io/library/php:8.4.26-apache
FROM ${BASE}

ARG MEMORY_LIMIT=128M
ARG POST_MAX_SIZE=8M
ARG UPLOAD_MAX_FILESIZE=2M
ARG MAX_INPUT_VARS=1000
ARG MAX_INPUT_NESTING_LEVEL=64
ARG SESSION_UPLOAD_PROGRESS=1
ARG DISPLAY_ERRORS=Off
ARG LAB_WORKERS=1

COPY php.ini /usr/local/etc/php/php.ini
RUN sed -i \
      -e "s|@MEMORY_LIMIT@|${MEMORY_LIMIT}|" \
      -e "s|@POST_MAX_SIZE@|${POST_MAX_SIZE}|" \
      -e "s|@UPLOAD_MAX_FILESIZE@|${UPLOAD_MAX_FILESIZE}|" \
      -e "s|@MAX_INPUT_VARS@|${MAX_INPUT_VARS}|" \
      -e "s|@MAX_INPUT_NESTING_LEVEL@|${MAX_INPUT_NESTING_LEVEL}|" \
      -e "s|@SESSION_UPLOAD_PROGRESS@|${SESSION_UPLOAD_PROGRESS}|" \
      -e "s|@DISPLAY_ERRORS@|${DISPLAY_ERRORS}|" \
      /usr/local/etc/php/php.ini

# Single prefork child by default => deterministic worker reuse for the
# stale-state half. Widen with --build-arg LAB_WORKERS=N.
COPY apache-lab.conf /etc/apache2/conf-enabled/zz-lab.conf
RUN sed -i "s|@WORKERS@|${LAB_WORKERS}|g" /etc/apache2/conf-enabled/zz-lab.conf

COPY www/ /var/www/html/
RUN mkdir -p /var/lib/php/sessions && chown www-data:www-data /var/lib/php/sessions

EXPOSE 80
