#!/bin/bash
# Netdata external plugin: GL.iNet router + client metrics
# Install: copy to /opt/netdata/usr/libexec/netdata/plugins.d/gl-inet.plugin
# Requires: jq (opkg install jq), gl-clients-dump service running

update_every="${1:-10}"

# Output charts immediately to prevent Netdata timeout
printf "CHART gl_client.count '' 'Connected clients' 'clients' 'GL-iNet Clients' gl_client.count line 99999 %s\nDIMENSION online 'online' absolute 1 1\nDIMENSION total 'known' absolute 1 1\nBEGIN gl_client.count\nSET online = 0\nSET total = 0\nEND\n" "${update_every}"
printf "CHART gl_router.temperature '' 'CPU temperature' 'Celsius' 'GL-iNet Router' gl_router.temperature line 99998 %s\nDIMENSION cpu 'cpu' absolute 1 1000\nBEGIN gl_router.temperature\nSET cpu = 0\nEND\n" "${update_every}"

declare -A known
known[_summary]=1

get_clients() {
    [ -f /tmp/gl-clients.json ] || return 1
    local json
    json=$(cat /tmp/gl-clients.json) || return 1

    local online_count=0 total_count=0

    while IFS=$'\t' read -r ip name iface tx rx total_tx total_rx; do
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        online_count=$((online_count + 1))

        local id="${ip//\./_}"
        local label="${name:-${ip}} (${iface})"
        local safe_name="${name:-${ip}}"
        safe_name="${safe_name// /_}"
        safe_name="${safe_name//-/_}"

        if [ -z "${known[$id]}" ]; then
            known[$id]=1
            printf "CHART gl_client.speed_%s '%s.speed' '%s bandwidth' 'bytes/s' 'GL-iNet Clients' gl_client.speed line 100000 %s\nDIMENSION tx 'sent' absolute 1 1\nDIMENSION rx 'received' absolute 1 1\n" "${id}" "${safe_name}" "${label}" "${update_every}"
            printf "CHART gl_client.traffic_%s '%s.traffic' '%s total' 'bytes' 'GL-iNet Clients' gl_client.traffic area 100001 %s\nDIMENSION total_tx 'sent' absolute 1 1\nDIMENSION total_rx 'received' absolute 1 1\n" "${id}" "${safe_name}" "${label}" "${update_every}"
        fi

        printf "BEGIN gl_client.speed_%s\nSET tx = %s\nSET rx = %s\nEND\nBEGIN gl_client.traffic_%s\nSET total_tx = %s\nSET total_rx = %s\nEND\n" "${id}" "${tx:-0}" "${rx:-0}" "${id}" "${total_tx:-0}" "${total_rx:-0}"
    done < <(echo "$json" | /usr/bin/jq -r '
        .clients[]
        | select(.online == true)
        | [
            (.ip // ""),
            (if (.name // "") == "" then .ip else .name end),
            (.iface // ""),
            (.tx // 0 | tonumber),
            (.rx // 0 | tonumber),
            (.total_tx // "0" | tonumber),
            (.total_rx // "0" | tonumber)
          ]
        | @tsv
    ')

    total_count=$(echo "$json" | /usr/bin/jq '.clients | length')

    printf "BEGIN gl_client.count\nSET online = %s\nSET total = %s\nEND\n" "${online_count}" "${total_count:-0}"

    local temp
    temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    if [ -n "$temp" ]; then
        printf "BEGIN gl_router.temperature\nSET cpu = %s\nEND\n" "${temp}"
    fi
}

while true; do
    get_clients
    sleep ${update_every}
done
