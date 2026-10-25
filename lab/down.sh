#!/bin/sh
for c in php2shell-stock php2shell-tight php2shell-patched php2shell-fpm; do
  container stop "$c" >/dev/null 2>&1 || true
  container rm "$c" >/dev/null 2>&1 || true
done
echo "lab down"
