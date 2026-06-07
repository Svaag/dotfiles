#!/usr/bin/env bash
set -euo pipefail

player="spotify"

if ! playerctl -p "$player" metadata >/dev/null 2>&1; then
  exit 1
fi

status="$(playerctl -p "$player" status 2>/dev/null || echo Stopped)"
artist="$(playerctl -p "$player" metadata xesam:artist 2>/dev/null || true)"
title="$(playerctl -p "$player" metadata xesam:title 2>/dev/null || true)"
album="$(playerctl -p "$player" metadata xesam:album 2>/dev/null || true)"

if [[ -z "$artist" && -z "$title" ]]; then
  exit 1
fi

case "$status" in
  Playing) icon=""; class="playing" ;;
  Paused) icon=""; class="paused" ;;
  *) icon=""; class="stopped" ;;
esac

track="$artist - $title"
max=55
if (( ${#track} > max )); then
  track="${track:0:max-1}…"
fi

python3 - "$icon" "$track" "$artist" "$title" "$album" "$status" "$class" <<'PY'
import json, sys
icon, track, artist, title, album, status, klass = sys.argv[1:]
tooltip = f"Spotify: {status}\n{artist} - {title}"
if album:
    tooltip += f"\nAlbum: {album}"
print(json.dumps({"text": f"{icon}  {track}", "tooltip": tooltip, "class": klass}))
PY
