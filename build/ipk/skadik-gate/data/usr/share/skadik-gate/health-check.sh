#!/bin/sh
# Skadik-Gate: Health check for nodes with failover support

. /lib/functions.sh

SG_CONF_DIR="/etc/skadik-gate"
SG_NODES_DIR="${SG_CONF_DIR}/nodes"
SG_BIN="/usr/share/skadik-gate"
SG_LOG="/tmp/skadik-gate-health.log"

log() { logger -t skadik-gate-health "$@"; }

get_primary_node() {
	local f
	for f in "${SG_NODES_DIR}"/*.outbound; do
		[ -f "$f" ] || continue
		local name
		name=$(basename "$f" .outbound)
		echo "$name"
		return 0
	done
	echo ""
}

check_node() {
	local node_name="$1"
	local node_file="${SG_NODES_DIR}/${node_name}.outbound"
	[ -f "$node_file" ] || return 1

	local host port
	host=$(sed -n 's/.*"address": "\([^"]*\)".*/\1/p' "$node_file" | head -1)
	port=$(sed -n 's/.*"port": \([0-9]*\).*/\1/p' "$node_file" | head -1)

	[ -z "$host" ] || [ -z "$port" ] && return 1

	config_load skadik-gate
	local health_timeout
	config_get health_timeout main health_timeout "5"

	if nc -z -w "$health_timeout" "$host" "$port" 2>/dev/null; then
		return 0
	else
		return 1
	fi
}

health_check_loop() {
	config_load skadik-gate
	local enabled failover_enabled health_interval
	config_get_bool enabled main enabled 0
	config_get_bool failover_enabled main failover_enabled 1
	config_get health_interval main health_interval 60

	[ "$enabled" -eq 1 ] || return 0
	[ "$failover_enabled" -eq 1 ] || return 0

	while true; do
		local current_node
		current_node=$(cat "${SG_NODES_DIR}/.active" 2>/dev/null)

		if [ -n "$current_node" ]; then
			if ! check_node "$current_node"; then
				log "WARN: Node '${current_node}' is unreachable"

				local backup_node=""
				for f in "${SG_NODES_DIR}"/*.outbound; do
					[ -f "$f" ] || continue
					local candidate
					candidate=$(basename "$f" .outbound)
					[ "$candidate" = "$current_node" ] && continue

					if check_node "$candidate"; then
						backup_node="$candidate"
						break
					fi
				done

				if [ -n "$backup_node" ]; then
					log "Switching to backup node: ${backup_node}"
					echo "$backup_node" > "${SG_NODES_DIR}/.active"
					"${SG_BIN}/config-gen.sh" generate 2>/dev/null
					/etc/init.d/skadik-gate restart 2>/dev/null
				else
					log "ERROR: No reachable nodes found"
				fi
			else
				local primary
				primary=$(get_primary_node)
				if [ -n "$primary" ] && [ "$current_node" != "$primary" ]; then
					if check_node "$primary"; then
						log "Primary node '${primary}' is back, switching..."
						echo "$primary" > "${SG_NODES_DIR}/.active"
						"${SG_BIN}/config-gen.sh" generate 2>/dev/null
						/etc/init.d/skadik-gate restart 2>/dev/null
					fi
				fi
			fi
		fi

		sleep "$health_interval"
	done
}

case "${1:-check}" in
	check)
		config_load skadik-gate
		local current_node
		current_node=$(cat "${SG_NODES_DIR}/.active" 2>/dev/null)
		if [ -n "$current_node" ]; then
			if check_node "$current_node"; then
				echo "OK: ${current_node} is reachable"
			else
				echo "FAIL: ${current_node} is unreachable"
				exit 1
			fi
		else
			echo "No active node"
			exit 1
		fi
		;;
	loop)
		health_check_loop
		;;
	status)
		for f in "${SG_NODES_DIR}"/*.outbound; do
			[ -f "$f" ] || continue
			local name
			name=$(basename "$f" .outbound)
			if check_node "$name"; then
				echo "  ${name}: OK"
			else
				echo "  ${name}: UNREACHABLE"
			fi
		done
		;;
	*)
		echo "Usage: $0 {check|loop|status}"
		exit 1
		;;
esac
