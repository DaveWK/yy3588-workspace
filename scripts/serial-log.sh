#!/bin/bash
# Start a detached screen session "yy3588-uart" running picocom on the YY3588 UART
# (1500000 8N1), logging to ./serial-logs/<timestamp>-<label>.log.
# Usage: ./serial-log.sh [label] [device]
#   attach: screen -r yy3588-uart   detach: Ctrl-A d   quit picocom: Ctrl-X Ctrl-Q
set -euo pipefail
label="${1:-run}"
dev="${2:-/dev/ttyUSB0}"
session=yy3588-uart
dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/serial-logs"
mkdir -p "$dir"
out="$dir/$(date +%Y-%m-%d-%H%M)-$label.log"
if [ ! -c "$dev" ]; then
    echo "no serial device $dev (adapter unplugged?); found: $(find /dev -maxdepth 1 \( -name "ttyUSB*" -o -name "ttyACM*" \) -printf "%p ")" >&2
    exit 1
fi
if screen -ls | grep -q "[.]${session}[[:space:]]"; then
    echo "screen session $session already running (screen -r $session)" >&2
    exit 1
fi
# picocom's escape is Ctrl-X so Ctrl-A stays with screen.
screen -dmS "$session" picocom -b 1500000 -e x --logfile "$out" "$dev"
echo "logging $dev to $out; attach with: screen -r $session" >&2
