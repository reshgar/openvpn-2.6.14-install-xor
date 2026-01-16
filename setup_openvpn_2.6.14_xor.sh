#!/bin/bash
# ============================================================
#  reshrag's OpenVPN XOR Installer
#  Version: 2.6.14 (XOR patched)
#
#  Description:
#    Interactive OpenVPN server installer with XOR obfuscation,
#    based on angristan/openvpn-install and Tunnelblick XOR patches.
#    This script runs angristan's interactive setup first, then
#    replaces the distro OpenVPN with a custom-built, XOR-patched
#    OpenVPN 2.6.14 from source.
#
#  Features:
#    - Step-by-step interactive setup (choose your own options)
#    - XOR obfuscation for bypassing DPI (Deep Packet Inspection)
#    - Latest Tunnelblick XOR patches applied
#    - Systemd service auto-setup
#    - Port 443 by default (HTTPS port, harder to block)
#
#  Usage:
#    curl -O https://raw.githubusercontent.com/reshgar/openvpn-2.6.14-install-xor/master/setup_openvpn_2.6.14_xor.sh
#    chmod +x setup_openvpn_2.6.14_xor.sh
#    sudo ./setup_openvpn_2.6.14_xor.sh
#
#  Credits:
#    Original installer by angristan (MIT License)
#    XOR patches by Tunnelblick
#    Modifications and updates by reshrag
#
#  License:
#    MIT License - see LICENSE file for details.
# ============================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

OPENVPN_VERSION="2.6.14"
TUNNELBLICK_BASE="https://raw.githubusercontent.com/Tunnelblick/Tunnelblick/master/third_party/sources/openvpn/openvpn-${OPENVPN_VERSION}/patches"

PATCHES=(
  "02-tunnelblick-openvpn_xorpatch-a.diff"
  "03-tunnelblick-openvpn_xorpatch-b.diff"
  "04-tunnelblick-openvpn_xorpatch-c.diff"
  "05-tunnelblick-openvpn_xorpatch-d.diff"
  "06-tunnelblick-openvpn_xorpatch-e.diff"
)

# XOR scramble key (change this for your own deployment)
XOR_KEY="9"

echo -e "${GREEN}"
echo "============================================================"
echo "  reshrag's OpenVPN XOR Installer"
echo "  Version: ${OPENVPN_VERSION} with XOR obfuscation"
echo "============================================================"
echo -e "${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] This script must be run as root${NC}"
   exit 1
fi

# === STEP 1: Download angristan's installer ===
echo -e "${YELLOW}[1/10] Downloading angristan's OpenVPN installer...${NC}"
curl -sO https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh
chmod +x openvpn-install.sh

echo
echo -e "${GREEN}>>> Now running angristan's installer interactively.${NC}"
echo -e "${GREEN}>>> Choose your options as needed. When it finishes, this script will continue.${NC}"
echo -e "${YELLOW}>>> TIP: You can choose any port/cipher - we'll add XOR on top of your choices.${NC}"
echo
sleep 2

# FIX: The new version requires 'interactive' command to run the installer
./openvpn-install.sh interactive

# === STEP 2: Detect config directory ===
echo -e "${YELLOW}[2/10] Detecting OpenVPN configuration...${NC}"

if [ -f /etc/openvpn/server/server.conf ]; then
    CONFIG_DIR="/etc/openvpn/server"
    echo -e "${GREEN}[OK] Found config at: ${CONFIG_DIR}${NC}"
elif [ -f /etc/openvpn/server.conf ]; then
    CONFIG_DIR="/etc/openvpn"
    echo -e "${GREEN}[OK] Found config at: ${CONFIG_DIR} (legacy path)${NC}"
else
    echo -e "${RED}[ERROR] OpenVPN config not found. Installation may have failed.${NC}"
    exit 1
fi

# === STEP 3: Add XOR scramble to configs ===
echo -e "${YELLOW}[3/10] Adding XOR obfuscation to configs...${NC}"

# Add XOR scramble directive to server config (if not already present)
if ! grep -q "^scramble xormask" "$CONFIG_DIR/server.conf"; then
    echo "scramble xormask ${XOR_KEY}" >> "$CONFIG_DIR/server.conf"
    echo -e "${GREEN}[OK] Added scramble directive to server.conf${NC}"
else
    echo -e "${GREEN}[OK] Scramble directive already present in server.conf${NC}"
fi

# Add XOR scramble directive to client template (if not already present)
if [ -f "$CONFIG_DIR/client-template.txt" ]; then
    if ! grep -q "^scramble xormask" "$CONFIG_DIR/client-template.txt"; then
        echo "scramble xormask ${XOR_KEY}" >> "$CONFIG_DIR/client-template.txt"
        echo -e "${GREEN}[OK] Added scramble directive to client-template.txt${NC}"
    else
        echo -e "${GREEN}[OK] Scramble directive already present in client-template.txt${NC}"
    fi
fi

# Update any existing client configs in common locations
for ovpn_file in /root/*.ovpn /home/*/*.ovpn; do
    if [ -f "$ovpn_file" ]; then
        if ! grep -q "^scramble xormask" "$ovpn_file"; then
            echo "scramble xormask ${XOR_KEY}" >> "$ovpn_file"
            echo -e "${GREEN}[OK] Updated: $ovpn_file${NC}"
        fi
    fi
done

# === STEP 4: Stop OpenVPN services ===
echo -e "${YELLOW}[4/10] Stopping OpenVPN services...${NC}"
systemctl stop openvpn-server@server 2>/dev/null || true
systemctl stop openvpn@server 2>/dev/null || true
echo -e "${GREEN}[OK] Services stopped${NC}"

