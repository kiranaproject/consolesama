#!/usr/bin/env bash
set -euo pipefail

ARTIFACTS_DIR="/home/afumi/.gemini/antigravity-cli/brain/975c8ef3-e22c-4d09-b28d-309845524761"
mkdir -p "${ARTIFACTS_DIR}"

pkill -9 -f "Xephyr :2" 2>/dev/null || true
pkill -9 -f "target/wmsama" 2>/dev/null || true
pkill -9 -f "target/consolesama" 2>/dev/null || true
sleep 1

Xephyr :2 -screen 1280x800 -ac -br -noreset &
XEPHYR_PID=$!

cleanup() {
  echo "Cleaning up processes..."
  kill -9 "${CONSOLESAMA_PID:-0}" "${WM_PID:-0}" "${XEPHYR_PID:-0}" 2>/dev/null || true
  pkill -9 -f "Xephyr :2" 2>/dev/null || true
  pkill -9 -f "target/consolesama" 2>/dev/null || true
  wait "${XEPHYR_PID:-0}" 2>/dev/null || true
}
trap cleanup EXIT

for i in $(seq 1 30); do
  if [ -e "/tmp/.X11-unix/X2" ]; then
    break
  fi
  sleep 0.1
done

export DISPLAY=:2

/home/afumi/Documents/projects/kirana/wmsama/target/wmsama &
WM_PID=$!
sleep 1

LIBFT_PATH="/home/afumi/Documents/projects/kirana/ftpas/target/libft.so" \
/home/afumi/Documents/projects/kirana/consolesama/target/consolesama &
CONSOLESAMA_PID=$!
sleep 2

# Screenshot 1: initial window with shell prompt
import -window root "${ARTIFACTS_DIR}/consolesama_initial.png"

WIN_ID=$(xdotool search --name "consolesama" | head -n1 || true)
if [ -z "${WIN_ID}" ]; then
  WIN_ID=$(xdotool search --onlyvisible "" | tail -n1 || true)
fi

echo "Focusing window ${WIN_ID}..."
xdotool windowfocus --sync "${WIN_ID}"
sleep 0.5

xdotool type --delay 30 "echo 'Hello from Kirana consolesama!'"
xdotool key Return
sleep 0.5
xdotool type --delay 30 "ls --color=always -la src/main/pascal"
xdotool key Return
sleep 1.5

# Screenshot 2: executed commands and color output
import -window root "${ARTIFACTS_DIR}/consolesama_commands.png"

# Test opening a new tab via Ctrl+Shift+T
xdotool key ctrl+shift+t
sleep 1.5
xdotool type --delay 30 "uname -a"
xdotool key Return
sleep 1.5

# Screenshot 3: multi-tab session
import -window root "${ARTIFACTS_DIR}/consolesama_tabs.png"

echo "Live verification completed successfully."
