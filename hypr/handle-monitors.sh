#!/bin/bash
# Handle the broken laptop panel (eDP-1) dynamically.
# If an external monitor is connected, disable the internal panel so it can't
# steal workspaces. Otherwise keep the internal panel enabled so the laptop
# remains usable on its own.

# Give Hyprland a moment to finish detecting outputs.
sleep 2

if hyprctl monitors all | grep -q '^Monitor HDMI-A-1'; then
    hyprctl keyword monitor eDP-1,disable
else
    hyprctl keyword monitor eDP-1,2880x1800@120,auto,2,bitdepth,10,vrr,1
fi