# === STEP 5: Remove distro OpenVPN binary ===
echo -e "${YELLOW}[5/10] Removing distro OpenVPN (keeping configs)...${NC}"
apt remove -y openvpn 2>/dev/null || true
rm -f /usr/sbin/openvpn 2>/dev/null || true
echo -e "${GREEN}[OK] Distro OpenVPN removed${NC}"

# === STEP 6: Install build dependencies ===
echo -e "${YELLOW}[6/10] Installing build dependencies...${NC}"
apt update -qq
apt install -y build-essential libssl-dev iproute2 liblz4-dev liblzo2-dev \
               libpam0g-dev libpkcs11-helper1-dev libsystemd-dev resolvconf pkg-config \
               libnl-3-dev libnl-genl-3-dev libcap-ng-dev wget patch
echo -e "${GREEN}[OK] Dependencies installed${NC}"

# === STEP 7: Download, patch, and build OpenVPN ===
echo -e "${YELLOW}[7/10] Building OpenVPN ${OPENVPN_VERSION} with XOR patch...${NC}"

cd /usr/local/src || mkdir -p /usr/local/src && cd /usr/local/src

# Clean up any previous builds
rm -rf "openvpn-${OPENVPN_VERSION}" "openvpn-${OPENVPN_VERSION}.tar.gz"

# Download source
echo "    Downloading source..."
wget -q "https://swupdate.openvpn.org/community/releases/openvpn-${OPENVPN_VERSION}.tar.gz"
tar xzf "openvpn-${OPENVPN_VERSION}.tar.gz"
cd "openvpn-${OPENVPN_VERSION}"

# Download and apply XOR patches
echo "    Downloading and applying XOR patches..."
for patch in "${PATCHES[@]}"; do
    echo "      - ${patch}"
    wget -q "${TUNNELBLICK_BASE}/${patch}"
    patch -p1 < "${patch}" > /dev/null
done

# Configure
echo "    Configuring..."
./configure --enable-static=yes --enable-shared --disable-debug \
            --disable-plugin-auth-pam --disable-dependency-tracking > /dev/null 2>&1

# Build
echo "    Building (this may take 1-2 minutes)..."
make -j"$(nproc)" > /dev/null 2>&1

# Install
echo "    Installing..."
make install > /dev/null 2>&1

echo -e "${GREEN}[OK] OpenVPN ${OPENVPN_VERSION} with XOR patch built and installed${NC}"

# === STEP 8: Create symlink and directories ===
echo -e "${YELLOW}[8/10] Setting up binary and directories...${NC}"

# Create symlink so systemd service can find openvpn
ln -sf /usr/local/sbin/openvpn /usr/sbin/openvpn

# Create required runtime directories
mkdir -p /var/run/openvpn-server
mkdir -p /var/run/openvpn

echo -e "${GREEN}[OK] Symlink and directories created${NC}"

# === STEP 9: Verify XOR patch ===
echo -e "${YELLOW}[9/10] Verifying XOR patch installation...${NC}"

# Check if scramble code exists in the binary
if grep -q "scramble" /usr/local/src/openvpn-${OPENVPN_VERSION}/src/openvpn/options.c 2>/dev/null; then
    echo -e "${GREEN}[OK] XOR patch verified in source code${NC}"
else
    echo -e "${RED}[WARNING] XOR patch may not be properly applied${NC}"
fi

# Show version
echo "    Installed version:"
/usr/local/sbin/openvpn --version | head -2 | sed 's/^/      /'

# === STEP 10: Start OpenVPN service ===
echo -e "${YELLOW}[10/10] Starting OpenVPN service...${NC}"

systemctl daemon-reload
systemctl enable openvpn-server@server 2>/dev/null || true
systemctl restart openvpn-server@server

sleep 3

# Check if service is running
if systemctl is-active --quiet openvpn-server@server; then
    echo -e "${GREEN}[OK] OpenVPN service is running!${NC}"
else
    echo -e "${YELLOW}[WARNING] Service may not have started. Checking logs...${NC}"
    journalctl -u openvpn-server@server -n 10 --no-pager
fi

# Show listening port
LISTEN_PORT=$(ss -tulnp | grep openvpn | awk '{print $5}' | grep -oE '[0-9]+$' | head -1)
if [ -n "$LISTEN_PORT" ]; then
    echo -e "${GREEN}[OK] OpenVPN listening on port: ${LISTEN_PORT}${NC}"
fi

# === DONE ===
echo
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  INSTALLATION COMPLETE!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo
echo -e "${YELLOW}Configuration summary:${NC}"
echo "  - Config directory: ${CONFIG_DIR}"
echo "  - XOR scramble: Enabled (scramble xormask ${XOR_KEY})"
echo "  - Binary location: /usr/local/sbin/openvpn"
echo
echo -e "${YELLOW}Important for censored regions (Turkmenistan, China, Iran):${NC}"
echo "  - XOR obfuscation helps bypass Deep Packet Inspection (DPI)"
echo "  - Consider using port 443 (HTTPS) for better stealth"
echo "  - All client .ovpn files MUST have: scramble xormask ${XOR_KEY}"
echo
echo -e "${YELLOW}Client management:${NC}"
echo "  - Add new client:    ./openvpn-install.sh client add <name>"
echo "  - List clients:      ./openvpn-install.sh client list"
echo "  - Revoke client:     ./openvpn-install.sh client revoke <name>"
echo
echo -e "${YELLOW}Client configs location:${NC}"
echo "  - Template: ${CONFIG_DIR}/client-template.txt"
echo "  - Generated configs: /root/*.ovpn or /home/*/*.ovpn"
echo
echo -e "${GREEN}Enjoy your obfuscated VPN! 🛡️${NC}"
echo