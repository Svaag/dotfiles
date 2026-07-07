#!/usr/bin/env bash
# Keep Hyprland's monitor state and Waybar in sync after hotplug events.
# Waybar can keep the old HDMI layer coordinates after HDMI-A-1 is removed;
# a restart after Hyprland settles recreates it on the remaining output.

set -u

handler="$HOME/.config/hypr/handle-monitors.sh"

log() {
    printf '[hypr-monitor-events] %s\n' "$*" >&2
}

apply_monitor_layout() {
    if [[ -x "$handler" ]]; then
        "$handler" || log "monitor handler failed"
    else
        log "monitor handler is not executable: $handler"
    fi

    systemctl --user restart waybar-hyprland.service || log "failed to restart waybar"
}

socket_path() {
    printf '%s/hypr/%s/.socket2.sock' "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" "${HYPRLAND_INSTANCE_SIGNATURE:-}"
}

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    log 'HYPRLAND_INSTANCE_SIGNATURE is not set; start this from Hyprland.'
    exit 1
fi

# Normalize the initial layout shortly after login, then keep watching hotplug events.
apply_monitor_layout

missing_socket_ticks=0

while true; do
    socket="$(socket_path)"

    if [[ ! -S "$socket" ]]; then
        missing_socket_ticks=$((missing_socket_ticks + 1))
        log "waiting for Hyprland event socket: $socket"

        # Avoid leaving stale handlers behind after a Hyprland session exits.
        if (( missing_socket_ticks >= 30 )); then
            log 'Hyprland event socket did not return; exiting stale handler.'
            exit 0
        fi

        sleep 1
        continue
    fi

    missing_socket_ticks=0

    nc -U -d "$socket" | while IFS= read -r event; do
        case "$event" in
            monitoradded*|monitorremoved*)
                log "handling $event"
                # Let Hyprland finish updating output geometry before restarting Waybar.
                sleep 1
                apply_monitor_layout
                ;;
        esac
    done

    # Reconnect if Hyprland recreates the socket.
    sleep 1
done
