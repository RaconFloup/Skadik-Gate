module("luci.controller.skadik-gate", package.seeall)

function index()
	entry({"admin", "vpn"}, alias("admin", "vpn", "skadik-gate"), _("Skadik-Gate"), 60)
	entry({"admin", "vpn", "skadik-gate"}, firstchild(), _("Skadik-Gate"), 1)
	entry({"admin", "vpn", "skadik-gate", "general"}, cbi("skadik-gate/general"), _("General"), 1)
	entry({"admin", "vpn", "skadik-gate", "nodes"}, cbi("skadik-gate/nodes"), _("Nodes"), 2)
	entry({"admin", "vpn", "skadik-gate", "rules"}, cbi("skadik-gate/rules"), _("Rules"), 3)
	entry({"admin", "vpn", "skadik-gate", "devices"}, cbi("skadik-gate/devices"), _("Devices"), 4)
	entry({"admin", "vpn", "skadik-gate", "status"}, template("skadik-gate/status"), _("Status"), 5)

	entry({"admin", "vpn", "skadik-gate", "action"}, call("action_handler"), nil).leaf = true
	entry({"admin", "vpn", "skadik-gate", "api"}, call("api_handler"), nil)
end

function action_handler()
	local action = luci.http.formvalue("action")
	local result = {}

	if action == "start" then
		luci.sys.call("/etc/init.d/skadik-gate start")
		result.status = "ok"
	elseif action == "stop" then
		luci.sys.call("/etc/init.d/skadik-gate stop")
		result.status = "ok"
	elseif action == "restart" then
		luci.sys.call("/etc/init.d/skadik-gate restart")
		result.status = "ok"
	elseif action == "update_sub" then
		luci.sys.call("/usr/bin/skadik-gate-sub update &")
		result.status = "ok"
	elseif action == "switch_node" then
		local node = luci.http.formvalue("node")
		if node then
			luci.sys.call(string.format("/usr/bin/skadik-gate-sub switch '%s'", node))
			result.status = "ok"
		else
			result.status = "error"
			result.message = "No node specified"
		end
	elseif action == "test_node" then
		local node = luci.http.formvalue("node")
		local output = luci.sys.exec(string.format("/usr/bin/skadik-gate-sub test '%s' 2>&1", node or ""))
		result.status = "ok"
		result.output = output
	elseif action == "health_check" then
		local output = luci.sys.exec("/usr/share/skadik-gate/health-check.sh check 2>&1")
		result.status = "ok"
		result.output = output
	else
		result.status = "error"
		result.message = "Unknown action"
	end

	luci.http.prepare_content("application/json")
	luci.http.write_json(result)
end

function api_handler()
	local path = luci.http.request_uri
	local cmd = path:match("/api/(.+)$")

	if cmd == "status" then
		local running = luci.sys.call("pgrep -f 'xray.*run' >/dev/null 2>&1") == 0
		local active_node = ""
		local f = io.open("/etc/skadik-gate/nodes/.active", "r")
		if f then
			active_node = f:read("*l") or ""
			f:close()
		end

		luci.http.prepare_content("application/json")
		luci.http.write_json({
			running = running,
			active_node = active_node,
			version = "1.0.0"
		})
	end
end
