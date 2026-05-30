#!/usr/bin/env bash
#
# openclaw smoke test
# -------------------
# Runs a set of lightweight liveness checks for an openclaw agent running under
# Termux on an Android device (e.g. an Oppo phone), plus the systems it depends
# on, and pushes a pass/fail summary to Telegram.
#
# Sections checked:
#   1. Environment / device   (Termux + device identity, e.g. Oppo & others)
#   2. openclaw agent         (binary present, version, process, health URL)
#   3. AI model               (model API reachable & responding)
#   4. Integration endpoints  ("other system" HTTP endpoints)
#   5. Telegram               (bot token valid; also the report channel)
#
# It is dependency-light: it only needs `bash` and `curl`. Android-only tools
# (`getprop`, `termux-info`) are used when available and skipped otherwise, so
# the script also runs cleanly on a plain Linux box or in CI.
#
# Configuration is read from environment variables. You can also drop the
# settings into a config file and point SMOKE_CONFIG at it (defaults to
# ./config.env next to this script). See config.example.env for all options.
#
# Exit code: 0 if no checks FAILED, 1 otherwise. WARN/SKIP do not fail the run.

set -u
set -o pipefail

# ---------------------------------------------------------------------------
# Locate and load config
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMOKE_CONFIG="${SMOKE_CONFIG:-$SCRIPT_DIR/config.env}"
if [ -f "$SMOKE_CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$SMOKE_CONFIG"
fi

# ---------------------------------------------------------------------------
# Settings (env overridable)
# ---------------------------------------------------------------------------
HTTP_TIMEOUT="${HTTP_TIMEOUT:-10}"

# openclaw agent
OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
OPENCLAW_VERSION_ARGS="${OPENCLAW_VERSION_ARGS:---version}"
OPENCLAW_PROCESS_PATTERN="${OPENCLAW_PROCESS_PATTERN:-openclaw}"
# 0 = match process name only (precise; default). 1 = match full command line
# (use when the agent runs as e.g. `python openclaw_agent.py`).
OPENCLAW_PROCESS_MATCH_FULL="${OPENCLAW_PROCESS_MATCH_FULL:-0}"
OPENCLAW_HEALTH_URL="${OPENCLAW_HEALTH_URL:-}"

# Device(s): comma-separated substrings expected in the device identity string,
# e.g. "oppo" or "oppo,pixel". Match is case-insensitive. Empty = informational.
EXPECTED_DEVICES="${EXPECTED_DEVICES:-}"

# AI model (OpenAI-compatible by default)
MODEL_API_URL="${MODEL_API_URL:-}"        # e.g. https://api.openai.com/v1
MODEL_API_KEY="${MODEL_API_KEY:-}"
MODEL_NAME="${MODEL_NAME:-}"              # optional, used in the chat ping
MODEL_PING_MODE="${MODEL_PING_MODE:-models}"   # "models" | "chat"

# Other systems: integration endpoints to probe. Newline- or comma-separated.
# Each entry is "NAME=URL" or just "URL".
INTEGRATION_ENDPOINTS="${INTEGRATION_ENDPOINTS:-}"

# Telegram (report channel + checked itself)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
TELEGRAM_NOTIFY="${TELEGRAM_NOTIFY:-auto}"     # auto | always | never

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  C_RESET="\033[0m"; C_GREEN="\033[32m"; C_RED="\033[31m"
  C_YELLOW="\033[33m"; C_BLUE="\033[34m"; C_DIM="\033[2m"; C_BOLD="\033[1m"
else
  C_RESET=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_BLUE=""; C_DIM=""; C_BOLD=""
fi

PASS_COUNT=0; FAIL_COUNT=0; WARN_COUNT=0; SKIP_COUNT=0
RESULTS=()   # "STATUS|NAME|DETAIL"

# record STATUS NAME DETAIL
record() {
  local status="$1" name="$2" detail="${3:-}"
  RESULTS+=("$status|$name|$detail")
  case "$status" in
    PASS) PASS_COUNT=$((PASS_COUNT+1)); printf "  ${C_GREEN}✔ PASS${C_RESET}  %-26s ${C_DIM}%s${C_RESET}\n" "$name" "$detail" ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT+1)); printf "  ${C_RED}✘ FAIL${C_RESET}  %-26s ${C_DIM}%s${C_RESET}\n" "$name" "$detail" ;;
    WARN) WARN_COUNT=$((WARN_COUNT+1)); printf "  ${C_YELLOW}⚠ WARN${C_RESET}  %-26s ${C_DIM}%s${C_RESET}\n" "$name" "$detail" ;;
    SKIP) SKIP_COUNT=$((SKIP_COUNT+1)); printf "  ${C_DIM}– SKIP  %-26s %s${C_RESET}\n" "$name" "$detail" ;;
  esac
}

