local m, s, o

m = Map("skadik-gate", translate("Skadik-Gate - Device Rules"),
	translate("Control which LAN devices go through VPN and which go direct."))

s = m:section(TypedSection, "skadik-gate_device", translate("Device Rules"),
	translate("Specify MAC addresses of devices and their routing policy."))
s.anonymous = true
s.addremove = true
s.sortable = true
s.template = "cbi/tblsection"

o = s:option(Flag, "enabled", translate("Enabled"))
o.default = "1"
o.width = "5%"

o = s:option(Value, "name", translate("Name"),
	translate("Device name for identification"))
o.rmempty = false
o.width = "15%"

o = s:option(Value, "mac", translate("MAC Address"),
	translate("MAC address of the device (e.g. AA:BB:CC:DD:EE:FF)"))
o.datatype = "macaddr"
o.rmempty = false
o.width = "20%"

o = s:option(Value, "ip", translate("IP Address"),
	translate("Optional: specific IP address of the device"))
o.datatype = "ipaddr"
o.width = "15%"

o = s:option(ListValue, "action", translate("Action"),
	translate("Route this device through VPN or direct"))
o:value("proxy", translate("Proxy (through VPN)"))
o:value("direct", translate("Direct (bypass VPN)"))
o.rmempty = false
o.width = "10%"

s2 = m:section(TypedSection, "skadik-gate", translate("Info"))
s2.anonymous = true
s2.addremove = false

o = s2:option(DummyValue, "_info", translate("Notes"))
o.rawhtml = true
o.value = [[<div style="padding: 10px; background: #f0f0f0; border-radius: 5px; margin-top: 10px;">
<strong>How device rules work:</strong>
<ul style="margin: 5px 0;">
<li><strong>Proxy:</strong> All traffic from this device goes through the VPN tunnel</li>
<li><strong>Direct:</strong> All traffic from this device bypasses VPN and goes direct</li>
<li>Devices not listed here follow the general routing rules</li>
<li>MAC addresses are matched against the source MAC of LAN packets</li>
</ul>
<strong>Tip:</strong> You can find device MAC addresses in LuCI → Network → DHCP/DNS → Leases
</div>]]

return m
