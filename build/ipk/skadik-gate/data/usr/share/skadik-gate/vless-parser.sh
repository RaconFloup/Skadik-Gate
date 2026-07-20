#!/bin/sh
# Skadik-Gate: VLESS/Trojan/SS/Hysteria2 share link parser
# Parses share links from Remnawave subscription into Xray outbound JSON
# Usage: vless-parser.sh < <links.txt> or vless-parser.sh "vless://..."

SG_CONF_DIR="/etc/skadik-gate"
SG_NODES_DIR="${SG_CONF_DIR}/nodes"
mkdir -p "$SG_NODES_DIR"

urldecode() {
	printf '%b' "${1//%/\\x}" 2>/dev/null || echo "$1"
}

parse_vless_link() {
	local link="$1"
	local uuid host port name params
	local security flow sni fp pbk sid spx path host_ws alpn
	local network grpc_service httpupgrade_path

	link="${link#vless://}"
	uuid="${link%%@*}"
 remainder="${link#*@}"
	host_port="${remainder%%\?*}"
	remainder="${remainder#*\?}"

	host="${host_port%%:*}"
	port="${host_port##*:}"
	port="${port%%#*}"

	name="${link##*#}"
	name=$(urldecode "$name")

	params="$remainder"

	security=$(echo "$params" | sed -n 's/.*[&?]security=\([^&]*\).*/\1/p')
	flow=$(echo "$params" | sed -n 's/.*[&?]flow=\([^&]*\).*/\1/p')
	sni=$(echo "$params" | sed -n 's/.*[&?]sni=\([^&]*\).*/\1/p')
	fp=$(echo "$params" | sed -n 's/.*[&?]fp=\([^&]*\).*/\1/p')
	pbk=$(echo "$params" | sed -n 's/.*[&?]pbk=\([^&]*\).*/\1/p')
	sid=$(echo "$params" | sed -n 's/.*[&?]sid=\([^&]*\).*/\1/p')
	spx=$(echo "$params" | sed -n 's/.*[&?]spx=\([^&]*\).*/\1/p')
	path=$(echo "$params" | sed -n 's/.*[&?]path=\([^&]*\).*/\1/p')
	host_ws=$(echo "$params" | sed -n 's/.*[&?]host=\([^&]*\).*/\1/p')
	alpn=$(echo "$params" | sed -n 's/.*[&?]alpn=\([^&]*\).*/\1/p')
	network=$(echo "$params" | sed -n 's/.*[&?]type=\([^&]*\).*/\1/p')
	grpc_service=$(echo "$params" | sed -n 's/.*[&?]serviceName=\([^&]*\).*/\1/p')
	httpupgrade_path=$(echo "$params" | sed -n 's/.*[&?]path=\([^&]*\).*/\1/p')
	enc=$(echo "$params" | sed -n 's/.*[&?]encryption=\([^&]*\).*/\1/p')
	cipher=$(echo "$params" | sed -n 's/.*[&?]cipher=\([^&]*\).*/\1/p')
	plugin=$(echo "$params" | sed -n 's/.*[&?]plugin=\([^&]*\).*/\1/p')
	obfs_password=$(echo "$params" | sed -n 's/.*[&?]obfs-password=\([^&]*\).*/\1/p')
	obfs_type=$(echo "$params" | sed -n 's/.*[&?]obfs-type=\([^&]*\).*/\1/p')

	[ -z "$name" ] && name="${host}:${port}"
	[ -z "$sni" ] && sni="$host_ws"
	[ -z "$sni" ] && sni="$sni"

	local tag
	tag=$(echo "$name" | sed 's/[^a-zA-Z0-9._-]/_/g')

	echo "${tag}|${host}|${port}|${security}|${flow}|${sni}|${fp}|${pbk}|${sid}|${spx}|${path}|${host_ws}|${alpn}|${network}|${grpc_service}|${enc}|${cipher}|${uuid}"
}

