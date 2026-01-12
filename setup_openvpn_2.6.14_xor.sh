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
#    - XOR obfuscation for bypassing DPI
#    - Latest Tunnelblick XOR patches applied
#    - Systemd service auto-setup
#
#  Credits:
#    Original installer by angristan (MIT License)
#    XOR patches by Tunnelblick
#    Modifications and updates by reshrag
#
#  License:
#    MIT License  see LICENSE file for details.
# ============================================================

set -e

OPENVPN_VERSION="2.6.14"
TUNNELBLICK_BASE="https://raw.githubusercontent.com/Tunnelblick/Tunnelblick/master/third_party/sources/openvpn/openvpn-${OPENVPN_VERSION}/patches"

PATCHES=(
  "02-tunnelblick-openvpn_xorpatch-a.diff"
  "03-tunnelblick-openvpn_xorpatch-b.diff"
  "04-tunnelblick-openvpn_xorpatch-c.diff"
  "05-tunnelblick-openvpn_xorpatch-d.diff"
  "06-tunnelblick-openvpn_xorpatch-e.diff"
)

# === STEP 1: Download angristan's installer ===
echo "[*] Downloading angristan's OpenVPN installer..."
curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh
chmod +x openvpn-install.sh

echo
echo ">>> Now running angristan's installer interactively."
echo ">>> Choose your options as needed. When it finishes, this script will continue."
echo

# FIX: The new version requires 'interactive' command to run the interactive installer
./openvpn-install.sh interactive

# === STEP 2: Modify configs after angristan install ===
# FIX: Config files are now in /etc/openvpn/server/ directory (not /etc/openvpn/)
echo "[*] Adjusting OpenVPN configs..."

# Check if config exists in new location
if [ -f /etc/openvpn/server/server.conf ]; then
    CONFIG_DIR="/etc/openvpn/server"
elif [ -f /etc/openvpn/server.conf ]; then
    # Fallback for older versions
    CONFIG_DIR="/etc/openvpn"
else
    echo "[!] Error: OpenVPN config not found. Installation may have failed."
    exit 1
fi

echo "[*] Using config directory: $CONFIG_DIR"

# Change port to 443 (common HTTPS port, harder to block)
sed -i "s/^port .*/port 443/" "$CONFIG_DIR/server.conf"

# Update client template with new port
sed -i 's/1194/443/g' "$CONFIG_DIR/client-template.txt"

# Add XOR scramble directive to server config
if ! grep -q "scramble xormask" "$CONFIG_DIR/server.conf"; then
    echo "scramble xormask 9" >> "$CONFIG_DIR/server.conf"
fi

# Add XOR scramble directive to client template
if ! grep -q "scramble xormask" "$CONFIG_DIR/client-template.txt"; then
    echo "scramble xormask 9" >> "$CONFIG_DIR/client-template.txt"
fi

# Update any already-generated client configs
if [ -f /root/client.ovpn ]; then
    if ! grep -q "scramble xormask" /root/client.ovpn; then
        echo "scramble xormask 9" >> /root/client.ovpn
    fi
fi

# Also check /home/ubuntu for client configs
if [ -f /home/ubuntu/client.ovpn ]; then
    if ! grep -q "scramble xormask" /home/ubuntu/client.ovpn; then
        echo "scramble xormask 9" >> /home/ubuntu/client.ovpn
    fi
fi

# === STEP 3: Stop OpenVPN before replacing binary ===
echo "[*] Stopping OpenVPN service..."
systemctl stop openvpn-server@server || systemctl stop openvpn@server || true

# === STEP 4: Remove distro OpenVPN ===
echo "[*] Removing distro OpenVPN binary (keeping configs)..."
apt remove -y openvpn || true

# === STEP 5: Install build dependencies ===
echo "[*] Installing build dependencies..."
apt update && apt dist-upgrade -y
apt install -y build-essential libssl-dev iproute2 liblz4-dev liblzo2-dev \
               libpam0g-dev libpkcs11-helper1-dev libsystemd-dev resolvconf pkg-config \
               libnl-3-dev libnl-genl-3-dev libcap-ng-dev

# === STEP 6: Download and extract OpenVPN source ===
echo "[*] Downloading OpenVPN ${OPENVPN_VERSION}..."
cd /usr/local/src || mkdir -p /usr/local/src && cd /usr/local/src

# Clean up any previous build
rm -rf "openvpn-${OPENVPN_VERSION}" "openvpn-${OPENVPN_VERSION}.tar.gz"

wget "https://swupdate.openvpn.org/community/releases/openvpn-${OPENVPN_VERSION}.tar.gz"
tar xvf "openvpn-${OPENVPN_VERSION}.tar.gz"
cd "openvpn-${OPENVPN_VERSION}"

# === STEP 7: Download and apply XOR patches ===
echo "[*] Downloading and applying XOR patches..."
for patch in "${PATCHES[@]}"; do
    echo "    - ${patch}"
    wget "${TUNNELBLICK_BASE}/${patch}"
    patch -p1 < "${patch}"
done

# === STEP 8: Configure, build, and install ===
echo "[*] Configuring..."
./configure --enable-static=yes --enable-shared --disable-debug \
            --disable-plugin-auth-pam --disable-dependency-tracking
echo "[*] Building..."
make -j"$(nproc)"
echo "[*] Installing..."
make install

# === STEP 9: Create systemd service ===
echo "[*] Creating systemd service..."
cat << EOF > /etc/systemd/system/openvpn@server.service
[Unit]
Description=OpenVPN Robust And Highly Flexible Tunneling Application On %I
After=syslog.target network.target

[Service]
Type=forking
PrivateTmp=true
ExecStart=/usr/local/sbin/openvpn --daemon --cd $CONFIG_DIR/ --config $CONFIG_DIR/server.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# === STEP 10: Enable and start service ===
systemctl daemon-reload
systemctl -f enable openvpn@server
systemctl -f restart openvpn@server

# === STEP 11: Verify installation ===
echo
echo "[*] Verifying OpenVPN XOR installation..."
OVPN_VERSION=$(/usr/local/sbin/openvpn --version | head -1)
echo "    Installed: $OVPN_VERSION"

if systemctl is-active --quiet openvpn@server; then
    echo "[+] OpenVPN service is running!"
else
    echo "[!] Warning: OpenVPN service failed to start. Check logs with: journalctl -u openvpn@server"
fi

echo
echo "[+] OpenVPN ${OPENVPN_VERSION} with XOR patch installed successfully."
echo
echo "=== IMPORTANT FOR TURKMENISTAN ==="
echo "Your server is configured with:"
echo "  - Port: 443 (HTTPS port, harder to block)"
echo "  - XOR Scramble: Enabled (scramble xormask 9)"
echo
echo "Client configs are in: $CONFIG_DIR/client-template.txt"
echo "To add new clients, run: ./openvpn-install.sh client add <name>"
echo