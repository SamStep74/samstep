# Termux remote access on Oppo (ColorOS)

End goal: SSH into your Oppo phone from anywhere via Tailscale.

The pieces:
- **Termux** runs sshd on port 8022.
- **Tailscale (Android app)** puts the phone on your tailnet.
- **Termux:Boot** restarts sshd after reboot.
- **ColorOS battery whitelist** keeps Termux from being killed.

## 1. Install apps (manual, on the phone)

Install **from F-Droid, not the Play Store** — the Play Store builds of Termux are unmaintained and will break things.

1. F-Droid: https://f-droid.org/F-Droid.apk
2. From F-Droid, install:
   - `Termux`
   - `Termux:Boot`
   - `Termux:API` (optional, lets you script phone features)
3. Open each app once after install so Android registers them.
4. Tailscale (Play Store or F-Droid is fine): install, sign in to your tailnet, toggle the VPN on. Note the device name it picks.

## 2. ColorOS battery whitelist (critical)

ColorOS will kill Termux in the background unless you exempt it. Without these settings sshd dies whenever the screen locks.

- Settings → Battery → **App battery management** → Termux → **Allow background activity** + **Don't optimize**
- Settings → Apps → Termux → Battery usage → **Allow foreground / background**
- Recent apps view → swipe down on the Termux card → tap the **padlock** icon to lock it
- Repeat all three for **Termux:Boot** and **Tailscale**.
- Settings → Additional settings → Developer options → **Don't keep activities** → **off**.

## 3. Run the bootstrap script

In Termux on the phone:

```sh
pkg install -y git
git clone https://github.com/samstep74/samstep.git
cd samstep
git checkout claude/setup-termux-oppo-xR5I2
bash bootstrap.sh
```

The script will:
- Install `openssh`, `termux-api`, `termux-services`, etc.
- Prompt you to set a Termux password (used as SSH fallback).
- Install `start-services` into `~/.termux/boot/` so sshd restarts after reboot.
- Start sshd immediately on port 8022.

## 4. Add your laptop's public key

On your laptop:

```sh
cat ~/.ssh/id_ed25519.pub   # or id_rsa.pub
```

Paste that line into the phone's `~/.ssh/authorized_keys` (one key per line). Easiest path: open Termux on the phone and run `nano ~/.ssh/authorized_keys`.

## 5. Connect

From any device on your tailnet:

```sh
tailscale status                              # find the phone's name/IP
ssh -p 8022 <termux-username>@<phone-tailscale-name>
```

Username is whatever `whoami` printed at the end of bootstrap (e.g. `u0_a234`).

## 6. Verify reboot survival

Reboot the phone. Wait ~30s. From your laptop:

```sh
ssh -p 8022 <user>@<phone-tailscale-name>
```

If it fails:
- Open Termux on the phone — Termux:Boot only fires if Termux is allowed to autostart. Re-check the battery whitelist.
- Check sshd is up: in Termux, `pgrep -a sshd`.
- Re-run `~/.termux/boot/start-services` manually to confirm the script works.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Connection refused` | sshd not running. Open Termux, run `sshd`. |
| Works on Wi-Fi, not on cellular | Tailscale VPN toggle is off, or Tailscale app got killed — re-whitelist battery. |
| Dies after screen lock | `termux-wake-lock` not held. Make sure `start-services` ran; rerun manually. |
| Disconnects every few minutes | ColorOS background restriction. Lock Termux in recents (padlock icon). |
| `Permission denied (publickey)` | Public key not in `~/.ssh/authorized_keys`, or file perms wrong (`chmod 600`). |

## Karpathy Eval

This repo includes a static product contract for the Termux bootstrap flow:

```sh
node scripts/karpathy-eval.mjs --list
node scripts/karpathy-eval.mjs --program termux-bootstrap-contract
node scripts/karpathy-eval.mjs --run termux-bootstrap-contract
```

Use `--allow-harness-dirty` only while bootstrapping reviewed local harness
files before committing them.
