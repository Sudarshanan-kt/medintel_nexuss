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
# Usage: ./scripts/run.sh [--port 8000] [extra uvicorn args...]

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

PORT=8000
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

# Use the project venv when it exists and isn't already active, so the script
# works from a plain shell.
if [[ -z "${VIRTUAL_ENV:-}" && -f venv/bin/activate ]]; then
  # shellcheck disable=SC1091
  source venv/bin/activate
fi

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

exec uvicorn main:app --reload --host 0.0.0.0 --port "${PORT}" "${ARGS[@]+"${ARGS[@]}"}"
