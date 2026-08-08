#!/usr/bin/env bash
#
# Installs MedIntel Nexus and its on-device AI model onto a USB-connected
# Android phone.
#
#   ./scripts/install_to_phone.sh [path-to-model.task]
#
# The model is a ~1.6 GB file that is deliberately NOT bundled in the APK —
# it would make the download unusable. It's pushed separately, once. After
# that the assistant runs entirely on the phone: no backend, no Wi-Fi, and
# nothing said to it leaves the handset.
#
# Re-running is safe. The APK is reinstalled over the top (data is kept),
# and the model push is skipped if the file is already there at the right
# size.

set -euo pipefail

PACKAGE="com.medintelnexus.medintel_nexus"
APK="build/app/outputs/flutter-apk/app-release.apk"
MODEL_NAME="qwen2.5-1.5b-it-q8.task"
# External app storage — the only app-owned location adb can write to
# without root. Must match OnDeviceLlm._candidatePaths() in the Dart code.
REMOTE_DIR="/sdcard/Android/data/$PACKAGE/files"

MODEL_SRC="${1:-}"

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
info()  { printf '\033[1m%s\033[0m\n' "$1"; }

# ── Preflight ──────────────────────────────────────────────────────────────

if ! command -v adb >/dev/null 2>&1; then
  red "adb not found. Install Android platform-tools first."
  exit 1
fi

adb start-server >/dev/null 2>&1 || true
if [ -z "$(adb devices | sed '1d' | grep -w device || true)" ]; then
  red "No phone detected."
  echo "  • Connect it by USB"
  echo "  • Enable Developer options → USB debugging"
  echo "  • Unlock the screen and accept the debugging prompt"
  exit 1
fi

if [ ! -f "$APK" ]; then
  red "No APK at $APK"
  echo "Build one first:"
  echo "  flutter build apk --release --dart-define=API_BASE_URL=http://\$(ipconfig getifaddr en0):8000"
  exit 1
fi

# ── App ────────────────────────────────────────────────────────────────────

info "Installing the app…"
adb install -r "$APK"
green "App installed."

# The external files directory only exists once the app has run at least
# once, so create it rather than assuming.
adb shell mkdir -p "$REMOTE_DIR" >/dev/null 2>&1 || true

# ── Model ──────────────────────────────────────────────────────────────────

if [ -z "$MODEL_SRC" ]; then
  echo
  info "No model file given — skipping the AI model."
  echo "The assistant will use the backend, or its built-in replies."
  echo "To install the on-device model, re-run with the path:"
  echo "  ./scripts/install_to_phone.sh ~/Downloads/$MODEL_NAME"
  exit 0
fi

if [ ! -f "$MODEL_SRC" ]; then
  red "Model file not found: $MODEL_SRC"
  exit 1
fi

LOCAL_SIZE=$(wc -c < "$MODEL_SRC" | tr -d ' ')
REMOTE_SIZE=$(adb shell "stat -c %s '$REMOTE_DIR/$MODEL_NAME' 2>/dev/null" | tr -dc '0-9' || true)

if [ "${REMOTE_SIZE:-0}" = "$LOCAL_SIZE" ]; then
  green "Model already on the phone and complete — skipping the push."
else
  info "Pushing the AI model ($(( LOCAL_SIZE / 1000000 )) MB). This takes a few minutes…"
  adb push "$MODEL_SRC" "$REMOTE_DIR/$MODEL_NAME"

  PUSHED=$(adb shell "stat -c %s '$REMOTE_DIR/$MODEL_NAME' 2>/dev/null" | tr -dc '0-9' || true)
  if [ "${PUSHED:-0}" != "$LOCAL_SIZE" ]; then
    red "Push incomplete: $PUSHED of $LOCAL_SIZE bytes."
    echo "A truncated model will fail to load. Re-run to try again."
    exit 1
  fi
  green "Model installed and verified."
fi

echo
green "Done. Open the app → Assistant."
echo "The status sheet (top-right) should say \"Running on this phone\"."
