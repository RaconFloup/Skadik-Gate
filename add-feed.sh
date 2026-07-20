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

# Detect architecture
ARCH=$(. /etc/openwrt_release 2>/dev/null && echo "$DISTRIB_TARGET" || echo "x86/64")
ARCH_SLUG=$(echo "$ARCH" | tr '/' '_')

echo "Detected architecture: ${ARCH}"
echo "Feed URL: ${FEED_BASE}/${ARCH_SLUG}"

# Check if feed already exists
if grep -q "skadik-gate" /etc/opkg/customfeeds.conf 2>/dev/null || \
   grep -q "skadik-gate" /etc/opkg.conf 2>/dev/null; then
    echo "Feed already configured"
else
    # Add feed
    echo "src/gz skadik-gate ${FEED_BASE}/${ARCH_SLUG}" >> /etc/opkg/customfeeds.conf 2>/dev/null || \
    echo "src/gz skadik-gate ${FEED_BASE}/${ARCH_SLUG}" >> /etc/opkg.conf
    
    echo "Feed added successfully"
fi

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
