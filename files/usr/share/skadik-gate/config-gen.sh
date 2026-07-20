#!/bin/sh
# Skadik-Gate: Xray JSON config generator
# Reads UCI config + node outbounds → generates /etc/skadik-gate/config.json

. /lib/functions.sh

SG_CONF_DIR="/etc/skadik-gate"
SG_XRAY_CONF="${SG_CONF_DIR}/config.json"
SG_NODES_DIR="${SG_CONF_DIR}/nodes"
SG_DATA_DIR="/usr/share/xray"
SG_GEO_DIR="${SG_DATA_DIR}"

log() { logger -t skadik-gate-config "$@"; }

get_active_node() {
	local active_file="${SG_NODES_DIR}/.active"
	if [ -f "$active_file" ]; then
		cat "$active_file"
	fi
}

generate_config() {
	config_load skadik-gate

	local tproxy_port dns_port socks_port log_level xray_log_level
	config_get tproxy_port main tproxy_port "7893"
	config_get dns_port main dns_port "7874"
	config_get socks_port main socks_port "7875"
	config_get log_level main log_level "warning"
	config_get xray_log_level main xray_log_level "warning"

	local active_node
	active_node=$(get_active_node)

	local node_file="${SG_NODES_DIR}/${active_node}.outbound"
	if [ ! -f "$node_file" ]; then
		log "No active node found, using direct only"
		node_file=""
	fi

	local proxy_outbound
	if [ -n "$node_file" ] && [ -f "$node_file" ]; then
		proxy_outbound=$(cat "$node_file")
	else
		proxy_outbound='{
			"tag": "direct",
			"protocol": "freedom",
			"settings": {}
		}'
	fi

	local outbound_tag
	outbound_tag=$(echo "$proxy_outbound" | sed -n 's/.*"tag": "\([^"]*\)".*/\1/p' | head -1)

	cat > "$SG_XRAY_CONF" <<XRAYEOF
{
    "log": {
        "loglevel": "${xray_log_level}",
        "access": "${SG_CONF_DIR}/access.log",
        "error": "${SG_CONF_DIR}/error.log"
    },
    "stats": {},
    "api": {
        "tag": "api",
        "services": ["StatsService"]
    },
    "policy": {
        "system": {
            "statsInboundUplink": true,
            "statsInboundDownlink": true,
            "statsOutboundUplink": true,
            "statsOutboundDownlink": true
        }
    },
    "inbounds": [
        {
            "tag": "tproxy",
            "port": ${tproxy_port},
            "protocol": "dokodemo-door",
            "settings": {
                "network": "tcp,udp",
                "followRedirect": true
            },
            "streamSettings": {
                "sockopt": {
                    "tproxy": "tproxy",
                    "mark": 255
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "routeOnly": true
            }
        },
        {
            "tag": "socks-in",
            "port": ${socks_port},
            "protocol": "socks",
            "settings": {
                "auth": "noauth",
                "udp": true,
                "ip": "127.0.0.1"
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        },
        {
            "tag": "dns-in",
            "port": ${dns_port},
            "protocol": "dokodemo-door",
            "settings": {
                "address": "127.0.0.1",
                "port": 53,
                "network": "tcp,udp"
            }
        },
        {
            "tag": "api-in",
            "port": 10085,
            "protocol": "dokodemo-door",
            "settings": {
                "address": "127.0.0.1"
            },
            "listen": "127.0.0.1"
        }
    ],
    "outbounds": [
        ${proxy_outbound},
        {
            "tag": "direct",
            "protocol": "freedom",
            "settings": {}
        },
        {
            "tag": "block",
            "protocol": "blackhole",
            "settings": {}
        },
        {
            "tag": "dns-out",
            "protocol": "dns",
            "settings": {}
        }
    ],
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "inboundTag": ["api-in"],
                "outboundTag": "api"
            },
            {
                "type": "field",
                "domain": ["geosite:private"],
                "outboundTag": "direct"
            },
            {
                "type": "field",
                "ip": ["geoip:private"],
                "outboundTag": "direct"
            },
            {
                "type": "field",
                "inboundTag": ["dns-in"],
                "outboundTag": "dns-out"
            }
XRAYEOF

	config_load skadik-gate
	local rule_action rule_type rule_value rule_enabled rule_name

	config_foreach process_rule "rule"

	cat >> "$SG_XRAY_CONF" <<XRAYEOF2
            {
                "type": "field",
                "outboundTag": "${outbound_tag}",
                "port": "0-65535"
            }
        ]
    },
    "dns": {
        "servers": [
            "8.8.8.8",
            {
                "address": "1.1.1.1",
                "domains": ["geosite:geolocation-!cn"]
            },
            {
                "address": "223.5.5.5",
                "domains": ["geosite:cn"]
            },
            "localhost"
        ],
        "queryStrategy": "UseIP",
        "disableCache": false
    }
}
XRAYEOF2

	log "Config generated successfully: ${SG_XRAY_CONF}"
}

