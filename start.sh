#!/bin/bash

set -e

sed -i "s/BACKEND;/\"${BACKEND}\";/g" $VCL_CONFIG
sed -i "s/BACKEND_PORT;/\"${BACKEND_PORT}\";/g" $VCL_CONFIG

dd if=/dev/random of=/etc/varnish/varnish_secret count=1
chmod 600 /etc/varnish/varnish_secret
mkdir -p /var/lib/varnish/

exec bash -c \
  "exec varnishd -F -u varnish \
  -f $VCL_CONFIG \
  -a 0.0.0.0:9080
  -S /etc/varnish/varnish_secret \
  -T 10024 \
  -s file,/var/lib/varnish/storage,$CACHE_SIZE \
  $VARNISHD_PARAMS"
