#!/bin/bash
# ============================================================
#  reshrag's OpenVPN XOR Installer / Upgrader
#
#  Builds OpenVPN from source with the Tunnelblick XOR ("scramble")
#  patches and plugs it into angristan's openvpn-install setup.
#
#  Modes:
#    install  - fresh server: runs angristan's interactive wizard,
#               then swaps in the XOR-patched binary (default when
#               no server.conf exists)
#    upgrade  - existing server: rebuilds/replaces ONLY the binary.
#               Keys, clients, server.conf and .ovpn files are kept.
#               (default when /etc/openvpn/server/server.conf exists)
#
#  Usage:
#    sudo ./setup_openvpn_xor.sh            # auto-detect mode
#    sudo ./setup_openvpn_xor.sh install
#    sudo ./setup_openvpn_xor.sh upgrade
#
#  Environment overrides:
#    OPENVPN_VERSION=2.6.23   OpenVPN version to build
#    XOR_KEY=9                scramble xormask key (install mode only)
#    OVPN_DIR=/home/ubuntu    where client .ovpn files are copied
#    UPSTREAM=1               use latest angristan installer instead
#                             of the pinned copy from this repo
#
#  Credits: angristan/openvpn-install (MIT), Tunnelblick XOR patches.
#  License: MIT
# ============================================================

