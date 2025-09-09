# reshrag's OpenVPN XOR Installer

An interactive OpenVPN server installer with XOR obfuscation support (v2.6.14),  
based on [angristan/openvpn-install](https://github.com/angristan/openvpn-install) and  
[Tunnelblick XOR patches](https://github.com/Tunnelblick/Tunnelblick).

## Features
- Step-by-step interactive setup (choose your own options)
- XOR obfuscation for bypassing DPI
- Updated to OpenVPN 2.6.14 with latest Tunnelblick patches
- Systemd service auto-setup
- Works on Debian/Ubuntu/CentOS

## Quick Install
```bash
curl -O https://raw.githubusercontent.com/reshgar/openvpn-2.6.14-install-xor/master/setup_openvpn_2.6.14_xor.sh
chmod +x setup_openvpn_2.6.14_xor.sh
./setup_openvpn_2.6.14_xor.sh
