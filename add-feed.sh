#!/bin/sh
# Skadik-Gate: Add package feed to OpenWRT
# Run this on the router to add the Skadik-Gate repository
#
# Usage:
#   wget -O /tmp/add-feed.sh https://raw.githubusercontent.com/RaconFloup/Skadik-Gate/main/add-feed.sh
#   chmod +x /tmp/add-feed.sh
#   /tmp/add-feed.sh

REPO_URL="https://raw.githubusercontent.com/RaconFloup/Skadik-Gate"
FEED_NAME="skadik-gate"
FEED_BASE="${REPO_URL}/gh-pages"

# Detect architecture from OpenWRT
if [ -f /etc/openwrt_release ]; then
    . /etc/openwrt_release
    ARCH="${DISTRIB_TARGET}"
else
    ARCH="x86_64"
fi

# Convert slash to underscore for URL
ARCH_SLUG=$(echo "$ARCH" | tr '/' '_')

# Available architectures in feed
AVAILABLE_ARCHS="aarch64_generic mediatek_filogic x86_64 arm_cortex-a7 mips_24kc"

# Find matching architecture
FOUND=0
for avail in $AVAILABLE_ARCHS; do
    if [ "$avail" = "$ARCH_SLUG" ]; then
        FOUND=1
        break
    fi
done

# Fallback to aarch64_generic if exact match not found
if [ "$FOUND" -eq 0 ]; then
    echo "Architecture ${ARCH_SLUG} not found in feed, using aarch64_generic"
    ARCH_SLUG="aarch64_generic"
fi

echo "Detected architecture: ${ARCH}"
echo "Feed URL: ${FEED_BASE}/${ARCH_SLUG}"

# Check if feed already exists
if grep -q "skadik-gate" /etc/opkg/customfeeds.conf 2>/dev/null || \
   grep -q "skadik-gate" /etc/opkg.conf 2>/dev/null; then
    echo "Feed already configured, updating..."
    sed -i '/skadik-gate/d' /etc/opkg/customfeeds.conf 2>/dev/null
    sed -i '/skadik-gate/d' /etc/opkg.conf 2>/dev/null
fi

# Add feed
echo "src/gz skadik-gate ${FEED_BASE}/${ARCH_SLUG}" >> /etc/opkg/customfeeds.conf 2>/dev/null || \
echo "src/gz skadik-gate ${FEED_BASE}/${ARCH_SLUG}" >> /etc/opkg.conf

echo "Feed added successfully"

# Update package lists
echo "Updating package lists..."
opkg update

echo ""
echo "========================================"
echo "Feed added! Now you can install:"
echo "  opkg install skadik-gate"
echo "  opkg install luci-app-skadik-gate"
echo ""
echo "Or update with:"
echo "  opkg update && opkg upgrade skadik-gate luci-app-skadik-gate"
echo "========================================"
