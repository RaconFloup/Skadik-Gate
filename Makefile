include $(TOPDIR)/rules.mk

PKG_NAME:=skadik-gate
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Skadik <noreply@skadik.dev>
PKG_LICENSE:=AGPL-3.0

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/skadik-gate
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=Skadik-Gate VPN Client for Remnawave
  DEPENDS:=+xray-core +curl +kmod-nft-tproxy +nftables +ip-full
  PKGARCH:=all
endef

define Package/skadik-gate/description
  Skadik-Gate is an OpenWRT VPN client that integrates with Remnawave panel.
  Features include:
  - Subscription-based node management
  - VLESS/Trojan/Shadowsocks protocol support
  - Transparent proxy via TPROXY
  - Per-device routing rules
  - Automatic failover to backup nodes
  - LuCI web interface
endef

define Package/luci-app-skadik-gate
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI App for Skadik-Gate
  DEPENDS:=+skadik-gate +luci-base
  PKGARCH:=all
endef

define Package/luci-app-skadik-gate/description
  LuCI web interface for managing Skadik-Gate VPN client.
  Provides General, Nodes, Rules, Devices and Status pages.
endef

define Build/Compile
endef

define Package/skadik-gate/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/skadik-gate $(1)/etc/config/skadik-gate

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/skadik-gate $(1)/etc/init.d/skadik-gate

	$(INSTALL_DIR) $(1)/etc/cron.d
	$(INSTALL_BIN) ./files/etc/cron.d/skadik-gate $(1)/etc/cron.d/skadik-gate

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/skadik-gate $(1)/etc/uci-defaults/skadik-gate

	$(INSTALL_DIR) $(1)/etc/skadik-gate
	$(INSTALL_CONF) ./files/etc/skadik-gate/*.nft $(1)/etc/skadik-gate/ 2>/dev/null || true

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/skadik-gate $(1)/usr/bin/skadik-gate
	$(INSTALL_BIN) ./files/usr/bin/skadik-gate-sub $(1)/usr/bin/skadik-gate-sub

	$(INSTALL_DIR) $(1)/usr/share/skadik-gate
	$(INSTALL_BIN) ./files/usr/share/skadik-gate/vless-parser.sh $(1)/usr/share/skadik-gate/vless-parser.sh
	$(INSTALL_BIN) ./files/usr/share/skadik-gate/config-gen.sh $(1)/usr/share/skadik-gate/config-gen.sh
	$(INSTALL_BIN) ./files/usr/share/skadik-gate/health-check.sh $(1)/usr/share/skadik-gate/health-check.sh
	$(INSTALL_BIN) ./files/usr/share/skadik-gate/tproxy-setup.sh $(1)/usr/share/skadik-gate/tproxy-setup.sh
endef

define Package/skadik-gate/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	chmod +x /usr/bin/skadik-gate
	chmod +x /usr/bin/skadik-gate-sub
	chmod +x /usr/share/skadik-gate/*.sh
	chmod +x /etc/init.d/skadik-gate
	/etc/init.d/skadik-gate enable
}
endef

define Package/skadik-gate/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/skadik-gate stop 2>/dev/null
	/etc/init.d/skadik-gate disable 2>/dev/null
}
endef

define Package/luci-app-skadik-gate/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luci-app-skadik-gate/luasrc/controller/skadik-gate.lua \
		$(1)/usr/lib/lua/luci/controller/skadik-gate.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/skadik-gate
	$(INSTALL_DATA) ./luci-app-skadik-gate/luasrc/model/cbi/skadik-gate/*.lua \
		$(1)/usr/lib/lua/luci/model/cbi/skadik-gate/

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/skadik-gate
	$(INSTALL_DATA) ./luci-app-skadik-gate/luasrc/view/skadik-gate/*.htm \
		$(1)/usr/lib/lua/luci/view/skadik-gate/
endef

$(eval $(call BuildPackage,skadik-gate))
$(eval $(call BuildPackage,luci-app-skadik-gate))
