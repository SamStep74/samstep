# openclaw smoke test

A dependency-light smoke test for an **openclaw agent** running under
[Termux](https://termux.dev/) on an Android device (e.g. an **Oppo** phone),
plus the systems it depends on. It checks each piece is alive and pushes a
pass/fail summary to **Telegram**.

## What it checks

| # | Section | What it verifies |
|---|---------|------------------|
| 1 | **Environment / device** | Running under Termux; device identity (Oppo & "other system" via `EXPECTED_DEVICES`); `curl` present |
| 2 | **openclaw agent** | Binary in PATH, prints a version, process is running, optional health URL returns 2xx |
| 3 | **AI model** | Model API reachable (`GET /models`) or responding to a 1-token chat ping |
| 4 | **Integration endpoints** | Each configured "other system" URL returns 2xx/3xx |
| 5 | **Telegram** | Bot token is valid (`getMe`) — and is also the channel the report is sent on |

Each check reports `PASS`, `FAIL`, `WARN`, or `SKIP`. Only `FAIL` makes the run
exit non-zero. Unconfigured checks `SKIP` rather than fail, so you can start with
a minimal config and add targets as you go.

## Requirements

Just `bash` and `curl`. In Termux:

```sh
pkg install bash curl
```

Android-only probes (`getprop` for device identity, `pgrep` for the process
check) are used when present and skipped otherwise, so the script also runs on a
plain Linux box or in CI.

## Usage

```sh
# 1. Configure (copy the example, then edit — config.env is gitignored)
cp config.example.env config.env
$EDITOR config.env

# 2. Run
./smoke-test.sh
```

You can also skip the file and pass everything as environment variables:

```sh
OPENCLAW_HEALTH_URL=http://127.0.0.1:8080/health \
MODEL_API_URL=https://api.openai.com/v1 MODEL_API_KEY=sk-... \
TELEGRAM_BOT_TOKEN=123:ABC TELEGRAM_CHAT_ID=42 TELEGRAM_NOTIFY=always \
./smoke-test.sh
```

Point at an alternate config file with `SMOKE_CONFIG=/path/to/file ./smoke-test.sh`.

## Configuration

See [`config.example.env`](config.example.env) for every option with comments.
Key ones:

- `EXPECTED_DEVICES` — comma-separated substrings expected in the device string
  (e.g. `oppo` or `oppo,pixel`); a miss is a `WARN`.
- `OPENCLAW_BIN` / `OPENCLAW_PROCESS_PATTERN` / `OPENCLAW_HEALTH_URL` — how to
  find and probe the agent.
- `MODEL_API_URL` / `MODEL_API_KEY` / `MODEL_NAME` / `MODEL_PING_MODE`
  (`models` or `chat`) — the AI model under test.
- `INTEGRATION_ENDPOINTS` — `NAME=URL` entries (comma- or newline-separated) for
  any other systems.
- `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` / `TELEGRAM_NOTIFY`
  (`auto` | `always` | `never`).

## Telegram report

On `auto` (default) a report is delivered only when a check fails, to keep the
chat quiet on healthy runs. Use `always` to get a message every run. The message
includes the overall result, host, pass/fail/warn/skip counts, and the detail of
any failures or warnings.

## Scheduling on the device

Run it on a timer with Termux's cron (`termux-job-scheduler`) or a simple loop:

```sh
while true; do ./smoke-test.sh; sleep 900; done
```

## Exit codes

- `0` — no checks failed (warnings/skips allowed)
- `1` — at least one check failed
