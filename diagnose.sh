#!/bin/bash
# Quick health check for an XOR OpenVPN server.
# Usage: sudo ./diagnose.sh            # status report
#        sudo ./diagnose.sh watch      # live: show packets while a client tries to connect
CONF=/etc/openvpn/server/server.conf
SERVICE=openvpn-server@server

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }
PORT=$(awk '/^port /{print $2}' "$CONF" 2>/dev/null)
PROTO=$(awk '/^proto /{print $2}' "$CONF" 2>/dev/null)
PROTO=${PROTO%6}; PROTO=${PROTO%-server}

if [[ ${1:-} == watch ]]; then
	command -v tcpdump >/dev/null || apt-get install -y -qq tcpdump >/dev/null
	echo "Watching ${PROTO} port ${PORT}. Ask the client to connect now. Ctrl+C to stop."
	echo "  - NOTHING appears      -> traffic is blocked before reaching the server (ISP/DPI/IP block)"
	echo "  - packets IN, no OUT   -> server rejects them (scramble key/tls key mismatch, see journal)"
	echo "  - IN and OUT, no VPN   -> handshake/route issue on client side"
	tcpdump -ni any "${PROTO} port ${PORT}" -c 200
	exit 0
fi

line() { printf '%-22s %s\n' "$1" "$2"; }
echo "=== OpenVPN XOR server check ==="
line "Binary:" "$(readlink -f /usr/sbin/openvpn 2>/dev/null) — $( (openvpn --version 2>/dev/null || true) | sed -n 1p | cut -d' ' -f1,2)"
line "XOR in binary:" "$(grep -aq xormask "$(readlink -f /usr/sbin/openvpn)" 2>/dev/null && echo yes || echo 'NO (unpatched!)')"
line "Service:" "$(systemctl is-active $SERVICE)"
line "Port/proto:" "${PORT:-?}/${PROTO:-?}"
line "Server scramble:" "$(grep '^scramble' "$CONF" || echo 'NOT SET')"
line "Template scramble:" "$(grep '^scramble' /etc/openvpn/server/client-template.txt 2>/dev/null || echo 'NOT SET')"
line "disable-dco:" "$(grep -q '^disable-dco' "$CONF" && echo yes || echo 'no (XOR may break on new kernels)')"
line "Listening:" "$(ss -tulnp | grep openvpn | awk '{print $1, $5}' | head -1)"
line "IP forwarding:" "$(sysctl -n net.ipv4.ip_forward)"
line "Connected clients:" "$(awk '/^Common Name/{f=1;next} /^ROUTING TABLE/{f=0} f{n++} END{print n+0}' /var/log/openvpn/status.log 2>/dev/null || echo '?')"
command -v ufw >/dev/null && line "UFW:" "$(ufw status | head -1)"
command -v fail2ban-client >/dev/null && line "fail2ban:" "$(fail2ban-client status 2>/dev/null | grep 'Jail list' | cut -f2-)"
echo
echo "--- Last 15 log lines ---"
journalctl -u $SERVICE -n 15 --no-pager -o cat
echo
echo "Tip: run 'sudo ./diagnose.sh watch' while the client connects."