set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
step() { echo -e "${YELLOW}==> $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

OPENVPN_VERSION="${OPENVPN_VERSION:-2.6.23}"
XOR_KEY="${XOR_KEY:-9}"
OVPN_DIR="${OVPN_DIR:-/home/ubuntu}"
REPO_RAW="https://raw.githubusercontent.com/reshgar/openvpn-2.6.14-install-xor/master"
# Tunnelblick deletes old version folders from master, so this is only a fallback.
TUNNELBLICK_RAW="https://raw.githubusercontent.com/Tunnelblick/Tunnelblick/master/third_party/sources/openvpn/openvpn-${OPENVPN_VERSION}/patches"
PATCHES=(
	"02-tunnelblick-openvpn_xorpatch-a.diff"
	"03-tunnelblick-openvpn_xorpatch-b.diff"
	"04-tunnelblick-openvpn_xorpatch-c.diff"
	"05-tunnelblick-openvpn_xorpatch-d.diff"
	"06-tunnelblick-openvpn_xorpatch-e.diff"
)
# Known-good tarball checksums (verified from the official release)
declare -A TARBALL_SHA256=(
	["2.6.23"]="4041c709162bec1325abf5aa8cf27a255cc477c634b15ee310411c701fc40a96"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/openvpn/server"
SERVICE="openvpn-server@server"
BUILD_ROOT="/usr/local/src"
BUILD_LOG="/var/log/openvpn-xor-build.log"

trap 'die "Failed at line $LINENO. Build log (if any): $BUILD_LOG"' ERR

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."
command -v apt-get >/dev/null || die "Only Debian/Ubuntu are supported."

MODE="${1:-auto}"
if [[ $MODE == auto ]]; then
	if [[ -f $CONFIG_DIR/server.conf ]]; then MODE=upgrade; else MODE=install; fi
fi
[[ $MODE =~ ^(install|upgrade)$ ]] || die "Unknown mode '$MODE'. Use: install | upgrade"

echo -e "${GREEN}============================================================"
echo "  reshrag's OpenVPN XOR installer — mode: ${MODE}"
echo "  Target: OpenVPN ${OPENVPN_VERSION} + Tunnelblick XOR patches"
echo -e "============================================================${NC}"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
ovpn_ver() { # first line of "openvpn --version" without SIGPIPE issues
	local out
	out=$("$1" --version 2>/dev/null || true)
	out=${out%%$'\n'*}
	echo "${out:-none}" | cut -d' ' -f1,2
}

fetch() { # fetch <url> <dest>
	curl -fsSL --retry 3 -o "$2" "$1"
}

get_patch() { # copy vendored patch, else download from this repo, else Tunnelblick
	local name=$1 dest=$2
	local local_copy="$SCRIPT_DIR/patches/openvpn-${OPENVPN_VERSION}/$name"
	if [[ -f $local_copy ]]; then
		cp "$local_copy" "$dest"
	elif fetch "$REPO_RAW/patches/openvpn-${OPENVPN_VERSION}/$name" "$dest"; then
		:
	elif fetch "$TUNNELBLICK_RAW/$name" "$dest"; then
		warn "Using patch from Tunnelblick master (not vendored): $name"
	else
		die "Patch $name for OpenVPN ${OPENVPN_VERSION} not found. Vendor it into patches/openvpn-${OPENVPN_VERSION}/."
	fi
}

install_build_deps() {
	step "Installing build dependencies"
	apt-get update -qq
	DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential pkg-config \
		libssl-dev liblz4-dev liblzo2-dev libpam0g-dev libpkcs11-helper1-dev \
		libsystemd-dev libnl-3-dev libnl-genl-3-dev libcap-ng-dev \
		iproute2 curl patch ca-certificates >/dev/null
	ok "Dependencies installed"
}

build_openvpn() {
	step "Building OpenVPN ${OPENVPN_VERSION} with XOR patches (1-3 min)"
	: >"$BUILD_LOG"
	mkdir -p "$BUILD_ROOT"
	local src="$BUILD_ROOT/openvpn-${OPENVPN_VERSION}"
	local tgz="$BUILD_ROOT/openvpn-${OPENVPN_VERSION}.tar.gz"
	rm -rf "$src" "$tgz"

	fetch "https://github.com/OpenVPN/openvpn/releases/download/v${OPENVPN_VERSION}/openvpn-${OPENVPN_VERSION}.tar.gz" "$tgz" ||
		fetch "https://swupdate.openvpn.org/community/releases/openvpn-${OPENVPN_VERSION}.tar.gz" "$tgz" ||
		die "Could not download OpenVPN ${OPENVPN_VERSION} source."

	local expected="${TARBALL_SHA256[$OPENVPN_VERSION]:-}"
	if [[ -n $expected ]]; then
		echo "$expected  $tgz" | sha256sum -c --quiet - || die "Source tarball checksum mismatch!"
		ok "Source checksum verified"
	else
		warn "No pinned checksum for ${OPENVPN_VERSION}; skipping verification"
	fi

	tar xzf "$tgz" -C "$BUILD_ROOT"
	cd "$src"

	for p in "${PATCHES[@]}"; do
		get_patch "$p" "$src/$p"
		patch -p1 --forward <"$p" >>"$BUILD_LOG" 2>&1 || die "Patch $p failed to apply (see $BUILD_LOG)"
		echo "    applied $p"
	done
	grep -q 'xormask' src/openvpn/options.c || die "XOR patch not present in source"

	# --enable-systemd is REQUIRED: the service unit is Type=notify; without
	# sd_notify support systemd kills the daemon after the start timeout.
	./configure --enable-systemd --disable-debug --disable-plugin-auth-pam \
		--disable-dependency-tracking >>"$BUILD_LOG" 2>&1 ||
		{ tail -20 "$BUILD_LOG"; die "configure failed"; }
	make -j"$(nproc)" >>"$BUILD_LOG" 2>&1 || { tail -30 "$BUILD_LOG"; die "make failed"; }

	./src/openvpn/openvpn --version >/dev/null || die "Built binary does not run"
	grep -aq 'xormask' src/openvpn/openvpn || die "Built binary has no XOR support"
	ok "Build finished: $(ovpn_ver ./src/openvpn/openvpn)"
}

install_binary() {
	step "Installing binary"
	cd "$BUILD_ROOT/openvpn-${OPENVPN_VERSION}"
	make install >>"$BUILD_LOG" 2>&1 || { tail -20 "$BUILD_LOG"; die "make install failed"; }
	# Remove the distro package binary (configs in /etc are kept) and point
	# /usr/sbin/openvpn (used by the systemd unit) at our build.
	if dpkg -s openvpn >/dev/null 2>&1; then
		apt-get remove -y -qq openvpn >/dev/null || true
	fi
	ln -sf /usr/local/sbin/openvpn /usr/sbin/openvpn
	# Stop apt from ever reinstalling the unpatched distro openvpn over our build
	cat >/etc/apt/preferences.d/no-distro-openvpn <<-'EOF'
		# Managed by setup_openvpn_xor.sh — XOR-patched OpenVPN lives in /usr/local
		Package: openvpn
		Pin: release *
		Pin-Priority: -1
	EOF
	mkdir -p /run/openvpn-server /run/openvpn
	ok "Installed: $(ovpn_ver /usr/sbin/openvpn)"
}

ensure_server_conf() {
	local conf="$CONFIG_DIR/server.conf"
	# XOR only happens in userspace. Data Channel Offload (kernel 6.16+ or
	# ovpn-dco module) would send data packets UNscrambled -> clients break.
	if ! grep -q '^disable-dco' "$conf"; then
		echo "disable-dco" >>"$conf"
		ok "Added 'disable-dco' to server.conf"
	fi
}

restart_and_check() {
	step "Restarting $SERVICE"
	systemctl daemon-reload
	systemctl enable "$SERVICE" >/dev/null 2>&1 || true
	systemctl restart "$SERVICE"
	sleep 3
	if systemctl is-active --quiet "$SERVICE"; then
		ok "Service is running"
	else
		journalctl -u "$SERVICE" -n 25 --no-pager || true
		die "Service failed to start (log above)."
	fi
	local listen
	listen=$(ss -tulnp 2>/dev/null | grep openvpn | awk '{print $1, $5}' | head -1 || true)
	[[ -n $listen ]] && ok "Listening: $listen"
	grep -E '^(port|proto|scramble|cipher|data-ciphers|disable-dco)' "$CONFIG_DIR/server.conf" | sed 's/^/    /' || true
}

copy_ovpn_files() {
	[[ -d $OVPN_DIR ]] || return 0
	local owner f
	owner=$(stat -c '%U:%G' "$OVPN_DIR")
	for f in /root/*.ovpn; do
		[[ -f $f ]] || continue
		cp -f "$f" "$OVPN_DIR/" && chown "$owner" "$OVPN_DIR/$(basename "$f")" && chmod 600 "$OVPN_DIR/$(basename "$f")"
		ok "Client config copied to $OVPN_DIR/$(basename "$f")"
	done
}

# ------------------------------------------------------------
# UPGRADE mode: binary only, configs untouched
# ------------------------------------------------------------
if [[ $MODE == upgrade ]]; then
	[[ -f $CONFIG_DIR/server.conf ]] || die "No $CONFIG_DIR/server.conf — use 'install' mode."
	echo "    Current binary: $(ovpn_ver openvpn)"
	echo "    Server scramble: $(grep '^scramble' "$CONFIG_DIR/server.conf" || echo 'NOT SET')"

	BACKUP="/root/openvpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
	BACKUP_PATHS=(/etc/openvpn /etc/systemd/system/openvpn-server@.service)
	OLD_BIN=$(readlink -f /usr/sbin/openvpn 2>/dev/null || true)
	[[ -n $OLD_BIN && -f $OLD_BIN ]] && BACKUP_PATHS+=("$OLD_BIN")
	tar czf "$BACKUP" "${BACKUP_PATHS[@]}" 2>/dev/null || true
	ok "Backup saved: $BACKUP"

	install_build_deps
	build_openvpn # build first, so downtime is only the restart
	systemctl stop "$SERVICE" || true
	install_binary
	ensure_server_conf
	restart_and_check
	echo
	ok "Upgrade complete. Existing .ovpn client files keep working (same keys, same scramble key)."
	echo "    Rollback: systemctl stop $SERVICE; tar xzf $BACKUP -C /; systemctl start $SERVICE"
	exit 0
fi

# ------------------------------------------------------------
# INSTALL mode
# ------------------------------------------------------------
step "Getting angristan's installer"
cd "$SCRIPT_DIR"
if [[ ${UPSTREAM:-0} == 1 ]]; then
	fetch https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh openvpn-install.sh
	warn "Using UNPINNED upstream installer (UPSTREAM=1)"
elif [[ ! -f openvpn-install.sh ]]; then
	fetch "$REPO_RAW/openvpn-install.sh" openvpn-install.sh
fi
chmod +x openvpn-install.sh
ok "Installer ready ($(grep -m1 'EASYRSA_VERSION=' openvpn-install.sh | tr -d ' '))"

echo
echo -e "${GREEN}>>> angristan's wizard starts now. Pick port/protocol/cipher as you like.${NC}"
echo -e "${YELLOW}>>> Tips for censored networks: UDP, a common port (443/53/123), CHACHA20-POLY1305 or AES-GCM.${NC}"
echo
sleep 2
./openvpn-install.sh interactive

[[ -f $CONFIG_DIR/server.conf ]] || die "server.conf not found — angristan's install did not finish."

step "Adding XOR obfuscation (scramble xormask ${XOR_KEY})"
for f in "$CONFIG_DIR/server.conf" "$CONFIG_DIR/client-template.txt" /root/*.ovpn /home/*/*.ovpn; do
	[[ -f $f ]] || continue
	if ! grep -q '^scramble' "$f"; then
		echo "scramble xormask ${XOR_KEY}" >>"$f"
		ok "scramble added: $f"
	fi
done

install_build_deps
build_openvpn
systemctl stop "$SERVICE" 2>/dev/null || true
install_binary
ensure_server_conf
restart_and_check
copy_ovpn_files

echo
echo -e "${GREEN}============================================================"
echo "  INSTALLATION COMPLETE"
echo -e "============================================================${NC}"
echo "  Binary:       /usr/local/sbin/openvpn (symlink /usr/sbin/openvpn)"
echo "  XOR:          scramble xormask ${XOR_KEY}  (server AND every client must match)"
echo "  Add client:   cd $SCRIPT_DIR && ./openvpn-install.sh client add <name>"
echo "                (template already contains the scramble line)"
echo "  Upgrade later: sudo ./setup_openvpn_xor.sh upgrade"
