#!/data/data/com.termux/files/usr/bin/bash
# Run inside Termux on the phone:  bash bootstrap.sh
set -eu

if [ ! -d /data/data/com.termux ]; then
  echo "This script must be run inside Termux." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
APT="apt-get -y -o Dpkg::Options::=--force-confnew"

echo "==> Updating package index"
$APT update

echo "==> Upgrading installed packages"
$APT upgrade

echo "==> Installing core packages"
$APT install openssh git curl nano

echo "==> Granting storage access (will prompt)"
termux-setup-storage || true

echo "==> Preparing ~/.ssh"
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

echo "==> Setting Termux login password (used for SSH password auth fallback)"
echo "    You'll be prompted twice; pick something memorable."
until passwd; do
  echo "Try again."
done

echo "==> Installing Termux:Boot autostart hook"
mkdir -p ~/.termux/boot
cp -f "$(dirname "$0")/start-services" ~/.termux/boot/start-services
chmod +x ~/.termux/boot/start-services

echo "==> Starting sshd now"
pkill sshd 2>/dev/null || true
sshd

cat <<EOF

================================================================
Setup complete.

  Username:     $(whoami)
  SSH port:     8022

Tailscale IP:   open the Tailscale app, sign in, then in Termux run
                'tailscale ip -4' (or check the app, "This device").

Add your laptop public key to:
  ~/.ssh/authorized_keys

Then from your laptop (over Tailscale):
  ssh -p 8022 $(whoami)@<phone-tailscale-name>

See README.md for ColorOS battery whitelist (still TODO).
================================================================
EOF