section() { printf "\n${C_BOLD}${C_BLUE}== %s ==${C_RESET}\n" "$1"; }

have() { command -v "$1" >/dev/null 2>&1; }

# http_status URL [extra curl args...]  -> echoes HTTP code, returns curl rc
http_status() {
  local url="$1"; shift
  curl -sS -o /dev/null -m "$HTTP_TIMEOUT" -w '%{http_code}' "$@" "$url" 2>/dev/null
}

# ---------------------------------------------------------------------------
# 1. Environment / device
# ---------------------------------------------------------------------------
check_environment() {
  section "1. Environment / device"

  # Termux detection
  if [ -n "${TERMUX_VERSION:-}" ] || printf '%s' "${PREFIX:-}" | grep -q 'com.termux' || have termux-info; then
    record PASS "termux" "Termux detected (${TERMUX_VERSION:-unknown version})"
  else
    record WARN "termux" "not running under Termux ($(uname -s)/$(uname -m))"
  fi

  # Device identity
  local device_id=""
  if have getprop; then
    local manuf model andver
    manuf="$(getprop ro.product.manufacturer 2>/dev/null)"
    model="$(getprop ro.product.model 2>/dev/null)"
    andver="$(getprop ro.build.version.release 2>/dev/null)"
    device_id="$manuf $model (Android $andver)"
    record PASS "device" "$device_id"
  else
    device_id="$(uname -n) ($(uname -s) $(uname -m))"
    record SKIP "device" "getprop unavailable; host: $device_id"
  fi

  # Expected device match (e.g. oppo, other system)
  if [ -n "$EXPECTED_DEVICES" ]; then
    local lc_id; lc_id="$(printf '%s' "$device_id" | tr '[:upper:]' '[:lower:]')"
    local IFS=','
    for want in $EXPECTED_DEVICES; do
      want="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]' | xargs)"
      [ -z "$want" ] && continue
      if printf '%s' "$lc_id" | grep -q "$want"; then
        record PASS "device:$want" "matched"
      else
        record WARN "device:$want" "expected device substring not found"
      fi
    done
  fi

  # curl is the one hard dependency
  if have curl; then
    record PASS "curl" "$(curl --version 2>/dev/null | head -1 | cut -d' ' -f1-2)"
  else
    record FAIL "curl" "curl not installed (pkg install curl)"
  fi
}

