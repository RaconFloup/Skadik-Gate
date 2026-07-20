#!/bin/bash
# Skadik-Gate: Build script for OpenWRT packages
# Automatically downloads SDK and builds .ipk packages
#
# Usage:
#   ./build.sh                    # Auto-detect architecture
#   ./build.sh x86_64             # Build for x86_64
#   ./build.sh aarch64_generic    # Build for ARM64
#   ./build.sh arm_cortex-a7      # Build for ARM Cortex-A7

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
PACKAGES_DIR="${SCRIPT_DIR}/packages"
OPENWRT_VERSION="24.10.0"
SDK_BASE_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[BUILD]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)      echo "x86/64" ;;
        aarch64)     echo "aarch64/generic" ;;
        armv7l)      echo "arm/cortex-a7" ;;
        *)           err "Unsupported architecture: $arch" ;;
    esac
}

get_sdk_url() {
    local target="$1"
    local sdk_pattern="openwrt-sdk-${OPENWRT_VERSION}-${target//\//_}_gcc-*_musl.Linux-x86_64"
    
    # Try to find the SDK download link
    local page_url="${SDK_BASE_URL}/${target}/"
    log "Looking for SDK at: ${page_url}"
    
    # For x86_64
    if [ "$target" = "x86/64" ]; then
        echo "https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/x86/64/openwrt-sdk-${OPENWRT_VERSION}-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst"
    elif [ "$target" = "aarch64/generic" ]; then
        echo "https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/aarch64/generic/openwrt-sdk-${OPENWRT_VERSION}-aarch64-generic_gcc-13.3.0_musl.Linux-x86_64.tar.zst"
    else
        err "Please provide SDK URL manually for target: $target"
    fi
}

download_sdk() {
    local target="$1"
    local sdk_dir="${BUILD_DIR}/openwrt-sdk"
    
    if [ -d "$sdk_dir" ]; then
        log "SDK already downloaded at ${sdk_dir}"
        return 0
    fi
    
    mkdir -p "$BUILD_DIR"
    
    local sdk_url
    sdk_url=$(get_sdk_url "$target")
    
    log "Downloading SDK from: ${sdk_url}"
    
    local archive="${BUILD_DIR}/sdk.tar.zst"
    curl -L -o "$archive" "$sdk_url" || err "Failed to download SDK"
    
    log "Extracting SDK..."
    cd "$BUILD_DIR"
    
    if command -v zstd &>/dev/null; then
        zstd -d "$archive" -o sdk.tar 2>/dev/null || tar --zstd -xf "$archive"
    else
        tar --zstd -xf "$archive"
    fi
    
    # Find and rename the extracted directory
    local extracted=$(ls -d openwrt-sdk-* 2>/dev/null | head -1)
    if [ -n "$extracted" ]; then
        mv "$extracted" "openwrt-sdk"
    fi
    
    rm -f "$archive"
    log "SDK extracted to ${sdk_dir}"
}

setup_sdk() {
    local sdk_dir="${BUILD_DIR}/openwrt-sdk"
    
    log "Updating SDK feeds..."
    cd "$sdk_dir"
    ./scripts/feeds update -a
    ./scripts/feeds install -a
    
    log "SDK ready"
}

copy_package() {
    local sdk_dir="${BUILD_DIR}/openwrt-sdk"
    local pkg_dir="${sdk_dir}/package/skadik-gate"
    
    log "Copying package sources..."
    mkdir -p "$pkg_dir"
    
    cp -r "${SCRIPT_DIR}/files" "$pkg_dir/"
    cp -r "${SCRIPT_DIR}/luci-app-skadik-gate" "$pkg_dir/"
    cp "${SCRIPT_DIR}/package/Makefile" "$pkg_dir/Makefile"
    
    log "Package sources copied to SDK"
}

build_packages() {
    local sdk_dir="${BUILD_DIR}/openwrt-sdk"
    
    log "Building packages..."
    cd "$sdk_dir"
    
    make package/skadik-gate/compile V=s -j$(nproc) 2>&1 || {
        log "Trying single-threaded build..."
        make package/skadik-gate/compile V=s
    }
    
    log "Build complete!"
}

collect_packages() {
    local sdk_dir="${BUILD_DIR}/openwrt-sdk"
    
    log "Collecting .ipk packages..."
    mkdir -p "$PACKAGES_DIR"
    
    find "$sdk_dir/bin/packages" -name "skadik-gate_*.ipk" -exec cp {} "$PACKAGES_DIR/" \;
    find "$sdk_dir/bin/packages" -name "luci-app-skadik-gate_*.ipk" -exec cp {} "$PACKAGES_DIR/" \;
    
    log "Packages saved to: ${PACKAGES_DIR}"
    ls -la "$PACKAGES_DIR"/*.ipk 2>/dev/null
}

show_usage() {
    cat <<EOF
Skadik-Gate Build Script

Usage: $0 [OPTIONS] [ARCHITECTURE]

Options:
  -h, --help          Show this help
  -c, --clean         Clean build directory
  -s, --sdk-only      Download SDK only (don't build)
  -k, --keep-sdk      Keep SDK after build

Architecture:
  x86_64              For x86_64 routers
  aarch64             For ARM64 routers
  arm_cortex_a7       For ARM Cortex-A7 routers
  auto                Auto-detect (default)

Examples:
  ./build.sh                    # Auto-detect and build
  ./build.sh x86_64             # Build for x86_64
  ./build.sh --clean            # Clean and rebuild
EOF
}

clean_build() {
    log "Cleaning build directory..."
    rm -rf "$BUILD_DIR" "$PACKAGES_DIR"
    log "Clean complete"
}

main() {
    local arch=""
    local sdk_only=0
    local keep_sdk=0
    
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)    show_usage; exit 0 ;;
            -c|--clean)   clean_build; exit 0 ;;
            -s|--sdk-only) sdk_only=1 ;;
            -k|--keep-sdk) keep_sdk=1 ;;
            x86_64)       arch="x86/64" ;;
            aarch64)      arch="aarch64/generic" ;;
            arm_cortex_a7) arch="arm/cortex-a7" ;;
            auto)         arch="" ;;
            *)            err "Unknown option: $1" ;;
        esac
        shift
    done
    
    [ -z "$arch" ] && arch=$(detect_arch)
    
    log "Target architecture: ${arch}"
    
    download_sdk "$arch"
    setup_sdk
    copy_package
    build_packages
    collect_packages
    
    if [ "$keep_sdk" -eq 0 ]; then
        log "Cleaning SDK..."
        rm -rf "${BUILD_DIR}/openwrt-sdk"
    fi
    
    log "=== BUILD COMPLETE ==="
    log "Packages ready in: ${PACKAGES_DIR}"
    log ""
    log "Install on router with:"
    log "  scp ${PACKAGES_DIR}/*.ipk root@router:/tmp/"
    log "  ssh root@router 'opkg install /tmp/skadik-gate_*.ipk /tmp/luci-app-skadik-gate_*.ipk'"
}

main "$@"