process_rule() {
	local section="$1"
	config_get rule_enabled "$section" enabled "1"
	[ "$rule_enabled" = "0" ] && return

	config_get rule_action "$section" action "proxy"
	config_get rule_type "$section" type "domain"
	config_get rule_value "$section" value ""

	[ -z "$rule_value" ] && return

	local xray_action
	case "$rule_action" in
		direct) xray_action="direct" ;;
		block)  xray_action="block" ;;
		proxy)  xray_action="$(get_active_tag)" ;;
		*)      xray_action="direct" ;;
	esac

	local rule_json=""
	case "$rule_type" in
		domain)
			local IFS=','
			for d in $rule_value; do
				d=$(echo "$d" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
				[ -n "$rule_json" ] && rule_json="${rule_json},"
				rule_json="${rule_json}\"${d}\""
			done
			echo "            {\"type\": \"field\", \"domain\": [${rule_json}], \"outboundTag\": \"${xray_action}\"}," >> "${SG_NODES_DIR}/.rules_tmp"
			;;
		cidr)
			local IFS=','
			for c in $rule_value; do
				c=$(echo "$c" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
				[ -n "$rule_json" ] && rule_json="${rule_json},"
				rule_json="${rule_json}\"${c}\""
			done
			echo "            {\"type\": \"field\", \"ip\": [${rule_json}], \"outboundTag\": \"${xray_action}\"}," >> "${SG_NODES_DIR}/.rules_tmp"
			;;
		geosite)
			echo "            {\"type\": \"field\", \"domain\": [\"geosite:${rule_value}\"], \"outboundTag\": \"${xray_action}\"}," >> "${SG_NODES_DIR}/.rules_tmp"
			;;
		geoip)
			echo "            {\"type\": \"field\", \"ip\": [\"geoip:${rule_value}\"], \"outboundTag\": \"${xray_action}\"}," >> "${SG_NODES_DIR}/.rules_tmp"
			;;
		destination)
			local IFS=','
			for d in $rule_value; do
				d=$(echo "$d" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
				[ -n "$rule_json" ] && rule_json="${rule_json},"
				rule_json="${rule_json}\"${d}\""
			done
			echo "            {\"type\": \"field\", \"domain\": [${rule_json}], \"outboundTag\": \"${xray_action}\"}," >> "${SG_NODES_DIR}/.rules_tmp"
			;;
	esac
}

get_active_tag() {
	local active_node
	active_node=$(get_active_node)
	local node_file="${SG_NODES_DIR}/${active_node}.outbound"
	if [ -f "$node_file" ]; then
		sed -n 's/.*"tag": "\([^"]*\)".*/\1/p' "$node_file" | head -1
	else
		echo "proxy"
	fi
}

insert_rules() {
	local rules_tmp="${SG_NODES_DIR}/.rules_tmp"
	> "$rules_tmp"

	config_load skadik-gate
	config_foreach process_rule "rule"

	if [ -s "$rules_tmp" ]; then
		sed -i '$ s/,$//' "$rules_tmp"

		local tmp_conf="${SG_XRAY_CONF}.tmp"
		local insert_after
		insert_after=$(grep -n '"ip": \["geoip:private"\]' "$SG_XRAY_CONF" | tail -1 | cut -d: -f1)

		if [ -n "$insert_after" ]; then
			head -n "$insert_after" "$SG_XRAY_CONF" > "$tmp_conf"
			cat "$rules_tmp" >> "$tmp_conf"
			tail -n +$((insert_after + 1)) "$SG_XRAY_CONF" >> "$tmp_conf"
			mv "$tmp_conf" "$SG_XRAY_CONF"
		fi
	fi

	rm -f "$rules_tmp"
}

case "${1:-generate}" in
	generate)
		generate_config
		;;
	insert-rules)
		insert_rules
		;;
	*)
		echo "Usage: $0 {generate|insert-rules}"
		exit 1
		;;
esac
