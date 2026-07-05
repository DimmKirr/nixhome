#!/bin/sh
# GL.iNet client data dumper — runs as root via procd
# Install: copy to /usr/bin/gl-clients-dump
# Creates /tmp/gl-clients.json for the netdata gl-router.plugin to read

logger -t gl-dump "starting"

while true; do
    if /bin/ubus call gl-clients list > /tmp/gl-clients.json.tmp 2>/dev/null; then
        chmod 644 /tmp/gl-clients.json.tmp
        mv /tmp/gl-clients.json.tmp /tmp/gl-clients.json
    else
        logger -t gl-dump "ubus call failed"
    fi
    sleep 10
done
