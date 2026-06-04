#!/usr/bin/env bash
set -euo pipefail

SERVICE="llama-server.service"
CONFIG_DIR="$HOME/.config/llama-server"
MODELS_FILE="$CONFIG_DIR/models.tsv"
CURRENT_ENV="$CONFIG_DIR/current.env"

DEFAULT_SERVER_ARGS="--temp 1.0 --top-p 0.95 --top-k 64 -c 262144 -fa on -ngl 999 -t 16 -b 4096 -ub 1024 --no-mmap -np 1"

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "AI Model" "$1"
  fi
}

quote_env() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

if [[ ! -f "$MODELS_FILE" ]]; then
  mkdir -p "$CONFIG_DIR"
  cat > "$MODELS_FILE" <<'EOF'
# label<TAB>model_args<TAB>server_args
Gemma 4 12B BF16	-hf unsloth/gemma-4-12b-it-GGUF:BF16	
EOF
fi

labels=()
lines=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  label="${line%%$'\t'*}"
  [[ -z "$label" ]] && continue
  labels+=("$label")
  lines+=("$line")
done < "$MODELS_FILE"

if [[ ${#labels[@]} -eq 0 ]]; then
  notify "No models configured in $MODELS_FILE"
  exit 1
fi

if ! command -v zenity >/dev/null 2>&1; then
  notify "zenity is required for model picking"
  exit 1
fi

selected="$(zenity \
  --list \
  --title="AI Model" \
  --text="Choose model to load. The llama-server user service will restart." \
  --column="Model" \
  --width=520 \
  --height=360 \
  "${labels[@]}" 2>/dev/null || true)"

[[ -z "$selected" ]] && exit 0

chosen_line=""
for line in "${lines[@]}"; do
  label="${line%%$'\t'*}"
  if [[ "$label" == "$selected" ]]; then
    chosen_line="$line"
    break
  fi
done

if [[ -z "$chosen_line" ]]; then
  notify "Selection not found: $selected"
  exit 1
fi

IFS=$'\t' read -r label model_args server_args <<< "$chosen_line"
server_args="${server_args:-$DEFAULT_SERVER_ARGS}"
[[ -z "$server_args" ]] && server_args="$DEFAULT_SERVER_ARGS"

mkdir -p "$CONFIG_DIR"
{
  printf 'AI_MODEL_LABEL=%s\n' "$(quote_env "$label")"
  printf 'LLAMA_MODEL_ARGS=%s\n' "$(quote_env "$model_args")"
  printf 'LLAMA_SERVER_ARGS=%s\n' "$(quote_env "$server_args")"
} > "$CURRENT_ENV"

systemctl --user daemon-reload
systemctl --user restart "$SERVICE"

notify "Switched to $label"

# Ask Waybar to refresh soon by restarting only if a RT signal is configured elsewhere; interval handles it otherwise.
exit 0