# ---------------------------------------------------------------------------
# 2. openclaw agent
# ---------------------------------------------------------------------------
check_openclaw() {
  section "2. openclaw agent"

  if have "$OPENCLAW_BIN"; then
    record PASS "agent:binary" "$(command -v "$OPENCLAW_BIN")"
    local ver
    if ver="$("$OPENCLAW_BIN" $OPENCLAW_VERSION_ARGS 2>&1 | head -1)"; then
      record PASS "agent:version" "$ver"
    else
      record WARN "agent:version" "could not read version"
    fi
  else
    record FAIL "agent:binary" "'$OPENCLAW_BIN' not found in PATH"
  fi

  # Process running? Match the process name by default (precise); opt into
  # full-command-line matching with OPENCLAW_PROCESS_MATCH_FULL=1. Either way,
  # exclude this script's own process tree so the test never matches itself.
  if have pgrep; then
    local pids
    if [ "$OPENCLAW_PROCESS_MATCH_FULL" = "1" ]; then
      pids="$(pgrep -f "$OPENCLAW_PROCESS_PATTERN" 2>/dev/null)"
    else
      pids="$(pgrep "$OPENCLAW_PROCESS_PATTERN" 2>/dev/null)"
    fi
    local found="" p
    for p in $pids; do
      [ "$p" = "$$" ] && continue
      [ "$p" = "${PPID:-0}" ] && continue
      found="$p"; break
    done
    if [ -n "$found" ]; then
      record PASS "agent:process" "running (pid $found, pattern: $OPENCLAW_PROCESS_PATTERN)"
    else
      record WARN "agent:process" "no process matching '$OPENCLAW_PROCESS_PATTERN'"
    fi
  else
    record SKIP "agent:process" "pgrep unavailable"
  fi

  # Health endpoint
  if [ -n "$OPENCLAW_HEALTH_URL" ]; then
    local code; code="$(http_status "$OPENCLAW_HEALTH_URL")"
    if printf '%s' "$code" | grep -qE '^2[0-9][0-9]$'; then
      record PASS "agent:health" "HTTP $code $OPENCLAW_HEALTH_URL"
    else
      record FAIL "agent:health" "HTTP ${code:-no-response} $OPENCLAW_HEALTH_URL"
    fi
  else
    record SKIP "agent:health" "OPENCLAW_HEALTH_URL not set"
  fi
}

# ---------------------------------------------------------------------------
# 3. AI model
# ---------------------------------------------------------------------------
check_model() {
  section "3. AI model"

  if [ -z "$MODEL_API_URL" ]; then
    record SKIP "model" "MODEL_API_URL not set"
    return
  fi

  local auth=()
  [ -n "$MODEL_API_KEY" ] && auth=(-H "Authorization: Bearer $MODEL_API_KEY")

  if [ "$MODEL_PING_MODE" = "chat" ]; then
    local body
    body="$(printf '{"model":"%s","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}' "${MODEL_NAME:-gpt-4o-mini}")"
    local code
    code="$(http_status "${MODEL_API_URL%/}/chat/completions" -X POST \
            -H 'Content-Type: application/json' "${auth[@]}" --data "$body")"
    if printf '%s' "$code" | grep -qE '^2[0-9][0-9]$'; then
      record PASS "model:chat" "HTTP $code (${MODEL_NAME:-default model})"
    else
      record FAIL "model:chat" "HTTP ${code:-no-response} ${MODEL_API_URL%/}/chat/completions"
    fi
  else
    local code
    code="$(http_status "${MODEL_API_URL%/}/models" "${auth[@]}")"
    if printf '%s' "$code" | grep -qE '^2[0-9][0-9]$'; then
      record PASS "model:models" "HTTP $code ${MODEL_API_URL%/}/models"
    else
      record FAIL "model:models" "HTTP ${code:-no-response} ${MODEL_API_URL%/}/models"
    fi
  fi
}

# ---------------------------------------------------------------------------
# 4. Integration endpoints ("other system")
# ---------------------------------------------------------------------------
check_integrations() {
  section "4. Integration endpoints"

  if [ -z "$INTEGRATION_ENDPOINTS" ]; then
    record SKIP "integrations" "INTEGRATION_ENDPOINTS not set"
    return
  fi

  # Allow comma- or newline-separated entries.
  local normalized; normalized="$(printf '%s' "$INTEGRATION_ENDPOINTS" | tr ',' '\n')"
  while IFS= read -r entry; do
    entry="$(printf '%s' "$entry" | xargs)"
    [ -z "$entry" ] && continue
    local name url
    if printf '%s' "$entry" | grep -q '='; then
      name="${entry%%=*}"; url="${entry#*=}"
    else
      name="$entry"; url="$entry"
    fi
    local code; code="$(http_status "$url")"
    if printf '%s' "$code" | grep -qE '^[23][0-9][0-9]$'; then
      record PASS "int:$name" "HTTP $code"
    else
      record FAIL "int:$name" "HTTP ${code:-no-response} $url"
    fi
  done <<< "$normalized"
}

