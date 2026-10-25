#!/bin/sh
# Bring the lab up. Two vulnerable targets (mod_php stock + tight) and the
# tightened patched control used by exploit/compare.py.
set -e
here=$(cd "$(dirname "$0")" && pwd)
container build --progress plain -t php2shell-lab:stock "$here"
container build --progress plain -t php2shell-lab:tight \
  --build-arg MEMORY_LIMIT=32M --build-arg POST_MAX_SIZE=64M \
  --build-arg UPLOAD_MAX_FILESIZE=64M --build-arg MAX_INPUT_VARS=10000 "$here"
container build --progress plain -t php2shell-lab:tight-patched \
  --build-arg BASE=docker.io/library/php:8.4.27-apache \
  --build-arg MEMORY_LIMIT=32M --build-arg POST_MAX_SIZE=64M \
  --build-arg UPLOAD_MAX_FILESIZE=64M --build-arg MAX_INPUT_VARS=10000 "$here"
container run -d --name php2shell-stock -p 127.0.0.1:8080:80 php2shell-lab:stock
container run -d --name php2shell-tight -p 127.0.0.1:8081:80 php2shell-lab:tight
container run -d --name php2shell-patched -p 127.0.0.1:8082:80 php2shell-lab:tight-patched
sleep 3
for p in 8080 8081 8082; do curl -s -m 5 "http://127.0.0.1:$p/version.php" | head -1; done
