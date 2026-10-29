# Reshrag's OpenVPN XOR Installer

An interactive OpenVPN server installer with XOR obfuscation, based on [angristan/openvpn-install](https://github.com/angristan/openvpn-install) and the [Tunnelblick XOR patches](https://github.com/Tunnelblick/Tunnelblick).

It runs angristan's interactive wizard (you choose port, protocol, cipher), then replaces the distro OpenVPN with a **source-built, XOR-patched OpenVPN 2.6.23**.

> The repo name still says 2.6.14 for link compatibility. The installer now builds **2.6.23** (latest 2.6.x) by default.

---

## 🚀 Fresh install

```bash
git clone https://github.com/reshgar/openvpn-2.6.14-install-xor.git
cd openvpn-2.6.14-install-xor
sudo ./setup_openvpn_xor.sh install
```

Optional: `sudo XOR_KEY=myKey ./setup_openvpn_xor.sh install` (default key is `9`).

## ⬆️ Upgrade an existing server (keeps keys, clients and .ovpn files)

```bash
cd openvpn-2.6.14-install-xor && git pull
sudo ./setup_openvpn_xor.sh upgrade
```

Builds the new binary first, then stops the service for a few seconds, swaps the binary and restarts. A backup goes to `/root/openvpn-backup-*.tar.gz` with a one-line rollback command printed at the end.

## 🩺 Diagnose

```bash
sudo ./diagnose.sh          # version, XOR, service, port, scramble, DCO, last log lines
sudo ./diagnose.sh watch    # tcpdump while a client connects: do packets reach the server?
```

---

## 📂 Repository structure

| Path | Purpose |
|---|---|
| `setup_openvpn_xor.sh` | Main installer / upgrader |
| `setup_openvpn_2.6.14_xor.sh` | Old name, now a wrapper → `setup_openvpn_xor.sh` |
| `openvpn-install.sh` | Pinned copy of angristan's installer (tested). `UPSTREAM=1` uses latest master instead |
| `patches/openvpn-<ver>/` | Vendored Tunnelblick XOR patches + `SHA256SUMS` |
| `diagnose.sh` | Health check / packet watcher |

## 🔧 How it works (short logic)

1. angristan's wizard creates PKI, `server.conf`, firewall rules, systemd unit (copied to `/etc/systemd/system`).
2. `scramble xormask <key>` is appended to `server.conf`, `client-template.txt` and existing `.ovpn` files.
3. OpenVPN source (checksum-verified) is patched with the 5 XOR patches and built with `--enable-systemd`.
4. Distro `openvpn` is removed and pinned (`/etc/apt/preferences.d/no-distro-openvpn`) so `apt upgrade` can never put an unpatched binary back; `/usr/sbin/openvpn` → `/usr/local/sbin/openvpn`.
5. `disable-dco` is added to `server.conf` and the service is restarted and verified.

## ⚠️ Known issues and their fixes

| Problem | Cause | Fix in this version |
|---|---|---|
| Install fails at "applying patches" | Tunnelblick deletes old version folders (e.g. `openvpn-2.6.14`) from master | Patches are vendored in `patches/` |
| Install breaks after upstream update | angristan master changed (CLI moved to `interactive` subcommand, etc.) | Pinned local copy is used by default |
| Service "activating" then killed after ~90 s | Unit is `Type=notify`, binary built without systemd support | `--enable-systemd` |
| Handshake OK, no traffic (new kernels) | DCO moves the data channel into the kernel, which does not XOR | `disable-dco` |
| `TLS handshake failed` after changes | Cipher or `scramble` key differs between server and client | Every client must have the same `scramble xormask` line |
| Works from one country, not another | Blocking on the client's ISP (IP or protocol fingerprint), not a server bug | Check with `diagnose.sh watch` |

---

## 📝 Credits

- Original installer — angristan/openvpn-install (MIT)
- XOR patches — Tunnelblick
- Modifications & updates — Reshrag

## 📜 License

MIT — see `LICENSE`.
