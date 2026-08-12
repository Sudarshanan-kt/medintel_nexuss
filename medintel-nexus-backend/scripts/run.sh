#!/usr/bin/env bash
#
# Starts the backend so a phone on the same Wi-Fi can actually reach it.
#
# The bind address is the whole point of this script. `uvicorn main:app`
# defaults to 127.0.0.1, which serves this machine and refuses everything
# else — the API looks perfectly healthy from `curl localhost:8000` while
# every request from the phone is refused before it reaches Python. Binding
# 0.0.0.0 listens on the LAN interface too.
#
# Binding 0.0.0.0 also means everything here is reachable by everyone else on
# the network, which is worth keeping in mind on Wi-Fi you don't own. The API
# requires a Supabase token on every route, so that is a locked door rather
# than an open one — unless AUTH_DISABLED is set, which this warns about.
#
# Usage: ./scripts/run.sh [--port 8000] [--no-reload] [extra uvicorn args...]

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

PORT=8000
# Hot reload is on by default because this is a development server. It costs
# a dropped connection on every save, which during a demo lands as a scan
# that fails for no visible reason — hence --no-reload.
RELOAD=1
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --no-reload) RELOAD=0; shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

# Use the project venv when it exists and isn't already active, so the script
# works from a plain shell.
if [[ -z "${VIRTUAL_ENV:-}" && -f venv/bin/activate ]]; then
  # shellcheck disable=SC1091
  source venv/bin/activate
fi

# The pairing code that lets the app tell this backend apart from anything
# else answering on the LAN. Written to .env on first run and reused after
# that: the app stores it too, so a code that changed every run would mean
# re-pairing the phone every run.
ensure_discovery_secret() {
  local existing
  existing="$(grep -m1 '^DISCOVERY_SECRET=' .env 2>/dev/null | cut -d= -f2- || true)"
  if [[ -n "${existing:-}" ]]; then
    echo "$existing"
    return
  fi

  local generated
  if command -v openssl >/dev/null 2>&1; then
    generated="$(openssl rand -hex 16)"
  else
    generated="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
  fi

  # Keep an existing .env intact — it holds the Supabase secrets. Append,
  # after a newline if the file doesn't already end in one, or the new key
  # lands on the end of the last line and neither is readable.
  if [[ -f .env && -n "$(tail -c1 .env)" ]]; then
    echo >> .env
  fi
  {
    echo "# Lets the app verify this is its backend and not something else"
    echo "# answering on the same Wi-Fi. Generated once; enter it in the app"
    echo "# under Profile -> server settings."
    echo "DISCOVERY_SECRET=${generated}"
  } >> .env
  echo "$generated"
}

SECRET="$(ensure_discovery_secret)"

# The address to type into the app's server setting, or to sanity-check with
# curl from another device. Best-effort: a machine with no LAN address (or a
# non-macOS/Linux one) just doesn't get the hint.
lan_ip() {
  if command -v ipconfig >/dev/null 2>&1; then
    for iface in en0 en1 en2; do
      ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
      [[ -n "$ip" ]] && { echo "$ip"; return; }
    done
  fi
  if command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{print $1}'
  fi
}

IP="$(lan_ip || true)"
echo "MedIntel backend → http://0.0.0.0:${PORT}"
if [[ -n "${IP:-}" ]]; then
  echo "  from this machine : http://localhost:${PORT}/health"
  echo "  from the phone    : http://${IP}:${PORT}/health"
  echo
  echo "If the phone can't reach that, it is on a different network, on mobile"
  echo "data, or the router isolates clients from each other."
else
  echo "  (no LAN address detected — the phone will not be able to reach this)"
fi
echo
echo "  pairing code      : ${SECRET}"
echo "  Enter that once in the app under Profile -> server settings. Without"
echo "  it the app will not adopt a server it finds by scanning the network."
echo

# AUTH_DISABLED plus an 0.0.0.0 bind is the combination that turns a locked
# API into an open one, so say so where it can't be missed. The server
# enforces this too — with auth off it answers this machine only — but by
# then the symptom is "the phone gets 403 on everything", which is worth
# being able to recognise.
auth_disabled_setting="$(grep -m1 '^AUTH_DISABLED=' .env 2>/dev/null | cut -d= -f2- | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' || true)"
if [[ "${auth_disabled_setting:-}" == "true" || "${auth_disabled_setting:-}" == "1" ]]; then
  echo "  !! AUTH_DISABLED=true — every caller is treated as 'dev-user'."
  echo "     The phone will get 403s: with auth off this serves localhost"
  echo "     only, rather than opening patient records to the whole network."
  echo "     Set SUPABASE_JWT_SECRET and AUTH_DISABLED=false to use a phone."
  echo
fi

RELOAD_ARGS=()
if [[ "$RELOAD" == "1" ]]; then
  RELOAD_ARGS+=(--reload)
fi

exec uvicorn main:app "${RELOAD_ARGS[@]+"${RELOAD_ARGS[@]}"}" \
  --host 0.0.0.0 --port "${PORT}" "${ARGS[@]+"${ARGS[@]}"}"