generate_vless_outbound() {
	local data="$1"
	local tag host port security flow sni fp pbk sid spx path host_ws alpn network grpc_service enc cipher uuid

	tag=$(echo "$data" | cut -d'|' -f1)
	host=$(echo "$data" | cut -d'|' -f2)
	port=$(echo "$data" | cut -d'|' -f3)
	security=$(echo "$data" | cut -d'|' -f4)
	flow=$(echo "$data" | cut -d'|' -f5)
	sni=$(echo "$data" | cut -d'|' -f6)
	fp=$(echo "$data" | cut -d'|' -f7)
	pbk=$(echo "$data" | cut -d'|' -f8)
	sid=$(echo "$data" | cut -d'|' -f9)
	spx=$(echo "$data" | cut -d'|' -f10)
	path=$(echo "$data" | cut -d'|' -f11)
	host_ws=$(echo "$data" | cut -d'|' -f12)
	alpn=$(echo "$data" | cut -d'|' -f13)
	network=$(echo "$data" | cut -d'|' -f14)
	grpc_service=$(echo "$data" | cut -d'|' -f15)
	enc=$(echo "$data" | cut -d'|' -f16)
	cipher=$(echo "$data" | cut -d'|' -f17)
	uuid=$(echo "$data" | cut -d'|' -f18)

	[ -z "$network" ] && network="tcp"

	local vnext_users
	vnext_users="{\"id\":\"${uuid}\",\"encryption\":\"${enc:-none}\",\"flow\":\"${flow}\"}"

	local stream_settings
	stream_settings="\"network\":\"${network}\""

	if [ "$security" = "reality" ]; then
		stream_settings="${stream_settings},\"security\":\"reality\",\"realitySettings\":{\"show\":false,\"fingerprint\":\"${fp:-chrome}\",\"serverName\":\"${sni}\",\"publicKey\":\"${pbk}\",\"shortId\":\"${sid}\""
		[ -n "$spx" ] && stream_settings="${stream_settings},\"spiderX\":\"${spx}\""
		stream_settings="${stream_settings}}"
	elif [ "$security" = "tls" ]; then
		stream_settings="${stream_settings},\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"${sni}\",\"allowInsecure\":false,\"fingerprint\":\"${fp:-chrome}\""
		[ -n "$alpn" ] && stream_settings="${stream_settings},\"alpn\":[\"$(echo "$alpn" | sed 's/,/","/g')\"]"
		stream_settings="${stream_settings}}"
	elif [ "$security" = "xtls" ]; then
		stream_settings="${stream_settings},\"security\":\"xtls\",\"tlsSettings\":{\"serverName\":\"${sni}\",\"allowInsecure\":false}"
	fi

	case "$network" in
		ws)
			stream_settings="${stream_settings},\"wsSettings\":{\"headers\":{\"Host\":\"${host_ws}\"},\"path\":\"${path}\"}"
			;;
		grpc)
			stream_settings="${stream_settings},\"grpcSettings\":{\"serviceName\":\"${grpc_service}\"}"
			;;
		httpupgrade)
			stream_settings="${stream_settings},\"httpupgradeSettings\":{\"host\":\"${host_ws}\",\"path\":\"${path}\"}"
			;;
		h2)
			stream_settings="${stream_settings},\"httpSettings\":{\"host\":\"${host_ws}\",\"path\":\"${path}\"}"
			;;
		kcp)
			stream_settings="${stream_settings},\"kcpSettings\":{\"header\":{\"type\":\"none\"}}"
			;;
	esac

	cat <<EOF
{
    "tag": "${tag}",
    "protocol": "vless",
    "settings": {
        "vnext": [{
            "address": "${host}",
            "port": ${port},
            "users": [${vnext_users}]
        }]
    },
    "streamSettings": {${stream_settings}},
    "mux": {"enabled": false, "concurrency": -1}
}
EOF
}

generate_trojan_outbound() {
	local name="$1" host="$2" port="$3" password="$4" sni="$5" fp="$6" alpn="$7" network="$8" path="$9" host_ws="${10}"
	local tag
	tag=$(echo "$name" | sed 's/[^a-zA-Z0-9._-]/_/g')

	local tls_settings="\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"${sni}\",\"fingerprint\":\"${fp:-chrome}\""
	[ -n "$alpn" ] && tls_settings="${tls_settings},\"alpn\":[\"$(echo "$alpn" | sed 's/,/","/g')\"]"
	tls_settings="${tls_settings}}"

	local stream="\"network\":\"${network:-tcp}\",${tls_settings}"
	[ "$network" = "ws" ] && stream="${stream},\"wsSettings\":{\"headers\":{\"Host\":\"${host_ws}\"},\"path\":\"${path}\"}"
	[ "$network" = "grpc" ] && stream="${stream},\"grpcSettings\":{\"serviceName\":\"${path}\"}"

	cat <<EOF
{
    "tag": "${tag}",
    "protocol": "trojan",
    "settings": {
        "servers": [{
            "address": "${host}",
            "port": ${port},
            "password": "${password}",
            "email": ""
        }]
    },
    "streamSettings": {${stream}},
    "mux": {"enabled": false, "concurrency": -1}
}
EOF
}

generate_ss_outbound() {
	local name="$1" host="$2" port="$3" cipher="$4" password="$5" plugin="$6" plugin_opts="$7"
	local tag
	tag=$(echo "$name" | sed 's/[^a-zA-Z0-9._-]/_/g')

	cat <<EOF
{
    "tag": "${tag}",
    "protocol": "shadowsocks",
    "settings": {
        "servers": [{
            "address": "${host}",
            "port": ${port},
            "method": "${cipher}",
            "password": "${password}"
            ${plugin:+,"plugin":"${plugin}","pluginOpts":"${plugin_opts}"}
        }]
    },
    "mux": {"enabled": false, "concurrency": -1}
}
EOF
}

if [ "$1" = "--parse" ]; then
	shift
	while IFS= read -r line; do
		[ -z "$line" ] && continue
		case "$line" in
			vless://*)
				parsed=$(parse_vless_link "$line")
				generate_vless_outbound "$parsed"
				;;
			trojan://*)
				echo "" >&2
				;;
			ss://*)
				echo "" >&2
				;;
		esac
	done
elif [ -n "$1" ]; then
	case "$1" in
		vless://*)
			parsed=$(parse_vless_link "$1")
			generate_vless_outbound "$parsed"
			;;
	esac
fi
