#!/bin/sh
set -eu

# The escalation ladder, as a function of how many consecutive checks each
# probe has failed. Pure: no state, no devices, no side effects, so
# `kiosk-health.sh --decide <touch> <net> <kiosk> <reboot_ok> <uptime>` is
# runnable anywhere. See kiosk-health.test.sh.
decide() {
  _touch=$1 _net=$2 _kiosk=$3 _reboot_ok=$4 _uptime=$5

  # Let the box settle after boot before judging anything.
  if [ "$_uptime" -lt 300 ]; then echo none; return; fi

  if [ "$_touch" -ge 5 ] && [ "$_reboot_ok" = 1 ]; then
    echo reboot_touch
  elif [ "$_net" -ge 10 ] && [ "$_reboot_ok" = 1 ]; then
    echo reboot_network
  elif [ "$_net" -ge 3 ] && [ $(( (_net - 3) % 15 )) -eq 0 ]; then
    # Backs off to every 15th check after the first try. A real AP outage on
    # 2026-08-10 ran 107 minutes with the reboot held by cooldown, and an
    # every-minute rung tore down 105 in-progress association attempts to no
    # effect. Retry, do not hammer.
    echo wifi_reconnect
  elif [ "$_kiosk" -ge 2 ]; then
    echo kiosk_restart
  else
    echo none
  fi
}

if [ "${1:-}" = --decide ]; then
  shift
  decide "$@"
  exit 0
fi

directory=/var/lib/prometheus/node-exporter
state=/var/lib/kitchen-hub
temporary="$directory/kitchen_hub.prom.$$"
trap 'rm -f "$temporary"' EXIT

mkdir -p "$state"

# Streaks and counters persist across runs: this is a oneshot fired once a
# minute, so "3 minutes down" is "the third consecutive run that saw it down".
read_num() { cat "$state/$1" 2>/dev/null || echo 0; }
write_num() { printf '%s\n' "$2" > "$state/$1"; }

# Returns the new consecutive-failure count for a probe; 0 while it is healthy.
streak() {
  if [ "$2" = 1 ]; then
    write_num "streak.$1" 0
  else
    write_num "streak.$1" "$(( $(read_num "streak.$1") + 1 ))"
  fi
  read_num "streak.$1"
}

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

# The gateway, not a name: DNS here is the tailnet resolver, which is itself
# downstream of the link this probe is trying to judge.
network=0
gateway=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
if [ -n "$gateway" ] && ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
  network=1
fi

touch_down=$(streak touchscreen "$touchscreen")
net_down=$(streak network "$network")
kiosk_down=$(streak kiosk "$kiosk")

# Rebooting is the last rung, and for a vanished USB digitizer it is the only
# one: the panel's hub runs off the panel's own supply, so nothing on this host
# can power-cycle it. The cooldown keeps a persistent fault from becoming a loop.
reboot_cooldown=21600
now=$(date +%s)
uptime_s=$(awk '{print int($1)}' /proc/uptime)
if [ $(( now - $(read_num last-reboot) )) -ge "$reboot_cooldown" ]; then
  reboot_ok=1
else
  reboot_ok=0
fi

action=$(decide "$touch_down" "$net_down" "$kiosk_down" "$reboot_ok" "$uptime_s")

if [ "$action" != none ]; then
  write_num "count.$action" "$(( $(read_num "count.$action") + 1 ))"
fi

# Written before the action runs, so a reboot still leaves its own count behind.
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
  printf '# HELP kitchen_hub_network_up Default gateway answers ICMP.\n'
  printf '# TYPE kitchen_hub_network_up gauge\n'
  printf 'kitchen_hub_network_up %s\n' "$network"
  printf '# HELP kitchen_hub_selfheal_total Corrective actions taken by this script.\n'
  printf '# TYPE kitchen_hub_selfheal_total counter\n'
  for name in wifi_reconnect kiosk_restart reboot_touch reboot_network; do
    printf 'kitchen_hub_selfheal_total{action="%s"} %s\n' "$name" "$(read_num "count.$name")"
  done
} > "$temporary"
mv "$temporary" "$directory/kitchen_hub.prom"

case "$action" in
  none) ;;
  wifi_reconnect)
    logger -t kiosk-health "self-heal: reconnecting wlan0 after ${net_down} failed checks"
    nmcli device reconnect wlan0 >/dev/null 2>&1 || true
    ;;
  kiosk_restart)
    # lwrespawn is Chromium's parent and restarts it, so killing it is the reload.
    logger -t kiosk-health "self-heal: restarting chromium after ${kiosk_down} failed checks"
    pkill -x chromium >/dev/null 2>&1 || true
    ;;
  reboot_touch|reboot_network)
    logger -t kiosk-health "self-heal: rebooting ($action)"
    write_num last-reboot "$now"
    write_num streak.touchscreen 0
    write_num streak.network 0
    write_num streak.kiosk 0
    systemctl reboot
    ;;
esac
