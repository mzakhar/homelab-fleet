#!/bin/sh
set -eu

directory=/var/lib/prometheus/node-exporter
temporary="$directory/kitchen_hub.prom.$$"
trap 'rm -f "$temporary"' EXIT

touchscreen=0
test -e /dev/input/by-id/usb-ILITEK_ILITEK-TP-event-if00 && touchscreen=1

hdmi=0
test "$(cat /sys/class/drm/card1-HDMI-A-1/status 2>/dev/null || true)" = connected && hdmi=1

kiosk=0
if pgrep -x chromium >/dev/null && runuser -u mzakhar -- env \
  XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  systemctl --user is-active --quiet kiosk-screen.timer; then
  kiosk=1
fi

umask 022
{
  printf '# HELP kitchen_hub_touchscreen_present ILITEK touchscreen is present.\n'
  printf '# TYPE kitchen_hub_touchscreen_present gauge\n'
  printf 'kitchen_hub_touchscreen_present %s\n' "$touchscreen"
  printf '# HELP kitchen_hub_hdmi_connected Kitchen panel HDMI link is connected.\n'
  printf '# TYPE kitchen_hub_hdmi_connected gauge\n'
  printf 'kitchen_hub_hdmi_connected %s\n' "$hdmi"
  printf '# HELP kitchen_hub_kiosk_healthy Chromium and screen policy timer are active.\n'
  printf '# TYPE kitchen_hub_kiosk_healthy gauge\n'
  printf 'kitchen_hub_kiosk_healthy %s\n' "$kiosk"
} > "$temporary"
mv "$temporary" "$directory/kitchen_hub.prom"
