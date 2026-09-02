#!/usr/bin/env bash
# BFF soak for tvOS client paths (no Apple TV hardware required).
#
# Anonymous checks always run. Authenticated walk runs when credentials are set.
#
# Usage:
#   ./scripts/bff-soak.sh
#   MUX_BASE_URL=https://mux.zem.systems ./scripts/bff-soak.sh
#   MUX_TV_USER=ender MUX_TV_PASS=secret ./scripts/bff-soak.sh
#   MUX_SESSION='mux_session=…' ./scripts/bff-soak.sh   # skip login, use existing cookie
#
# TOTP (optional second step when login returns partial_token):
#   MUX_TV_TOTP=123456 MUX_TV_PARTIAL_TOKEN=… ./scripts/bff-soak.sh
set -euo pipefail

BASE="${MUX_BASE_URL:-https://mux.zem.systems}"
BASE="${BASE%/}"
CURL=(curl -sS --connect-timeout 8 --max-time 25)
fail=0

die() { echo "FAIL: $*" >&2; fail=1; }

check_code() {
  local label="$1" url="$2" expect="$3"
  local code
  code=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 000)
  if [[ "$expect" == *"$code"* ]]; then
    printf 'ok   %s → %s\n' "$label" "$code"
  else
    printf 'FAIL %s → %s (want %s)\n' "$label" "$code" "$expect"
    fail=1
  fi
}

echo "bff-soak base=$BASE"

check_code 'GET /' "$BASE/" '200 302 303'
check_code 'GET /api/capabilities' "$BASE/api/capabilities" '200'

# Quick Connect register (no auth)
qc_body=$("${CURL[@]}" -X POST "$BASE/api/quickconnect" \
  -H 'Content-Type: application/json' \
  -d '{"action":"register"}' 2>/dev/null || true)
if echo "$qc_body" | grep -q '"code"'; then
  echo 'ok   POST /api/quickconnect register → code returned'
else
  die "POST /api/quickconnect register — no code in response"
fi

session_cookie="${MUX_SESSION:-}"
partial_token="${MUX_TV_PARTIAL_TOKEN:-}"

if [[ -z "$session_cookie" && -n "${MUX_TV_USER:-}" && -n "${MUX_TV_PASS:-}" ]]; then
  login_body=$("${CURL[@]}" -X POST "$BASE/api/tv/login" \
    -H 'Content-Type: application/json' \
    -d "$(printf '{"username":"%s","password":"%s"}' "$MUX_TV_USER" "$MUX_TV_PASS")" 2>/dev/null || true)

  if echo "$login_body" | grep -q '"session_token"'; then
    token=$(echo "$login_body" | sed -n 's/.*"session_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    session_cookie="mux_session=$token"
    echo 'ok   POST /api/tv/login → session_token'
  elif echo "$login_body" | grep -q '"partial_token"'; then
    partial_token=$(echo "$login_body" | sed -n 's/.*"partial_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    echo 'ok   POST /api/tv/login → partial_token (TOTP required)'
  else
    die "POST /api/tv/login — unexpected response: ${login_body:0:120}"
  fi
fi

if [[ -n "$partial_token" && -n "${MUX_TV_TOTP:-}" ]]; then
  totp_body=$("${CURL[@]}" -X POST "$BASE/api/tv/login/totp" \
    -H 'Content-Type: application/json' \
    -d "$(printf '{"partial_token":"%s","totp_code":"%s"}' "$partial_token" "$MUX_TV_TOTP")" 2>/dev/null || true)
  if echo "$totp_body" | grep -q '"session_token"'; then
    token=$(echo "$totp_body" | sed -n 's/.*"session_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    session_cookie="mux_session=$token"
    echo 'ok   POST /api/tv/login/totp → session_token'
  else
    die "POST /api/tv/login/totp — unexpected response: ${totp_body:0:120}"
  fi
fi

if [[ -n "$session_cookie" ]]; then
  for path in /api/capabilities /api/movies?page=1\&limit=1 /api/tv?page=1 /api/userdata/progress; do
    code=$("${CURL[@]}" -o /dev/null -w '%{http_code}' -H "Cookie: $session_cookie" "$BASE$path" 2>/dev/null || echo 000)
    if [[ "$code" == "200" ]]; then
      printf 'ok   GET %s (auth) → %s\n' "$path" "$code"
    else
      printf 'FAIL GET %s (auth) → %s (want 200)\n' "$path" "$code"
      fail=1
    fi
  done
else
  echo 'skip authenticated walk (set MUX_SESSION or MUX_TV_USER/MUX_TV_PASS)'
fi

exit "$fail"
