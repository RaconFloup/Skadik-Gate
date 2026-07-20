local m, s, o

m = Map("skadik-gate", translate("Skadik-Gate - Nodes"),
	translate("Manage VPN server nodes from your subscription."))

s = m:section(TypedSection, "skadik-gate_node", translate("Available Nodes"),
	translate("Nodes are automatically populated from your subscription."))
s.anonymous = true
s.addremove = true
s.sortable = true

o = s:option(Flag, "enabled", translate("Enabled"))
o.default = "1"

o = s:option(Value, "name", translate("Name"),
	translate("Display name for this node"))
o.rmempty = false

o = s:option(ListValue, "role", translate("Role"),
	translate("Primary or backup node"))
o:value("primary", translate("Primary"))
o:value("backup", translate("Backup"))
o.default = "primary"

o = s:option(DummyValue, "_status", translate("Status"))
o.width = "10%"
o.textfunction = function(self, section)
	local name = luci.model.uci:get("skadik-gate", section, "name")
	local output = luci.sys.exec(string.format(
		"/usr/bin/skadik-gate-sub test '%s' 2>&1", name or ""
	))
	if output and output:find("OK") then
		return '<span style="color:green">ONLINE</span>'
	else
		return '<span style="color:red">OFFLINE</span>'
	end
end

s2 = m:section(TypedSection, "skadik-gate", translate("Subscription"))
s2.anonymous = true
s2.addremove = false

o = s2:option(Button, "update_sub", translate("Update Subscription"))
o.inputtitle = translate("Refresh Nodes")
o.inputstyle = "apply"
o.write = function(self, section)
	luci.sys.call("/usr/bin/skadik-gate-sub update &")
	luci.http.redirect(luci.dispatcher.build_url("admin", "vpn", "skadik-gate", "nodes"))
end

o = s2:option(Button, "test_all", translate("Test All Nodes"))
o.inputtitle = translate("Test Connectivity")
o.inputstyle = "reload"
o.write = function(self, section)
	luci.http.redirect(luci.dispatcher.build_url("admin", "vpn", "skadik-gate", "nodes"))
end

return m
