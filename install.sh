#!/bin/sh
# Skadik-Gate: Quick install script for OpenWRT router
# Run this on the router to install manually without SDK
#
# Usage:
#   wget -O /tmp/install.sh https://raw.githubusercontent.com/RaconFloup/Skadik-Gate/main/install.sh
#   chmod +x /tmp/install.sh
#   /tmp/install.sh

set -e

REPO_URL="https://raw.githubusercontent.com/RaconFloup/Skadik-Gate/main"
INSTALL_DIR="/"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }

check_root() {
    [ "$(id -u)" -eq 0 ] || err "Run as root"
}

check_openwrt() {
    [ -f /etc/openwrt_release ] || err "Not an OpenWRT system"
    log "OpenWRT detected: $(cat /etc/openwrt_release)"
}

install_deps() {
    log "Installing dependencies..."
    opkg update 2>/dev/null || true
    
    local pkgs=""
    for pkg in xray-core curl kmod-nft-tproxy nftables ip-full luci-base luci-compat; do
        if ! opkg list-installed | grep -q "^${pkg} "; then
            pkgs="${pkgs} ${pkg}"
        fi
    done
    
    if [ -n "$pkgs" ]; then
        log "Installing missing packages:${pkgs}"
        opkg install $pkgs || warn "Some packages may have failed to install"
    else
        ok "All dependencies already installed"
    fi
}

download_file() {
    local path="$1"
    local dest="$2"
    local url="${REPO_URL}/${path}"
    
    log "Downloading ${path}..."
    wget -q -O "${dest}" "${url}" 2>/dev/null || {
        warn "wget failed, trying curl..."
        curl -sS -L --connect-timeout 10 --max-time 30 -o "${dest}" "${url}" || err "Failed to download ${path}"
    }
}

install_files() {
    log "Installing Skadik-Gate..."
    
    # Create directories
    mkdir -p /etc/skadik-gate/nodes
    mkdir -p /etc/cron.d
    mkdir -p /etc/uci-defaults
    mkdir -p /usr/share/skadik-gate
    mkdir -p /var/log/skadik-gate
    
    # Core config
    download_file "files/etc/config/skadik-gate" "/etc/config/skadik-gate"
    
    # Init script
    download_file "files/etc/init.d/skadik-gate" "/etc/init.d/skadik-gate"
    chmod +x /etc/init.d/skadik-gate
    
    # Cron
    download_file "files/etc/cron.d/skadik-gate" "/etc/cron.d/skadik-gate"
    
    # UCI defaults
    download_file "files/etc/uci-defaults/skadik-gate" "/etc/uci-defaults/skadik-gate"
    chmod +x /etc/uci-defaults/skadik-gate
    
    # CLI binaries
    download_file "files/usr/bin/skadik-gate" "/usr/bin/skadik-gate"
    download_file "files/usr/bin/skadik-gate-sub" "/usr/bin/skadik-gate-sub"
    chmod +x /usr/bin/skadik-gate
    chmod +x /usr/bin/skadik-gate-sub
    
    # Library scripts
    for script in vless-parser.sh config-gen.sh health-check.sh tproxy-setup.sh; do
        download_file "files/usr/share/skadik-gate/${script}" "/usr/share/skadik-gate/${script}"
        chmod +x "/usr/share/skadik-gate/${script}"
    done
    
    ok "Files installed"
}

install_luci() {
    log "Installing LuCI interface..."
    
    mkdir -p /usr/lib/lua/luci/controller
    mkdir -p /usr/lib/lua/luci/model/cbi/skadik-gate
    mkdir -p /usr/lib/lua/luci/view/skadik-gate
    mkdir -p /usr/lib/lua/luci/i18n
    
    download_file "luci-app-skadik-gate/luasrc/controller/skadik-gate.lua" \
        "/usr/lib/lua/luci/controller/skadik-gate.lua"
    
    for model in general nodes rules devices; do
        download_file "luci-app-skadik-gate/luasrc/model/cbi/skadik-gate/${model}.lua" \
            "/usr/lib/lua/luci/model/cbi/skadik-gate/${model}.lua"
    done
    
    download_file "luci-app-skadik-gate/luasrc/view/skadik-gate/status.htm" \
        "/usr/lib/lua/luci/view/skadik-gate/status.htm"
    
    ok "LuCI interface installed"
}

enable_service() {
    /etc/init.d/skadik-gate enable 2>/dev/null || true
    ok "Service enabled"
}

show_info() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Skadik-Gate installed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "Next steps:"
    echo -e "  ${YELLOW}1.${NC} Set your subscription URL:"
    echo -e "     skadik-gate config set main.subscription_url 'https://panel.com/api/v1/client/subscribe?token=XXX'"
    echo ""
    echo -e "  ${YELLOW}2.${NC} Fetch subscription:"
    echo -e "     skadik-gate sub update"
    echo ""
    echo -e "  ${YELLOW}3.${NC} List available nodes:"
    echo -e "     skadik-gate sub list"
    echo ""
    echo -e "  ${YELLOW}4.${NC} Start VPN:"
    echo -e "     skadik-gate start"
    echo ""
    echo -e "  ${YELLOW}5.${NC} Or access LuCI web interface:"
    echo -e "     http://$(uci get network.lan.ipaddr 2>/dev/null || echo 'router-ip')/cgi-bin/luci/admin/vpn/skadik-gate"
    echo ""
}

main() {
    log "Skadik-Gate Installer for OpenWRT"
    echo ""
    
    check_root
    check_openwrt
    install_deps
    install_files
    install_luci
    enable_service
    show_info
}

main "$@"
