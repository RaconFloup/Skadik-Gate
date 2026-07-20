#!/bin/bash
# Skadik-Gate: Build .ipk packages on Linux
# Usage: ./build.sh [arch]
# arch: all (default)

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build/ipk"
VERSION="1.0.0"
ARCH="all"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Skadik-Gate Package Builder (Linux)${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

compile_po2lmo() {
    local po_file="$1"
    local lmo_file="$2"
    python3 "${SCRIPT_DIR}/build/po2lmo.py" "$po_file" "$lmo_file"
}

build_ipk() {
    local pkg_name="$1"
    local description="$2"
    local depends="$3"
    local section="$4"
    local build_files_func="$5"

    echo ""
    echo -e "${YELLOW}Building ${pkg_name}...${NC}"

    local pkg_dir="${BUILD_DIR}/${pkg_name}"
    local data_dir="${pkg_dir}/data"
    local control_dir="${pkg_dir}/control"

    rm -rf "${pkg_dir}"
    mkdir -p "${data_dir}" "${control_dir}"

    eval "${build_files_func} '${data_dir}'"

    cat > "${control_dir}/control" <<EOF
Package: ${pkg_name}
Version: ${VERSION}
Depends: ${depends}
Architecture: ${ARCH}
Maintainer: Skadik <noreply@skadik.dev>
Section: ${section}
Source: https://github.com/RaconFloup/Skadik-Gate
Description: ${description}
EOF

    printf '/etc/config/skadik-gate\n/etc/skadik-gate/\n' > "${control_dir}/conffiles"

    cat > "${control_dir}/postinst" <<'POSTINST'
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
POSTINST

    cat > "${control_dir}/prerm" <<'PRERM'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
    /etc/init.d/skadik-gate stop 2>/dev/null
    /etc/init.d/skadik-gate disable 2>/dev/null
}
PRERM

    printf '2.0\n' > "${pkg_dir}/debian-binary"

    pushd "${data_dir}" > /dev/null
    find . -type f | sed 's|^\./||' | tar -czf "${pkg_dir}/data.tar.gz" -T -
    popd > /dev/null

    pushd "${control_dir}" > /dev/null
    tar -czf "${pkg_dir}/control.tar.gz" *
    popd > /dev/null

    local ipk_name="${pkg_name}_${VERSION}_${ARCH}.ipk"
    local ipk_path="${BUILD_DIR}/${ipk_name}"

    pushd "${pkg_dir}" > /dev/null
    tar -czf "${ipk_path}" debian-binary control.tar.gz data.tar.gz
    popd > /dev/null

    local size
    size=$(stat -c%s "${ipk_path}" 2>/dev/null || stat -f%z "${ipk_path}")
    echo -e "${GREEN}OK: ${ipk_name} (${size} bytes)${NC}"
}

build_core() {
    local data_dir="$1"
    mkdir -p "${data_dir}"/{etc/config,etc/init.d,etc/cron.d,etc/uci-defaults,usr/bin,usr/share/skadik-gate}

    cp "${SCRIPT_DIR}/files/etc/config/skadik-gate" "${data_dir}/etc/config/"
    cp "${SCRIPT_DIR}/files/etc/init.d/skadik-gate" "${data_dir}/etc/init.d/"
    cp "${SCRIPT_DIR}/files/etc/cron.d/skadik-gate" "${data_dir}/etc/cron.d/"
    cp "${SCRIPT_DIR}/files/etc/uci-defaults/skadik-gate" "${data_dir}/etc/uci-defaults/"
    cp "${SCRIPT_DIR}/files/usr/bin/skadik-gate" "${data_dir}/usr/bin/"
    cp "${SCRIPT_DIR}/files/usr/bin/skadik-gate-sub" "${data_dir}/usr/bin/"
    cp "${SCRIPT_DIR}/files/usr/share/skadik-gate/"*.sh "${data_dir}/usr/share/skadik-gate/"
}

build_luci() {
    local data_dir="$1"
    mkdir -p "${data_dir}"/{usr/lib/lua/luci/controller,usr/lib/lua/luci/model/cbi/skadik-gate,usr/lib/lua/luci/view/skadik-gate,usr/lib/lua/luci/i18n}

    cp "${SCRIPT_DIR}/luci-app-skadik-gate/luasrc/controller/skadik-gate.lua" "${data_dir}/usr/lib/lua/luci/controller/"
    cp "${SCRIPT_DIR}/luci-app-skadik-gate/luasrc/model/cbi/skadik-gate/"*.lua "${data_dir}/usr/lib/lua/luci/model/cbi/skadik-gate/"
    cp "${SCRIPT_DIR}/luci-app-skadik-gate/luasrc/view/skadik-gate/"*.htm "${data_dir}/usr/lib/lua/luci/view/skadik-gate/"

    echo -e "  Compiling i18n translations..."
    compile_po2lmo "${SCRIPT_DIR}/luci-app-skadik-gate/luasrc/i18n/skadik-gate.en.po" \
                   "${data_dir}/usr/lib/lua/luci/i18n/skadik-gate.en.lmo"
    compile_po2lmo "${SCRIPT_DIR}/luci-app-skadik-gate/luasrc/i18n/skadik-gate.ru.po" \
                   "${data_dir}/usr/lib/lua/luci/i18n/skadik-gate.ru.lmo"
}

build_ipk "skadik-gate" \
    "Skadik-Gate VPN Client for Remnawave panel" \
    "xray-core, curl, kmod-nft-tproxy, nftables, ip-full" \
    "net" \
    "build_core"

build_ipk "luci-app-skadik-gate" \
    "LuCI web interface for Skadik-Gate VPN client" \
    "skadik-gate, luci-base, luci-compat" \
    "luci" \
    "build_luci"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  BUILD COMPLETE${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${CYAN}Packages:${NC}"
ls -la "${BUILD_DIR}"/*.ipk.gz 2>/dev/null | while read line; do
    echo "  $line"
done
