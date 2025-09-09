# Reshrag's OpenVPN 2.6.14 XOR Installer

An interactive OpenVPN server installer with XOR obfuscation support, based on [angristan/openvpn-install](https://github.com/angristan/openvpn-install) and [Tunnelblick XOR patches](https://github.com/Tunnelblick/Tunnelblick).

This project lets you set up a secure, obfuscated OpenVPN server in minutes.  
It runs angristan’s interactive installer first (so you can choose your own options), then replaces the stock OpenVPN binary with a **custom‑built, XOR‑patched OpenVPN 2.6.14**.

---

## ✨ Features

- **Interactive setup** — choose your own ports, protocols, and options
- **XOR obfuscation** — bypass basic DPI and VPN blocking
- **Latest OpenVPN 2.6.14** — built from source with Tunnelblick patches
- **Systemd service auto‑setup** — starts on boot, restarts on failure
- Works on **Debian**, **Ubuntu**, and compatible systems

---

## 🚀 Quick Install

Run this on a fresh server (Debian/Ubuntu recommended):

```bash
curl -O https://raw.githubusercontent.com/reshgar/openvpn-2.6.14-install-xor/master/setup_openvpn_2.6.14_xor.sh
chmod +x setup_openvpn_2.6.14_xor.sh
./setup_openvpn_2.6.14_xor.sh
```
---

## 📂 Repository Structure

- **setup_openvpn_2.6.14_xor.sh** # Main installer script
- **openvpn-install.sh**            # angristan's interactive installer (downloaded at runtime)
- **LICENSE**                        # MIT License
- **README.md**                      # This file

---

## 📝 Credits

- Original installer — angristan/openvpn-install (MIT License)
- XOR patches — Tunnelblick
- Modifications & updates — Reshrag

---

## 📜 License

This project is licensed under the MIT License. See the LICENSE file for details.

---
