#!/usr/bin/env bash
set -euo pipefail

ROCM_SMI="/opt/rocm/bin/rocm-smi"

if [[ ! -x "$ROCM_SMI" ]]; then
  echo '{"text":"󰢮 N/A","tooltip":"rocm-smi not found","class":"vram-error"}'
  exit 0
fi

out="$($ROCM_SMI --showmeminfo vram 2>/dev/null || true)"

total_bytes="$(awk -F': ' '/VRAM Total Memory \(B\)/ {print $NF; exit}' <<< "$out" | tr -d '[:space:]')"
used_bytes="$(awk -F': ' '/VRAM Total Used Memory \(B\)/ {print $NF; exit}' <<< "$out" | tr -d '[:space:]')"

if [[ -z "${total_bytes:-}" || -z "${used_bytes:-}" || "$total_bytes" == "0" ]]; then
  echo '{"text":"󰢮 N/A","tooltip":"VRAM info unavailable","class":"vram-error"}'
  exit 0
fi

awk -v used="$used_bytes" -v total="$total_bytes" 'BEGIN {
  used_gib = used / 1024 / 1024 / 1024;
  total_gib = total / 1024 / 1024 / 1024;
  pct = (used / total) * 100;

  cls = "vram-ok";
  if (pct >= 90) cls = "vram-critical";
  else if (pct >= 75) cls = "vram-warning";

  printf "{\"text\":\"󰢮 %.1f/%.0fG\",\"tooltip\":\"VRAM: %.1f GiB / %.1f GiB (%.0f%%)\",\"class\":\"%s\"}\n", used_gib, total_gib, used_gib, total_gib, pct, cls;
}'
