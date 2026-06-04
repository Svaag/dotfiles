#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="llama-server.service"

if systemctl --user is-active --quiet "$SERVICE_NAME"; then
    systemctl --user stop "$SERVICE_NAME"
else
    systemctl --user start "$SERVICE_NAME"
fi
