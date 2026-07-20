include $(TOPDIR)/rules.mk

PKG_NAME:=skadik-gate
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Skadik <noreply@skadik.dev>
PKG_LICENSE:=AGPL-3.0

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/RaconFloup/Skadik-Gate.git
PKG_SOURCE_VERSION:=HEAD

include $(INCLUDE_DIR)/package.mk

# ============================================
# Package: skadik-gate (core)
# ============================================
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
  Features: subscription-based nodes, VLESS/Trojan/SS support,
  transparent proxy (TPROXY), per-device routing, failover, CLI.
endef

define Package/skadik-gate/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/files/etc/config/skadik-gate $(1)/etc/config/skadik-gate

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/init.d/skadik-gate $(1)/etc/init.d/skadik-gate

	$(INSTALL_DIR) $(1)/etc/cron.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/cron.d/skadik-gate $(1)/etc/cron.d/skadik-gate

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/uci-defaults/skadik-gate $(1)/etc/uci-defaults/skadik-gate

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/bin/skadik-gate $(1)/usr/bin/skadik-gate
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/bin/skadik-gate-sub $(1)/usr/bin/skadik-gate-sub

	$(INSTALL_DIR) $(1)/usr/share/skadik-gate
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/share/skadik-gate/vless-parser.sh $(1)/usr/share/skadik-gate/vless-parser.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/share/skadik-gate/config-gen.sh $(1)/usr/share/skadik-gate/config-gen.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/share/skadik-gate/health-check.sh $(1)/usr/share/skadik-gate/health-check.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/share/skadik-gate/tproxy-setup.sh $(1)/usr/share/skadik-gate/tproxy-setup.sh
endef

define Package/skadik-gate/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	chmod +x /usr/bin/skadik-gate
	chmod +x /usr/bin/skadik-gate-sub
	chmod +x /usr/share/skadik-gate/*.sh
	chmod +x /etc/init.d/skadik-gate
	mkdir -p /etc/skadik-gate/nodes
	mkdir -p /var/log/skadik-gate
	/etc/init.d/skadik-gate enable 2>/dev/null
}
endef

define Package/skadik-gate/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/skadik-gate stop 2>/dev/null
	/etc/init.d/skadik-gate disable 2>/dev/null
}
endef

# ============================================
# Package: luci-app-skadik-gate
# ============================================
define Package/luci-app-skadik-gate
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI App for Skadik-Gate
  DEPENDS:=+skadik-gate +luci-base +luci-compat
  PKGARCH:=all
endef

define Package/luci-app-skadik-gate/description
  LuCI web interface for managing Skadik-Gate VPN client.
  Provides General, Nodes, Rules, Devices and Status pages.
endef

define Package/luci-app-skadik-gate/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci-app-skadik-gate/luasrc/controller/skadik-gate.lua \
		$(1)/usr/lib/lua/luci/controller/skadik-gate.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/skadik-gate
	for f in $(PKG_BUILD_DIR)/luci-app-skadik-gate/luasrc/model/cbi/skadik-gate/*.lua; do \
		$(INSTALL_DATA) "$$f" $(1)/usr/lib/lua/luci/model/cbi/skadik-gate/ ; \
	done

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/skadik-gate
	for f in $(PKG_BUILD_DIR)/luci-app-skadik-gate/luasrc/view/skadik-gate/*.htm; do \
		$(INSTALL_DATA) "$$f" $(1)/usr/lib/lua/luci/view/skadik-gate/ ; \
	done
endef

$(eval $(call BuildPackage,skadik-gate))
$(eval $(call BuildPackage,luci-app-skadik-gate))
