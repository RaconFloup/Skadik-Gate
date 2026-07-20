local m, s, o

m = Map("skadik-gate", translate("Skadik-Gate - Routing Rules"),
	translate("Configure how traffic is routed: through VPN, directly, or blocked."))

s = m:section(TypedSection, "skadik-gate_rule", translate("Routing Rules"),
	translate("Rules are evaluated from top to bottom. First matching rule wins."))
s.anonymous = true
s.addremove = true
s.sortable = true
s.template = "cbi/tblsection"

o = s:option(Flag, "enabled", translate("Enabled"))
o.default = "1"
o.width = "5%"

o = s:option(Value, "name", translate("Name"),
	translate("Human-readable rule name"))
o.rmempty = false
o.width = "15%"

o = s:option(ListValue, "action", translate("Action"),
	translate("What to do with matching traffic"))
o:value("proxy", translate("Proxy (through VPN)"))
o:value("direct", translate("Direct (bypass VPN)"))
o:value("block", translate("Block (deny)"))
o.rmempty = false
o.width = "10%"

o = s:option(ListValue, "type", translate("Match Type"),
	translate("Type of traffic to match"))
o:value("domain", translate("Domain"))
o:value("cidr", translate("IP/CIDR"))
o:value("geosite", translate("GeoSite List"))
o:value("geoip", translate("GeoIP List"))
o:value("destination", translate("Destination"))
o:value("default", translate("Default (catch-all)"))
o.rmempty = false
o.width = "12%"

o = s:option(TextValue, "value", translate("Value"),
	translate("Comma-separated values. For GeoSite/GeoIP use list name (e.g. category-ads-all, cn, private)."))
o.rmempty = false
o.rows = 3
o.cols = 50

s2 = m:section(TypedSection, "skadik-gate", translate("Quick Rules"))
s2.anonymous = true
s2.addremove = false

o = s2:option(Button, "add_ads_block", translate("Block Ads"))
o.inputtitle = translate("Add Ad Block Rule")
o.inputstyle = "apply"
o.write = function(self, section)
	uci:set("skadik-gate", uci.add("skadik-gate", "rule"), "name", translate("Ads"))
	uci:set("skadik-gate", uci.section(-1), "enabled", "1")
	uci:set("skadik-gate", uci.section(-1), "action", "block")
	uci:set("skadik-gate", uci.section(-1), "type", "geosite")
	uci:set("skadik-gate", uci.section(-1), "value", "category-ads-all")
	uci.commit("skadik-gate")
	luci.http.redirect(luci.dispatcher.build_url("admin", "vpn", "skadik-gate", "rules"))
end

o = s2:option(Button, "add_china_direct", translate("China Direct"))
o.inputtitle = translate("Add China Direct Rule")
o.inputstyle = "apply"
o.write = function(self, section)
	uci:set("skadik-gate", uci.add("skadik-gate", "rule"), "name", translate("China Direct"))
	uci:set("skadik-gate", uci.section(-1), "enabled", "1")
	uci:set("skadik-gate", uci.section(-1), "action", "direct")
	uci:set("skadik-gate", uci.section(-1), "type", "geosite")
	uci:set("skadik-gate", uci.section(-1), "value", "cn")
	uci.commit("skadik-gate")
	luci.http.redirect(luci.dispatcher.build_url("admin", "vpn", "skadik-gate", "rules"))
end

o = s2:option(Button, "add_private_direct", translate("Private Networks"))
o.inputtitle = translate("Add Private Network Rule")
o.inputstyle = "apply"
o.write = function(self, section)
	uci:set("skadik-gate", uci.add("skadik-gate", "rule"), "name", translate("Private Networks"))
	uci:set("skadik-gate", uci.section(-1), "enabled", "1")
	uci:set("skadik-gate", uci.section(-1), "action", "direct")
	uci:set("skadik-gate", uci.section(-1), "type", "cidr")
	uci:set("skadik-gate", uci.section(-1), "value", "192.168.0.0/16,10.0.0.0/8,172.16.0.0/12")
	uci.commit("skadik-gate")
	luci.http.redirect(luci.dispatcher.build_url("admin", "vpn", "skadik-gate", "rules"))
end

return m
