#!/bin/bash
# setup_openvpn_2.6.14_xor.sh
# Step-by-step: interactive angristan install first, then XOR-patched OpenVPN 2.6.14

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
./openvpn-install.sh

# === STEP 2: Modify configs after angristan install ===
echo "[*] Adjusting OpenVPN configs..."
sed -i "s/^port .*/port 443/" /etc/openvpn/server.conf
sed -i 's/1194/443/g' /etc/openvpn/client-template.txt
echo "scramble xormask 9" >> /etc/openvpn/server.conf
echo "scramble xormask 9" >> /etc/openvpn/client-template.txt
if [ -f /root/client.ovpn ]; then
    echo "scramble xormask 9" >> /root/client.ovpn
fi

# === STEP 3: Remove distro OpenVPN ===
echo "[*] Removing distro OpenVPN..."
apt remove -y openvpn || true

# === STEP 4: Install build dependencies ===
echo "[*] Installing build dependencies..."
apt update && apt dist-upgrade -y
apt install -y build-essential libssl-dev iproute2 liblz4-dev liblzo2-dev \
               libpam0g-dev libpkcs11-helper1-dev libsystemd-dev resolvconf pkg-config \
               libnl-3-dev libnl-genl-3-dev libcap-ng-dev

# === STEP 5: Download and extract OpenVPN source ===
echo "[*] Downloading OpenVPN ${OPENVPN_VERSION}..."
cd /usr/local/src || mkdir -p /usr/local/src && cd /usr/local/src
wget "https://swupdate.openvpn.org/community/releases/openvpn-${OPENVPN_VERSION}.tar.gz"
tar xvf "openvpn-${OPENVPN_VERSION}.tar.gz"
cd "openvpn-${OPENVPN_VERSION}"

# === STEP 6: Download and apply XOR patches ===
echo "[*] Downloading and applying XOR patches..."
for patch in "${PATCHES[@]}"; do
    echo "    - ${patch}"
    wget "${TUNNELBLICK_BASE}/${patch}"
    patch -p1 < "${patch}"
done

# === STEP 7: Configure, build, and install ===
echo "[*] Configuring..."
./configure --enable-static=yes --enable-shared --disable-debug \
            --disable-plugin-auth-pam --disable-dependency-tracking
echo "[*] Building..."
make -j"$(nproc)"
echo "[*] Installing..."
make install

# === STEP 8: Create systemd service ===
echo "[*] Creating systemd service..."
cat << EOF > /etc/systemd/system/openvpn@server.service
[Unit]
Description=OpenVPN Robust And Highly Flexible Tunneling Application On %I
After=syslog.target network.target

[Service]
Type=forking
PrivateTmp=true
ExecStart=/usr/local/sbin/openvpn --daemon --cd /etc/openvpn/ --config /etc/openvpn/server.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# === STEP 9: Enable and start service ===
systemctl daemon-reload
systemctl -f enable openvpn@server
systemctl -f restart openvpn@server

echo
echo "[+] OpenVPN ${OPENVPN_VERSION} with XOR patch installed successfully."

