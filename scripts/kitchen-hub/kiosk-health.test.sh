#!/bin/sh
# Checks the self-heal escalation ladder. Run: sh kiosk-health.test.sh
set -eu

script="$(dirname "$0")/kiosk-health.sh"
failures=0

# expect <want> <touch> <net> <kiosk> <reboot_ok> <uptime>
expect() {
  want=$1
  shift
  got=$(sh "$script" --decide "$@")
  if [ "$got" = "$want" ]; then
    printf 'ok    %-16s <- %s\n' "$got" "$*"
  else
    printf 'FAIL  want %-14s got %-14s <- %s\n' "$want" "$got" "$*"
    failures=$(( failures + 1 ))
  fi
}

#      want            touch net kiosk reboot_ok uptime
expect none            0     0   0     1         9000   # everything healthy
expect none            9     9   9     1         120    # still settling after boot
expect wifi_reconnect  0     3   0     1         9000   # 3 min of no gateway
expect none            0     2   0     1         9000   # 2 min is not yet enough
expect reboot_network  0     10  0     1         9000   # reconnect did not take
expect wifi_reconnect  0     10  0     0         9000   # ... but cooldown holds the reboot
expect reboot_touch    5     0   0     1         9000   # yesterday's USB fault
expect none            5     0   0     0         9000   # cooldown holds it, alert covers the gap
expect none            4     0   0     1         9000   # 4 min is not yet enough
expect kiosk_restart   0     0   2     1         9000   # chromium gone
expect reboot_touch    5     10  2     1         9000   # touch wins the ladder

if [ "$failures" -eq 0 ]; then
  echo "all checks passed"
else
  echo "$failures check(s) failed"
  exit 1
fi
