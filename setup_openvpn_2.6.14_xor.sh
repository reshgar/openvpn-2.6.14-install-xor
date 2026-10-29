#!/bin/bash
# Deprecated name kept so old links keep working.
# The real installer is setup_openvpn_xor.sh (now builds OpenVPN 2.6.23 by default).
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$DIR/setup_openvpn_xor.sh" ]]; then
	curl -fsSL -o "$DIR/setup_openvpn_xor.sh" \
		https://raw.githubusercontent.com/reshgar/openvpn-2.6.14-install-xor/master/setup_openvpn_xor.sh
	chmod +x "$DIR/setup_openvpn_xor.sh"
fi
exec "$DIR/setup_openvpn_xor.sh" "$@"
