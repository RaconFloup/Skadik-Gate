#!/bin/sh
# Skadik-Gate: nftables TPROXY setup
# Configures transparent proxy with per-device routing and rules

. /lib/functions.sh

SG_CONF_DIR="/etc/skadik-gate"
SG_RULES_FILE="${SG_CONF_DIR}/rules.nft"

log() { logger -t skadik-gate-tproxy "$@"; }

LAN_SUBNETS="192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,127.0.0.0/8"

setup_tproxy() {
	config_load skadik-gate
	local tproxy_port
	config_get tproxy_port main tproxy_port "7893"

	local device_macs_proxy=""
	local device_macs_direct=""
	local device_ips_proxy=""
	local device_ips_direct=""

	config_foreach collect_device_rules "device"

	nft -f /dev/null 2>/dev/null
	if [ $? -ne 127 ]; then
		generate_nftables "$tproxy_port" "$device_macs_proxy" "$device_macs_direct" "$device_ips_proxy" "$device_ips_direct"
	else
		log "ERROR: nftables not available"
		return 1
	fi
}

collect_device_rules() {
	local section="$1"
	local mac action enabled ip
	config_get mac "$section" mac ""
	config_get action "$section" action "proxy"
	config_get_bool enabled "$section" enabled 1
	config_get ip "$section" ip ""

	[ "$enabled" -eq 0 ] && return

	case "$action" in
		proxy)
			[ -n "$mac" ] && device_macs_proxy="${device_macs_proxy:+$device_macs_proxy,}\"${mac}\""
			[ -n "$ip" ] && device_ips_proxy="${device_ips_proxy:+$device_ips_proxy,}\"${ip}\""
			;;
		direct)
			[ -n "$mac" ] && device_macs_direct="${device_macs_direct:+$device_macs_direct,}\"${mac}\""
			[ -n "$ip" ] && device_ips_direct="${device_ips_direct:+$device_ips_direct,}\"${ip}\""
			;;
	esac
}

generate_nftables() {
	local tproxy_port="$1"
	local device_macs_proxy="$2"
	local device_macs_direct="$3"
	local device_ips_proxy="$4"
	local device_ips_direct="$5"

	cat > "$SG_RULES_FILE" <<NFTEOF
#!/usr/sbin/nft -f

flush ruleset

table ip skadik_gate {
    set proxy_macs {
        type ether_addr
        flags interval,timeout
        timeout 5m
NFTEOF

	if [ -n "$device_macs_proxy" ]; then
		echo "        elements = { ${device_macs_proxy} }" >> "$SG_RULES_FILE"
	fi

	cat >> "$SG_RULES_FILE" <<NFTEOF2
    }

    set direct_macs {
        type ether_addr
        flags interval,timeout
        timeout 5m
NFTEOF2

	if [ -n "$device_macs_direct" ]; then
		echo "        elements = { ${device_macs_direct} }" >> "$SG_RULES_FILE"
	fi

	cat >> "$SG_RULES_FILE" <<NFTEOF3
    }

    set proxy_ips {
        type ipv4_addr
        flags interval,timeout
        timeout 5m
NFTEOF3

	if [ -n "$device_ips_proxy" ]; then
		echo "        elements = { ${device_ips_proxy} }" >> "$SG_RULES_FILE"
	fi

	cat >> "$SG_RULES_FILE" <<NFTEOF4
    }

    set direct_ips {
        type ipv4_addr
        flags interval,timeout
        timeout 5m
NFTEOF4

	if [ -n "$device_ips_direct" ]; then
		echo "        elements = { ${device_ips_direct} }" >> "$SG_RULES_FILE"
	fi

	cat >> "$SG_RULES_FILE" <<NFTEOF5
    }

    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;

        ip daddr { ${LAN_SUBNETS} } return

        iif "br-lan" meta l4proto tcp meta mark set 1 tproxy to 127.0.0.1:${tproxy_port}
        iif "br-lan" meta l4proto udp meta mark set 1 tproxy to 127.0.0.1:${tproxy_port}
    }

    chain output {
        type route hook output priority mangle; policy accept;

        ip daddr { ${LAN_SUBNETS} } return
        meta mark 2 return

        meta l4proto tcp meta mark set 1
        meta l4proto udp meta mark set 1
    }
}
NFTEOF5

	nft -f "$SG_RULES_FILE"
	if [ $? -eq 0 ]; then
		log "nftables TPROXY rules loaded"
	else
		log "ERROR: Failed to load nftables rules"
		return 1
	fi

	ip rule add fwmark 1 table 100 2>/dev/null
	ip route add local default dev lo table 100 2>/dev/null
}

setup_dns_hijack() {
	config_load skadik-gate
	local dns_port
	config_get dns_port main dns_port "7874"

	nft add rule ip skadik_gate prerouting \
		udp dport 53 tproxy to 127.0.0.1:${dns_port} meta mark set 1 \
		2>/dev/null

	log "DNS hijack configured on port 53 -> ${dns_port}"
}

cleanup_tproxy() {
	nft delete table ip skadik_gate 2>/dev/null
	ip rule del fwmark 1 table 100 2>/dev/null
	ip route del local default dev lo table 100 2>/dev/null
	rm -f "$SG_RULES_FILE"
	log "nftables TPROXY rules removed"
}

reload_devices() {
	config_load skadik-gate
	local tproxy_port
	config_get tproxy_port main tproxy_port "7893"

	local device_macs_proxy=""
	local device_macs_direct=""
	local device_ips_proxy=""
	local device_ips_direct=""

	config_foreach collect_device_rules "device"

	nft flush set ip skadik_gate proxy_macs 2>/dev/null
	nft flush set ip skadik_gate direct_macs 2>/dev/null
	nft flush set ip skadik_gate proxy_ips 2>/dev/null
	nft flush set ip skadik_gate direct_ips 2>/dev/null

	if [ -n "$device_macs_proxy" ]; then
		nft add element ip skadik_gate proxy_macs { ${device_macs_proxy} } 2>/dev/null
	fi
	if [ -n "$device_macs_direct" ]; then
		nft add element ip skadik_gate direct_macs { ${device_macs_direct} } 2>/dev/null
	fi
	if [ -n "$device_ips_proxy" ]; then
		nft add element ip skadik_gate proxy_ips { ${device_ips_proxy} } 2>/dev/null
	fi
	if [ -n "$device_ips_direct" ]; then
		nft add element ip skadik_gate direct_ips { ${device_ips_direct} } 2>/dev/null
	fi

	log "Device rules reloaded"
}

case "${1:-setup}" in
	setup)
		setup_tproxy
		;;
	cleanup)
		cleanup_tproxy
		;;
	reload-devices)
		reload_devices
		;;
	dns-hijack)
		setup_dns_hijack
		;;
	*)
		echo "Usage: $0 {setup|cleanup|reload-devices|dns-hijack}"
		exit 1
		;;
esac
