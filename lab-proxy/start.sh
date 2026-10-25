#!/bin/sh
# Official php.ini-production, with optional runtime overrides appended (the
# production file ships the interesting settings commented out).
cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini
[ -n "${MEMORY_LIMIT:-}" ] && echo "memory_limit = ${MEMORY_LIMIT}" >> /usr/local/etc/php/php.ini
[ -n "${POST_MAX_SIZE:-}" ] && echo "post_max_size = ${POST_MAX_SIZE}" >> /usr/local/etc/php/php.ini
[ -n "${UPLOAD_MAX_FILESIZE:-}" ] && echo "upload_max_filesize = ${UPLOAD_MAX_FILESIZE}" >> /usr/local/etc/php/php.ini
if [ -n "${UP_FREQ:-}" ]; then
  echo "session.upload_progress.freq = ${UP_FREQ}" >> /usr/local/etc/php/php.ini
  echo "session.upload_progress.min_freq = 0" >> /usr/local/etc/php/php.ini
fi
if [ -n "${UP_CLEANUP:-}" ]; then
  echo "session.upload_progress.cleanup = ${UP_CLEANUP}" >> /usr/local/etc/php/php.ini
fi
if [ -n "${SESSION_SAVE_PATH:-}" ]; then
  echo "session.save_path = ${SESSION_SAVE_PATH}" >> /usr/local/etc/php/php.ini
  mkdir -p "${SESSION_SAVE_PATH}" && chown www-data:www-data "${SESSION_SAVE_PATH}"
fi
apache2ctl start
exec nginx -g 'daemon off;'
