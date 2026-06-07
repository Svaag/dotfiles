#!/usr/bin/env bash
set -euo pipefail

SERVICE="llama-server.service"
CONFIG_DIR="$HOME/.config/llama-server"
MODELS_FILE="$CONFIG_DIR/models.tsv"
CURRENT_ENV="$CONFIG_DIR/current.env"

DEFAULT_SERVER_ARGS="--temp 1.0 --top-p 0.95 --top-k 64 -c 262144 -fa on -ngl 999 -t 16 -b 4096 -ub 1024 --no-mmap -np 1"
ADD_HF_LABEL="➕ Add Hugging Face GGUF model…"
ADD_LOCAL_LABEL="📁 Add local GGUF model…"

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "AI Model" "$1"
  fi
}

error_dialog() {
  local msg="$1"
  if command -v zenity >/dev/null 2>&1; then
    zenity --error --title="AI Model" --text="$msg" --width=520 2>/dev/null || true
  fi
  notify "$msg"
}

quote_env() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

ensure_models_file() {
  if [[ ! -f "$MODELS_FILE" ]]; then
    mkdir -p "$CONFIG_DIR"
    cat > "$MODELS_FILE" <<'EOF'
# label<TAB>model_args<TAB>server_args
# Add more models below. model_args can be: -hf owner/repo --hf-file model.gguf OR -m /path/to/model.gguf
# If server_args is empty, the picker uses DEFAULT_SERVER_ARGS from ai-model-picker.sh.
Gemma 4 12B BF16	-m /home/svag/.local/share/llama-server/models/gemma-4-12b-it-BF16.gguf	
EOF
  fi
}

