# Remote access to OpenClaw on the Oppo (Termux)

Goal: make the Oppo's Termux reachable over a private Tailscale network so a
future session (or you, from anywhere) can SSH in and check/control OpenClaw.

> Oppo's ColorOS aggressively kills background apps, so the persistence steps
> (battery + boot) matter as much as the networking.

## 1. Install the right Termux

Uninstall any Play Store Termux (abandoned and broken). Install from
**F-Droid** or **GitHub releases**:

- Termux
- **Termux:Boot** (auto-start on reboot)
- **Termux:API** (optional: wakelock/notifications)

## 2. Base packages

```sh
pkg update && pkg upgrade -y
pkg install -y openssh termux-services tailscale
```

## 3. SSH server

Set a password:

```sh
passwd
```

Key-based auth (recommended) — on the phone:

```sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys   # paste your pubkey, save
chmod 600 ~/.ssh/authorized_keys
```

Termux sshd listens on **port 8022** (not 22). Enable as a managed service:

```sh
sv-enable sshd
sv up sshd
```

## 4. Tailscale (private network, no port forwarding)

Easiest path on Android: install the **Tailscale app from Play Store** and
sign in. It gives the whole device a stable `100.x.y.z` IP and handles
NAT/keepalive far better than the Termux daemon under ColorOS.

From any device on your tailnet:

```sh
ssh -p 8022 <termux-user>@<oppo-tailscale-ip>
```

Find the username with `whoami`; find the IP in the Tailscale app or
`tailscale ip -4`.

> Running `tailscaled` inside Termux instead of the app requires userspace
> networking (`tailscaled --tun=userspace-networking`) and is flakier under
> ColorOS. Only use this route if the app is not an option.

## 5. Survive ColorOS killing it

Most-missed part on Oppo:

- **Settings → Battery →** Termux (and Tailscale) → **"Don't optimize" /
  "Allow background activity" / "Allow auto-launch"**.
- **Recent apps screen:** swipe down on the Termux card → **lock it**
  (padlock) so it is not cleared.
- Keep Termux awake while idle: `termux-wake-lock`
- Make boot + services automatic:

  ```sh
  mkdir -p ~/.termux/boot
  nano ~/.termux/boot/start.sh
  ```

  Contents:

  ```sh
  #!/data/data/com.termux/files/usr/bin/sh
  termux-wake-lock
  sv up sshd
  # start OpenClaw too — adjust to how you run it:
  # sv up openclaw
  # or: nohup <openclaw-launch-cmd> >> ~/.openclaw/boot.log 2>&1 &
  ```

  ```sh
  chmod +x ~/.termux/boot/start.sh
  ```

  Open the **Termux:Boot** app once so Android grants autostart.

## 6. Auto-start OpenClaw as a service (optional, cleaner)

Makes `sv status openclaw` work and restarts it on crash:

```sh
mkdir -p ~/.config/sv/openclaw
nano ~/.config/sv/openclaw/run
```

```sh
#!/data/data/com.termux/files/usr/bin/sh
exec 2>&1
exec <openclaw-launch-command>
```

```sh
chmod +x ~/.config/sv/openclaw/run
sv-enable openclaw
```

## 7. Verify

Reboot the phone. Do **not** open Termux. From another machine on the tailnet:

```sh
ssh -p 8022 <user>@<oppo-tailscale-ip> 'pgrep -fa -i openclaw; sv status sshd openclaw'
```

If that returns cleanly, a future remote session can run the same check.

## Quick status check (once set up)

```sh
pgrep -fa -i openclaw; echo "---"; tail -n 40 ~/.openclaw/logs/*.log 2>/dev/null
```
