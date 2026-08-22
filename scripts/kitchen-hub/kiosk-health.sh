#!/bin/sh
set -eu

# The escalation ladder, as a function of how many consecutive checks each
# probe has failed. Pure: no state, no devices, no side effects, so
# `kiosk-health.sh --decide <touch> <net> <kiosk> <reboot_ok> <uptime> <cycle_ok>`
# is runnable anywhere. See kiosk-health.test.sh.
decide() {
  _touch=$1 _net=$2 _kiosk=$3 _reboot_ok=$4 _uptime=$5 _cycle_ok=$6

  # Let the box settle after boot before judging anything.
  if [ "$_uptime" -lt 300 ]; then echo none; return; fi

  if [ "$_touch" -ge 5 ] && [ "$_reboot_ok" = 1 ]; then
    echo reboot_touch
  elif [ "$_touch" -ge 3 ] && [ "$_cycle_ok" = 1 ]; then
    # Cutting port power costs ~3 s where a reboot costs ~40 s, so it sits
    # below reboot_touch on streak and stays reachable above it: a drop that
    # lands while the reboot cooldown is holding still gets retried every
    # 15 min rather than waiting the cooldown out.
    #
    # This replaced usb_reset (an xhci controller rebind) on 2026-08-20 after
    # that rung finished 0-for-80 against the real fault. A rebind re-inits the
    # host controller and the panel never re-presents; this commands the root
    # hub port itself off, which is the signal a physical replug sends and the
    # only thing short of a reboot that has ever recovered this panel.
    echo usb_power_cycle
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

touch_node=/dev/input/by-id/usb-ILITEK_ILITEK-TP-event-if00
touchscreen=0
test -e "$touch_node" && touchscreen=1

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

# Rebooting is the last rung, and on this panel it is the only rung that has
# ever recovered a dropped digitizer — 61 controller rebinds have produced zero
# recoveries, while every single recovery in the series is a reboot.
#
# The cooldown exists to stop a persistent fault becoming a boot loop, and it
# was 6 h while the fault fired ~4.3x/day. That tuning inverted: with the fault
# down to ~2/day after the 2026-08-18 PSU and cable swaps, the cooldown became
# the dominant cost rather than the protection. A drop at 15:01Z on 2026-08-18
# left the panel dead until 18:27Z, and roughly 3h20m of that 3h26m was purely
# this constant holding back the only rung that works.
#
# One hour, by explicit choice: a reboot costs ~40 s of a screen nobody is
# looking at, and hours of dead touch costs the wall its whole purpose. Worst
# case is 24 reboots/day, which KitchenHubSelfHealThrashing is retuned to catch
# (>= 8 in 24 h) — that alert, not this constant, is what notices a fault that
# is not clearing.
reboot_cooldown=3600
usb_cycle_cooldown=900
now=$(date +%s)
uptime_s=$(awk '{print int($1)}' /proc/uptime)
if [ $(( now - $(read_num last-reboot) )) -ge "$reboot_cooldown" ]; then
  reboot_ok=1
else
  reboot_ok=0
fi
if [ $(( now - $(read_num last-usb-cycle) )) -ge "$usb_cycle_cooldown" ]; then
  usb_cycle_ok=1
else
  usb_cycle_ok=0
fi

# Which xhci instance owns the panel, learned while the digitizer is present:
# by the time a reset is wanted the device is gone and its sysfs path with it.
# Re-derived on every healthy check, so moving the cable to the other USB port
# corrects this by itself rather than silently resetting the wrong controller.
if [ "$touchscreen" = 1 ]; then
  found=$(udevadm info -q path -n "$touch_node" 2>/dev/null |
    sed -n 's|.*/\(xhci-hcd\.[0-9]\)/.*|\1|p')
  [ -n "$found" ] && printf '%s\n' "$found" > "$state/controller"
fi
controller=$(cat "$state/controller" 2>/dev/null || echo xhci-hcd.1)

# uhubctl addresses the root hub by bus and the panel's hub by the port it sits
# on: ".../usb3/3-2/..." is bus 3, port 2. Learned and cached for the same
# reason as the controller above — the path is gone when it is wanted.
if [ "$touchscreen" = 1 ]; then
  hp=$(udevadm info -q path -n "$touch_node" 2>/dev/null | awk -v RS=/ '
    /^usb[0-9]+$/ { bus = substr($0, 4) }
    bus != "" && /^[0-9]+-[0-9]+$/ { split($0, a, "-"); print bus, a[2]; exit }')
  [ -n "$hp" ] && printf '%s\n' "$hp" > "$state/hubport"
fi
hubport=$(cat "$state/hubport" 2>/dev/null || echo "3 2")

action=$(decide "$touch_down" "$net_down" "$kiosk_down" "$reboot_ok" "$uptime_s" "$usb_cycle_ok")

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
  # usb_reset stays in this list although nothing writes it any more: dropping
  # it would make the series go stale and break the history that proves the
  # rung was retired for cause.
  for name in wifi_reconnect kiosk_restart usb_reset usb_power_cycle reboot_touch reboot_network; do
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
  usb_power_cycle)
    # uhubctl commands the root hub port off, waits, and powers it back on.
    # That is what a physical replug does, and a replug is one of only two
    # things ever observed to recover this panel — the other being a reboot.
    #
    # DOES NOT RECOVER THE REAL FAULT FROM THIS HOST. Shipped 2026-08-20 as an
    # explicit bet with both outcomes named in advance; 2026-08-22 settled it
    # against, 17 cycles and zero recoveries across 12 outages that every one
    # of them ended in a reboot.
    #
    # So Pi 5 does not actually drop VBUS on its root hub ports despite the
    # root hub advertising ppps. Two independent software paths now say the
    # same thing -- the sysfs port/disable test in Machines.md 2026-08-14 and
    # this one through uhubctl's USB_PORT_FEAT_POWER control transfer -- and
    # both are no-ops electrically. That is worth knowing rather than guessing:
    # it is what turns an external uhubctl-capable powered hub from an
    # assumption into a requirement.
    #
    # The rung stays, and not only for the record. It is the thing that will
    # prove such a hub works the day one is fitted: cache hubport to the new
    # hub's location and this code path is already the test.
    #
    # Note the shape of the evidence that led here, because it repeats. The
    # 2026-08-20 verification was a healthy-state cycle -- port "0000 off",
    # both devices gone from lsusb, both back on power on -- which is exactly
    # the clean-removal evidence that made usb_reset look good before it went
    # 0-for-80. A clean removal is not the wedged state, and only the real
    # fault can tell you anything.
    #
    # Failure is safe either way: the touch streak keeps climbing to 5 and
    # reboot_touch takes it, which is where it was going anyway.
    logger -t kiosk-health "self-heal: power-cycling hub ${hubport} after ${touch_down} failed checks"
    write_num last-usb-cycle "$now"
    # shellcheck disable=SC2086 -- hubport is deliberately two words: hub, port
    /usr/sbin/uhubctl -a cycle -l ${hubport%% *} -p ${hubport##* } >/dev/null 2>&1 || true
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
