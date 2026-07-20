#!/bin/sh
# Skadik-Gate: Package builder without full SDK
# Creates .ipk packages from source files directly
#
# This script creates .ipk packages without needing the full OpenWRT SDK.
# The resulting packages can be installed with: opkg install *.ipk
#
# Usage: ./build-ipk.sh [architecture]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build/ipk"
VERSION="1.0.0"
ARCH="${1:-all}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[BUILD]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

check_deps() {
    for cmd in tar gzip ar; do
        command -v "$cmd" >/dev/null 2>&1 || err "Missing: $cmd"
    done
}

create_ipk() {
    local pkg_name="$1"
    local pkg_dir="${BUILD_DIR}/${pkg_name}"
    local data_dir="${pkg_dir}/data"
    local control_dir="${pkg_dir}/control"
    
    mkdir -p "$data_dir" "$control_dir"
    
    echo "$pkg_name" > "${pkg_dir}/name"
    echo "$VERSION" > "${pkg_dir}/version"
    echo "$ARCH" > "${pkg_dir}/arch"
    
    return "$data_dir"
}

build_skadik_gate() {
    log "Building skadik-gate..."
    
    local pkg_dir="${BUILD_DIR}/skadik-gate"
    local data_dir="${pkg_dir}/data"
    local control_dir="${pkg_dir}/control"
    
    rm -rf "$pkg_dir"
    mkdir -p "$data_dir" "$control_dir"
    
    # Copy files
    mkdir -p "${data_dir}/etc/config"
    mkdir -p "${data_dir}/etc/init.d"
    mkdir -p "${data_dir}/etc/cron.d"
    mkdir -p "${data_dir}/etc/uci-defaults"
    mkdir -p "${data_dir}/usr/bin"
    mkdir -p "${data_dir}/usr/share/skadik-gate"
    
    cp "${SCRIPT_DIR}/files/etc/config/skadik-gate" "${data_dir}/etc/config/"
    cp "${SCRIPT_DIR}/files/etc/init.d/skadik-gate" "${data_dir}/etc/init.d/"
    cp "${SCRIPT_DIR}/files/etc/cron.d/skadik-gate" "${data_dir}/etc/cron.d/"
    cp "${SCRIPT_DIR}/files/etc/uci-defaults/skadik-gate" "${data_dir}/etc/uci-defaults/"
    cp "${SCRIPT_DIR}/files/usr/bin/skadik-gate" "${data_dir}/usr/bin/"
    cp "${SCRIPT_DIR}/files/usr/bin/skadik-gate-sub" "${data_dir}/usr/bin/"
    cp "${SCRIPT_DIR}/files/usr/share/skadik-gate/"*.sh "${data_dir}/usr/share/skadik-gate/"
    
    chmod +x "${data_dir}/etc/init.d/skadik-gate"
    chmod +x "${data_dir}/etc/uci-defaults/skadik-gate"
    chmod +x "${data_dir}/usr/bin/skadik-gate"
    chmod +x "${data_dir}/usr/bin/skadik-gate-sub"
    chmod +x "${data_dir}/usr/share/skadik-gate/"*.sh
    
    # Create control file
    cat > "${control_dir}/control" <<EOF
Package: skadik-gate
Version: ${VERSION}
Depends: xray-core, curl, kmod-nft-tproxy, nftables, ip-full
Architecture: ${ARCH}
Maintainer: Skadik <noreply@skadik.dev>
Section: net
Source: https://github.com/RaconFloup/Skadik-Gate
Description: Skadik-Gate VPN Client for Remnawave panel
 Features: subscription-based nodes, VLESS/Trojan/SS support,
 transparent proxy (TPROXY), per-device routing, failover, CLI.
EOF

    # Create conffiles
    cat > "${control_dir}/conffiles" <<EOF
/etc/config/skadik-gate
/etc/skadik-gate/
EOF

    # Create postinst
    cat > "${control_dir}/postinst" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
    chmod +x /usr/bin/skadik-gate 2>/dev/null
    chmod +x /usr/bin/skadik-gate-sub 2>/dev/null
    chmod +x /usr/share/skadik-gate/*.sh 2>/dev/null
    chmod +x /etc/init.d/skadik-gate 2>/dev/null
    mkdir -p /etc/skadik-gate/nodes
    mkdir -p /var/log/skadik-gate
    /etc/init.d/skadik-gate enable 2>/dev/null
}
EOF
    chmod +x "${control_dir}/postinst"
    
    # Create prerm
    cat > "${control_dir}/prerm" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
    /etc/init.d/skadik-gate stop 2>/dev/null
    /etc/init.d/skadik-gate disable 2>/dev/null
}
EOF
    chmod +x "${control_dir}/prerm"
    
    # Build .ipk
    local ipk_name="skadik-gate_${VERSION}_${ARCH}.ipk"
    
    cd "$pkg_dir"
    tar czf "${pkg_dir}/data.tar.gz" -C data .
    tar czf "${pkg_dir}/control.tar.gz" -C control .
    
    echo "2.0" > "${pkg_dir}/debian-binary"
    
    ar r "${BUILD_DIR}/${ipk_name}" \
        "${pkg_dir}/debian-binary" \
        "${pkg_dir}/control.tar.gz" \
        "${pkg_dir}/data.tar.gz" 2>/dev/null || \
    tar -cf - -C "$pkg_dir" debian-binary control.tar.gz data.tar.gz | gzip -9 > "${BUILD_DIR}/${ipk_name}"
    
    cd "$SCRIPT_DIR"
    
    ok "Built: ${BUILD_DIR}/${ipk_name}"
}

build_luci_app() {
    log "Building luci-app-skadik-gate..."
    
    local pkg_dir="${BUILD_DIR}/luci-app-skadik-gate"
    local data_dir="${pkg_dir}/data"
    local control_dir="${pkg_dir}/control"
    
    rm -rf "$pkg_dir"
    mkdir -p "$data_dir" "$control_dir"
    
    mkdir -p "${data_dir}/usr/lib/lua/luci/controller"
    mkdir -p "${data_dir}/usr/lib/lua/luci/model/cbi/skadik-gate"
    mkdir -p "${data_dir}/usr/lib/lua/luci/view/skadik-gate"
    
    cp "${SCRIPT_DIR}/luci-app-skadik-gate/luasrc/controller/skadik-gate.lua" \
        "${data_dir}/usr/lib/lua/luci/controller/"
    
    cp "${SCRIPT_DIR}/luci-app-skadik-gate/luasrc/model/cbi/skadik-gate/"*.lua \
        "${data_dir}/usr/lib/lua/luci/model/cbi/skadik-gate/"
    
    cp "${SCRIPT_DIR}/luci-app-skadik-gate/luasrc/view/skadik-gate/"*.htm \
        "${data_dir}/usr/lib/lua/luci/view/skadik-gate/"
    
    # Control file
    cat > "${control_dir}/control" <<EOF
Package: luci-app-skadik-gate
Version: ${VERSION}
Depends: skadik-gate, luci-base, luci-compat
Architecture: ${ARCH}
Maintainer: Skadik <noreply@skadik.dev>
Section: luci
Source: https://github.com/RaconFloup/Skadik-Gate
Description: LuCI web interface for Skadik-Gate VPN client
 Provides General, Nodes, Rules, Devices and Status pages
 for managing Skadik-Gate VPN client.
EOF

    local ipk_name="luci-app-skadik-gate_${VERSION}_${ARCH}.ipk"
    
    cd "$pkg_dir"
    tar czf "${pkg_dir}/data.tar.gz" -C data .
    tar czf "${pkg_dir}/control.tar.gz" -C control .
    
    echo "2.0" > "${pkg_dir}/debian-binary"
    
    ar r "${BUILD_DIR}/${ipk_name}" \
        "${pkg_dir}/debian-binary" \
        "${pkg_dir}/control.tar.gz" \
        "${pkg_dir}/data.tar.gz" 2>/dev/null || \
    tar -cf - -C "$pkg_dir" debian-binary control.tar.gz data.tar.gz | gzip -9 > "${BUILD_DIR}/${ipk_name}"
    
    cd "$SCRIPT_DIR"
    
    ok "Built: ${BUILD_DIR}/${ipk_name}"
}

show_output() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Packages built successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "Files in ${BUILD_DIR}:"
    ls -la "${BUILD_DIR}"/*.ipk 2>/dev/null
    echo ""
    echo -e "Install on OpenWRT router:"
    echo -e "  ${YELLOW}scp ${BUILD_DIR}/*.ipk root@router:/tmp/${NC}"
    echo -e "  ${YELLOW}ssh root@router 'opkg install /tmp/*.ipk'${NC}"
    echo ""
    echo -e "Or use the install script:"
    echo -e "  ${YELLOW}wget -O- https://raw.githubusercontent.com/RaconFloup/Skadik-Gate/main/install.sh | sh${NC}"
    echo ""
}

main() {
    check_deps
    
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    
    log "Building packages for architecture: ${ARCH}"
    
    build_skadik_gate
    build_luci_app
    
    show_output
}

main "$@"