# ---------------------------------------------------------------------------
# 5. Telegram (validate bot token)
# ---------------------------------------------------------------------------
check_telegram() {
  section "5. Telegram"

  if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    record SKIP "telegram:token" "TELEGRAM_BOT_TOKEN not set"
    return
  fi

  local resp
  resp="$(curl -sS -m "$HTTP_TIMEOUT" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" 2>/dev/null)"
  if printf '%s' "$resp" | grep -q '"ok":true'; then
    local uname; uname="$(printf '%s' "$resp" | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4)"
    record PASS "telegram:token" "bot @${uname:-unknown}"
  else
    record FAIL "telegram:token" "getMe failed (token invalid or network down)"
  fi

  if [ -z "$TELEGRAM_CHAT_ID" ]; then
    record WARN "telegram:chat" "TELEGRAM_CHAT_ID not set (report won't be delivered)"
  fi
}

# ---------------------------------------------------------------------------
# Telegram report delivery
# ---------------------------------------------------------------------------
send_telegram_report() {
  local overall="$1" text="$2"
  [ "$TELEGRAM_NOTIFY" = "never" ] && return 0
  if [ "$TELEGRAM_NOTIFY" = "auto" ] && [ "$overall" = "PASS" ]; then
    # auto: only ping on failure to avoid noise. Use TELEGRAM_NOTIFY=always to send every run.
    printf "\n${C_DIM}Telegram: auto mode and run passed — report suppressed.${C_RESET}\n"
    return 0
  fi
  if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    return 0
  fi

  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' -m "$HTTP_TIMEOUT" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" \
    --data "parse_mode=HTML" \
    --data "disable_web_page_preview=true" 2>/dev/null)"
  if printf '%s' "$code" | grep -qE '^2[0-9][0-9]$'; then
    printf "\n${C_DIM}Telegram report delivered (HTTP %s).${C_RESET}\n" "$code"
  else
    printf "\n${C_YELLOW}Telegram report delivery failed (HTTP %s).${C_RESET}\n" "${code:-none}"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  local started; started="$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)"
  printf "${C_BOLD}openclaw smoke test${C_RESET} ${C_DIM}(%s)${C_RESET}\n" "$started"

  check_environment
  check_openclaw
  check_model
  check_integrations
  check_telegram

  local overall="PASS"
  [ "$FAIL_COUNT" -gt 0 ] && overall="FAIL"

  section "Summary"
  printf "  ${C_GREEN}%d passed${C_RESET}, ${C_RED}%d failed${C_RESET}, ${C_YELLOW}%d warn${C_RESET}, ${C_DIM}%d skip${C_RESET}\n" \
    "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT" "$SKIP_COUNT"
  if [ "$overall" = "PASS" ]; then
    printf "  Overall: ${C_GREEN}${C_BOLD}PASS${C_RESET}\n"
  else
    printf "  Overall: ${C_RED}${C_BOLD}FAIL${C_RESET}\n"
  fi

  # Build a compact Telegram report (HTML-escaped failures/warnings).
  local emoji="✅"; [ "$overall" = "FAIL" ] && emoji="❌"
  local host; host="$(uname -n 2>/dev/null || echo unknown)"
  local msg
  msg="${emoji} <b>openclaw smoke test: ${overall}</b>"$'\n'
  msg+="host: <code>${host}</code>"$'\n'
  msg+="${PASS_COUNT} pass / ${FAIL_COUNT} fail / ${WARN_COUNT} warn / ${SKIP_COUNT} skip"$'\n'
  msg+="${started}"
  if [ "$FAIL_COUNT" -gt 0 ] || [ "$WARN_COUNT" -gt 0 ]; then
    msg+=$'\n'
    local r status name detail line
    for r in "${RESULTS[@]}"; do
      status="${r%%|*}"; line="${r#*|}"; name="${line%%|*}"; detail="${line#*|}"
      case "$status" in
        FAIL) msg+=$'\n'"❌ <b>${name}</b>: $(html_escape "$detail")" ;;
        WARN) msg+=$'\n'"⚠️ ${name}: $(html_escape "$detail")" ;;
      esac
    done
  fi

  send_telegram_report "$overall" "$msg"

  [ "$overall" = "PASS" ] && exit 0 || exit 1
}

html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

main "$@"
