#!/data/data/com.termux/files/usr/bin/bash
# Run inside Termux on the phone:  bash bootstrap.sh
set -euo pipefail

if [ ! -d /data/data/com.termux ]; then
  echo "This script must be run inside Termux." >&2
  exit 1
fi

echo "==> Updating packages"
yes | pkg update
yes | pkg upgrade

echo "==> Installing core packages"
pkg install -y openssh termux-api termux-services git curl nano iproute2 termux-auth

echo "==> Granting storage access (will prompt)"
termux-setup-storage || true

echo "==> Preparing ~/.ssh"
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

echo "==> Setting Termux login password (used for SSH password auth fallback)"
passwd

echo "==> Installing Termux:Boot autostart hook"
mkdir -p ~/.termux/boot
cp -f "$(dirname "$0")/start-services" ~/.termux/boot/start-services
chmod +x ~/.termux/boot/start-services

echo "==> Starting sshd now"
pkill sshd || true
sshd

cat <<EOF

================================================================
Setup complete.

  Username:        $(whoami)
  SSH port:        8022
  LAN IP:          $(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
  Tailscale IP:    (run 'tailscale ip -4' once the Tailscale app is signed in)

Add your laptop public key to:
  ~/.ssh/authorized_keys

Then from your laptop (over Tailscale):
  ssh -p 8022 $(whoami)@<phone-tailscale-name>

See README.md for the manual steps (Tailscale app, ColorOS battery
whitelist, Termux:Boot install).
================================================================
EOF