validate_tsv_field() {
  local field_name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    error_dialog "$field_name cannot be empty."
    return 1
  fi
  if [[ "$value" == *$'\t'* || "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    error_dialog "$field_name cannot contain tabs or newlines."
    return 1
  fi
}

load_models() {
  labels=()
  lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    local label="${line%%$'\t'*}"
    [[ -z "$label" ]] && continue
    labels+=("$label")
    lines+=("$line")
  done < "$MODELS_FILE"
}

start_model() {
  local label="$1"
  local model_args="$2"
  local server_args="${3:-$DEFAULT_SERVER_ARGS}"
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
}

upsert_model() {
  local label="$1"
  local model_args="$2"
  local server_args="${3:-}"

  validate_tsv_field "Label" "$label" || return 1
  validate_tsv_field "Model args" "$model_args" || return 1
  if [[ "$server_args" == *$'\t'* || "$server_args" == *$'\n'* || "$server_args" == *$'\r'* ]]; then
    error_dialog "Server args cannot contain tabs or newlines."
    return 1
  fi

  mkdir -p "$CONFIG_DIR"

  local exists=0
  local line existing_label
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    existing_label="${line%%$'\t'*}"
    if [[ "$existing_label" == "$label" ]]; then
      exists=1
      break
    fi
  done < "$MODELS_FILE"

  if [[ "$exists" -eq 1 ]]; then
    if ! zenity --question --title="Replace model?" --text="A model named '$label' already exists. Replace it?" --width=520 2>/dev/null; then
      return 1
    fi
  fi

  local tmp
  tmp="$(mktemp)"
  local replaced=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
      printf '%s\n' "$line" >> "$tmp"
      continue
    fi
    existing_label="${line%%$'\t'*}"
    if [[ "$existing_label" == "$label" ]]; then
      if [[ "$replaced" -eq 0 ]]; then
        printf '%s\t%s\t%s\n' "$label" "$model_args" "$server_args" >> "$tmp"
        replaced=1
      fi
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$MODELS_FILE"

  if [[ "$replaced" -eq 0 ]]; then
    printf '%s\t%s\t%s\n' "$label" "$model_args" "$server_args" >> "$tmp"
  fi

  mv "$tmp" "$MODELS_FILE"
}

prompt_label() {
  local default_label="$1"
  zenity \
    --entry \
    --title="Model label" \
    --text="Choose the label shown in Waybar:" \
    --entry-text="$default_label" \
    --width=520 2>/dev/null
}

prompt_server_args() {
  local default_args="$1"
  zenity \
    --entry \
    --title="llama-server args" \
    --text="Optional llama-server args for this model. Clear to use the default args." \
    --entry-text="$default_args" \
    --width=900 2>/dev/null
}

ask_start_added_model() {
  local label="$1"
  local model_args="$2"
  local server_args="$3"

  if zenity --question --title="Start model?" --text="Added '$label'. Start it now?" --width=520 2>/dev/null; then
    start_model "$label" "$model_args" "$server_args"
  else
    notify "Added $label"
  fi
}

hf_search_repos() {
  local query="$1"
  python3 - "$query" <<'PY'
import json
import re
import sys
import urllib.parse
import urllib.request

query = sys.argv[1].strip()
seen = set()

# If the user pasted an exact repo id, show it first. File lookup will validate it.
if re.match(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", query):
    print(f"{query}\tmanual\tmanual")
    seen.add(query.lower())

search = query if "gguf" in query.lower() else f"{query} gguf"
url = "https://huggingface.co/api/models?" + urllib.parse.urlencode({
    "search": search,
    "limit": "50",
    "sort": "downloads",
    "direction": "-1",
})

with urllib.request.urlopen(url, timeout=12) as r:
    models = json.load(r)

for model in models:
    repo = model.get("modelId") or model.get("id")
    if not repo or repo.lower() in seen:
        continue
    tags = [str(t).lower() for t in model.get("tags") or []]
    if "gguf" not in tags and "gguf" not in repo.lower():
        continue
    seen.add(repo.lower())
    downloads = model.get("downloads")
    likes = model.get("likes")
    print(f"{repo}\t{downloads if downloads is not None else ''}\t{likes if likes is not None else ''}")
PY
}

hf_list_gguf_files() {
  local repo="$1"
  python3 - "$repo" <<'PY'
import json
import os
import re
import sys
import urllib.parse
import urllib.request

repo = sys.argv[1]
url = "https://huggingface.co/api/models/" + urllib.parse.quote(repo, safe="/")
with urllib.request.urlopen(url, timeout=12) as r:
    info = json.load(r)

files = []
for sibling in info.get("siblings") or []:
    name = sibling.get("rfilename") or ""
    lower = name.lower()
    if not lower.endswith(".gguf"):
        continue
    # These are helper/projector/draft files, not the normal text model the Waybar server should load.
    if "mmproj" in lower or "/mtp/" in lower or "-mtp-" in lower:
        continue
    base = os.path.basename(name)
    note = ""
    m = re.search(r"(BF16|F16|Q[0-9]_[A-Z0-9_]+)", base, re.IGNORECASE)
    if m:
        note = m.group(1).upper()
    files.append((name, note))

for name, note in sorted(files, key=lambda item: item[0].lower()):
    print(f"{name}\t{note}")
PY
}

add_hf_model() {
  local query
  if ! query="$(zenity \
    --entry \
    --title="Add Hugging Face GGUF model" \
    --text="Search Hugging Face GGUF repos, or paste an exact repo id (owner/repo):" \
    --entry-text="" \
    --width=650 2>/dev/null)"; then
    return 0
  fi
  [[ -z "$query" ]] && return 0

  local err_file out_file
  err_file="$(mktemp)"
  out_file="$(mktemp)"
  if ! hf_search_repos "$query" >"$out_file" 2>"$err_file"; then
    local err
    err="$(<"$err_file")"
    rm -f "$err_file" "$out_file"
    error_dialog "Could not search Hugging Face.\n\n${err:-Unknown error}"
    return 1
  fi
  mapfile -t repo_rows < "$out_file"
  rm -f "$err_file" "$out_file"

  if [[ "${#repo_rows[@]}" -eq 0 ]]; then
    error_dialog "No GGUF repositories found for: $query"
    return 1
  fi

  local repo_args=()
  local row repo downloads likes
  for row in "${repo_rows[@]}"; do
    IFS=$'\t' read -r repo downloads likes <<< "$row"
    repo_args+=("$repo" "$downloads" "$likes")
  done

  local selected_repo
  if ! selected_repo="$(zenity \
    --list \
    --title="Hugging Face results" \
    --text="Choose a GGUF repository. Results are searched live from Hugging Face." \
    --column="Repository" \
    --column="Downloads" \
    --column="Likes" \
    --print-column=1 \
    --width=900 \
    --height=520 \
    "${repo_args[@]}" 2>/dev/null)"; then
    return 0
  fi
  [[ -z "$selected_repo" ]] && return 0

  err_file="$(mktemp)"
  out_file="$(mktemp)"
  if ! hf_list_gguf_files "$selected_repo" >"$out_file" 2>"$err_file"; then
    local err
    err="$(<"$err_file")"
    rm -f "$err_file" "$out_file"
    error_dialog "Could not list GGUF files for $selected_repo.\n\n${err:-Unknown error}"
    return 1
  fi
  mapfile -t file_rows < "$out_file"
  rm -f "$err_file" "$out_file"

  if [[ "${#file_rows[@]}" -eq 0 ]]; then
    error_dialog "No normal GGUF model files found in $selected_repo.\n\nMTP and mmproj helper files are hidden to avoid loading the wrong model."
    return 1
  fi

  local file_args=()
  local file note
  for row in "${file_rows[@]}"; do
    IFS=$'\t' read -r file note <<< "$row"
    file_args+=("$file" "$note")
  done

  local selected_file
  if ! selected_file="$(zenity \
    --list \
    --title="Choose GGUF file" \
    --text="Choose the exact model file to load. MTP/mmproj helper files are hidden." \
    --column="GGUF file" \
    --column="Quant" \
    --print-column=1 \
    --width=900 \
    --height=520 \
    "${file_args[@]}" 2>/dev/null)"; then
    return 0
  fi
  [[ -z "$selected_file" ]] && return 0

  local base default_label label model_args server_args
  base="${selected_file##*/}"
  default_label="${base%.gguf}"
  default_label="${default_label//-/ }"

  if ! label="$(prompt_label "$default_label")"; then
    return 0
  fi
  [[ -z "$label" ]] && return 0

  # For HF text models, disabling automatic mmproj avoids llama-server picking projector/helper files from the repo.
  if ! server_args="$(prompt_server_args "$DEFAULT_SERVER_ARGS --no-mmproj")"; then
    return 0
  fi
  [[ -z "$server_args" ]] && server_args="$DEFAULT_SERVER_ARGS --no-mmproj"

  model_args="-hf $selected_repo --hf-file $selected_file"
  upsert_model "$label" "$model_args" "$server_args" || return 1
  ask_start_added_model "$label" "$model_args" "$server_args"
}

add_local_model() {
  local path
  if ! path="$(zenity \
    --file-selection \
    --title="Choose local GGUF model" \
    --file-filter="GGUF files | *.gguf" \
    --file-filter="All files | *" \
    --width=900 2>/dev/null)"; then
    return 0
  fi
  [[ -z "$path" ]] && return 0

  if [[ "$path" == *[[:space:]]* ]]; then
    error_dialog "This launcher currently cannot safely start model paths containing spaces:\n$path"
    return 1
  fi

  local base default_label label server_args model_args
  base="${path##*/}"
  default_label="${base%.gguf}"
  default_label="${default_label//-/ }"

  if ! label="$(prompt_label "$default_label")"; then
    return 0
  fi
  [[ -z "$label" ]] && return 0

  if ! server_args="$(prompt_server_args "$DEFAULT_SERVER_ARGS")"; then
    return 0
  fi
  [[ -z "$server_args" ]] && server_args="$DEFAULT_SERVER_ARGS"

  model_args="-m $path"
  upsert_model "$label" "$model_args" "$server_args" || return 1
  ask_start_added_model "$label" "$model_args" "$server_args"
}

main() {
  if ! command -v zenity >/dev/null 2>&1; then
    notify "zenity is required for model picking"
    exit 1
  fi

  ensure_models_file
  load_models

  local list_items=()
  local label
  for label in "${labels[@]}"; do
    list_items+=("$label")
  done
  list_items+=("$ADD_HF_LABEL" "$ADD_LOCAL_LABEL")

  local selected
  selected="$(zenity \
    --list \
    --title="AI Model" \
    --text="Choose model to load, or add a new model. The llama-server user service will restart when a model is started." \
    --column="Model" \
    --width=620 \
    --height=420 \
    "${list_items[@]}" 2>/dev/null || true)"

  [[ -z "$selected" ]] && exit 0

  case "$selected" in
    "$ADD_HF_LABEL")
      add_hf_model
      exit $?
      ;;
    "$ADD_LOCAL_LABEL")
      add_local_model
      exit $?
      ;;
  esac

  local chosen_line=""
  local line existing_label model_args server_args
  for line in "${lines[@]}"; do
    existing_label="${line%%$'\t'*}"
    if [[ "$existing_label" == "$selected" ]]; then
      chosen_line="$line"
      break
    fi
  done

  if [[ -z "$chosen_line" ]]; then
    error_dialog "Selection not found: $selected"
    exit 1
  fi

  IFS=$'\t' read -r label model_args server_args <<< "$chosen_line"
  server_args="${server_args:-$DEFAULT_SERVER_ARGS}"
  [[ -z "$server_args" ]] && server_args="$DEFAULT_SERVER_ARGS"
  start_model "$label" "$model_args" "$server_args"
}

main "$@"
