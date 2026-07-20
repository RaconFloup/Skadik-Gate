local m, s, o

m = Map("skadik-gate", translate("Skadik-Gate - General"),
	translate("Configure the Skadik-Gate VPN client for OpenWRT."))

s = m:section(TypedSection, "skadik-gate", translate("General Settings"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("Enable"),
	translate("Enable or disable the Skadik-Gate service"))
o.default = "0"
o.rmempty = false

o = s:option(Value, "subscription_url", translate("Subscription URL"),
	translate("Remnawave subscription URL (e.g. https://panel.com/api/v1/client/subscribe?token=xxx)"))
o.datatype = "url"
o.rmempty = false
o.size = 80

o = s:option(Button, "fetch_sub", translate("Fetch Subscription"),
	translate("Download and parse the subscription"))
o.inputtitle = translate("Fetch Subscription")
o.inputstyle = "apply"
o.write = function(self, section)
	luci.sys.call("/usr/bin/skadik-gate-sub update &")
	luci.http.redirect(luci.dispatcher.build_url("admin", "vpn", "skadik-gate", "general"))
end

s2 = m:section(TypedSection, "skadik-gate", translate("Service Settings"))
s2.anonymous = true
s2.addremove = false

o = s2:option(ListValue, "tproxy_port", translate("TPROXY Port"),
	translate("Port for transparent proxy"))
o:value("7893", "7893 (default)")
o:value("12345", "12345")
o.default = "7893"

o = s2:option(ListValue, "dns_port", translate("DNS Port"),
	translate("Port for DNS forwarding"))
o:value("7874", "7874 (default)")
o:value("5353", "5353")
o.default = "7874"

o = s2:option(ListValue, "socks_port", translate("SOCKS Port"),
	translate("Port for SOCKS5 proxy"))
o:value("7875", "7875 (default)")
o:value("10808", "10808")
o.default = "7875"

o = s2:option(ListValue, "xray_log_level", translate("Xray Log Level"),
	translate("Logging verbosity of xray-core"))
o:value("none", translate("None"))
o:value("error", translate("Error"))
o:value("warning", translate("Warning"))
o:value("info", translate("Info"))
o:value("debug", translate("Debug"))
o.default = "warning"

o = s2:option(Flag, "auto_update", translate("Auto Update"),
	translate("Automatically update subscription"))
o.default = "0"

o = s2:option(Value, "update_interval", translate("Update Interval (seconds)"),
	translate("How often to check for subscription updates"))
o.datatype = "min(300)"
o.default = "3600"
o:depends("auto_update", "1")

s3 = m:section(TypedSection, "skadik-gate", translate("Failover Settings"))
s3.anonymous = true
s3.addremove = false

o = s3:option(Flag, "failover_enabled", translate("Enable Failover"),
	translate("Automatically switch to backup node when primary is unreachable"))
o.default = "1"

o = s3:option(Flag, "health_check", translate("Health Check"),
	translate("Periodically check node connectivity"))
o.default = "1"

o = s3:option(Value, "health_interval", translate("Health Check Interval (seconds)"),
	translate("How often to check node health"))
o.datatype = "min(10)"
o.default = "60"
o:depends("health_check", "1")

o = s3:option(Value, "health_timeout", translate("Health Check Timeout (seconds)"),
	translate("Timeout for connectivity check"))
o.datatype = "min(1)"
o.default = "5"
o:depends("health_check", "1")

return m
