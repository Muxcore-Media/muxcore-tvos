#!/usr/bin/env bash
# Pre-flight BFF checks for media-tvos-app (no physical Apple TV required).
# Full hardware checklist still requires Xcode Run on a paired Apple TV.
#
# Usage:
#   ./scripts/bff-soak.sh
#   MUXCORE_BFF_URL=https://mux.zem.systems ./scripts/bff-soak.sh
#   TV_SOAK_USERNAME=... TV_SOAK_PASSWORD=... ./scripts/bff-soak.sh  # authenticated walk
set -euo pipefail

BASE="${MUXCORE_BFF_URL:-https://mux.zem.systems}"
BASE="${BASE%/}"
SESSION=""
FAIL=0

die() { echo "FAIL: $*" >&2; FAIL=1; }

check_code() {
  local label="$1" url="$2" want="$3"
  local code
  code="$(curl -sS -o /tmp/bff-soak-body -w '%{http_code}' "$url" ${SESSION:+-H "Authorization: Bearer $SESSION"})"
  if [[ "$code" != "$want" ]]; then
    die "$label: HTTP $code (want $want) $url"
    head -c 200 /tmp/bff-soak-body >&2 || true
    echo >&2
    return 1
  fi
  echo "OK $label ($code)"
}

check_code_any() {
  local label="$1" url="$2" wants="$3"
  local code
  code="$(curl -sS -o /tmp/bff-soak-body -w '%{http_code}' "$url" ${SESSION:+-H "Authorization: Bearer $SESSION"})"
  if [[ ",$wants," != *",$code,"* ]]; then
    die "$label: HTTP $code (want one of $wants) $url"
    return 1
  fi
  echo "OK $label ($code)"
}

echo "== tvOS BFF soak base=$BASE =="

check_code_any "SPA root" "$BASE/" "200,303"
check_code "capabilities unauth" "$BASE/api/capabilities" "401"
check_code "movies unauth" "$BASE/api/movies?page=1" "401"

if [[ -n "${TV_SOAK_USERNAME:-}" && -n "${TV_SOAK_PASSWORD:-}" ]]; then
  echo "== authenticated TV login =="
  login_body="$(curl -sS -X POST "$BASE/api/tv/login" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -d "$(printf '{"username":"%s","password":"%s"}' "$TV_SOAK_USERNAME" "$TV_SOAK_PASSWORD")")"
  if printf '%s' "$login_body" | grep -q '"requires_2fa"[[:space:]]*:[[:space:]]*true'; then
    partial="$(printf '%s' "$login_body" | sed -n 's/.*"partial_token":"\([^"]*\)".*/\1/p')"
    if [[ -z "${TV_SOAK_TOTP_CODE:-}" || -z "$partial" ]]; then
      die "tv login requires TOTP — set TV_SOAK_TOTP_CODE and retry (partial_token in response)"
    fi
    login_body="$(curl -sS -X POST "$BASE/api/tv/login/totp" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json' \
      -d "$(printf '{"partial_token":"%s","totp_code":"%s"}' "$partial" "$TV_SOAK_TOTP_CODE")")"
  fi
  SESSION="$(printf '%s' "$login_body" | sed -n 's/.*"session_token":"\([^"]*\)".*/\1/p')"
  if [[ -z "$SESSION" ]]; then
    SESSION="$(printf '%s' "$login_body" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
  fi
  if [[ -z "$SESSION" ]]; then
    die "tv login: no session_token in response: $login_body"
  else
    echo "OK tv login"
  fi
  check_code "capabilities auth" "$BASE/api/capabilities" "200"
  check_code "movies auth" "$BASE/api/movies?page=1&page_size=2" "200"
  check_code "userdata auth" "$BASE/api/userdata" "200"
  check_code "search auth" "$BASE/api/search?q=test&scope=library" "200"
fi

if [[ "$FAIL" != "0" ]]; then
  echo "bff-soak FAILED"
  exit 1
fi
echo "bff-soak PASS (authenticated walk: $([[ -n "$SESSION" ]] && echo yes || echo no — set TV_SOAK_USERNAME/TV_SOAK_PASSWORD for full walk))"
echo "Physical Apple TV checklist: docs/HARDWARE-VALIDATION.md"
