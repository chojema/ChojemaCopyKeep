#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
case "$MODE" in run|--debug|--logs|--telemetry|--verify) ;; *) echo "Usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;; esac
pkill -x ChojemaCopyKeep >/dev/null 2>&1 || true
bash "$ROOT_DIR/tools/build-macos.sh" native
APP_BUNDLE="$ROOT_DIR/build/macos/Chojema CopyKeep.app"
case "$MODE" in
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/ChojemaCopyKeep" ;;
  --logs|--telemetry)
    open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "ChojemaCopyKeep"'
    ;;
  --verify) open -n "$APP_BUNDLE"; sleep 1; pgrep -x ChojemaCopyKeep >/dev/null ;;
  run) open -n "$APP_BUNDLE" ;;
esac
