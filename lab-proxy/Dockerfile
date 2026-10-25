# mod_php behind nginx (reverse proxy), stock official ini -- the arrangement
# almost every "hardened" deployment uses. Question: does the chunked body and
# the 4-request chain survive the proxy?
FROM docker.io/library/php:8.4.26-apache

ARG BUFFERING=off

RUN apt-get update && apt-get install -y --no-install-recommends nginx libnginx-mod-stream \
 && rm -rf /var/lib/apt/lists/* \
 && sed -i 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf \
 && sed -i 's/:80>/:8080>/' /etc/apache2/sites-enabled/000-default.conf

COPY nginx.conf.tpl /etc/nginx/nginx.conf.tpl
RUN sed -i "s/@BUFFERING@/${BUFFERING}/" /etc/nginx/nginx.conf.tpl \
 && mv /etc/nginx/nginx.conf.tpl /etc/nginx/nginx.conf

COPY www/ /var/www/html/
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 80
CMD ["/start.sh"]
