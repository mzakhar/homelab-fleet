#!/bin/sh
# Checks the self-heal escalation ladder. Run: sh kiosk-health.test.sh
set -eu

script="$(dirname "$0")/kiosk-health.sh"
failures=0

# expect <want> <touch> <net> <kiosk> <reboot_ok> <uptime> <cycle_ok>
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

#      want            touch net kiosk reboot_ok uptime cycle_ok
expect none             0     0   0     1         9000   1   # everything healthy
expect none             9     9   9     1         120    1   # still settling after boot
expect wifi_reconnect   0     3   0     1         9000   1   # 3 min of no gateway
expect none             0     2   0     1         9000   1   # 2 min is not yet enough
expect reboot_network   0     10  0     1         9000   1   # reconnect did not take
expect none             0     10  0     0         9000   1   # cooldown holds the reboot, backoff holds the retry
expect none             0     4   0     1         9000   1   # backoff: no retry between attempts
expect none             0     17  0     0         9000   1   # ... still backing off, cooldown still holding
expect wifi_reconnect   0     18  0     0         9000   1   # ... 15 checks on, retry while cooldown holds
expect usb_power_cycle  3     0   0     1         9000   1   # 3 min of no digitizer: cut hub port power
expect none             2     0   0     1         9000   1   # 2 min is not yet enough
expect none             3     0   0     1         9000   0   # cycle cooldown holds the power cut
expect reboot_touch     5     0   0     1         9000   1   # power cycle did not take; reboot outranks it
expect usb_power_cycle  5     0   0     0         9000   1   # reboot on cooldown: keep retrying the cheap rung
expect none             5     0   0     0         9000   0   # both cooldowns holding, alert covers the gap
expect kiosk_restart    0     0   2     1         9000   1   # chromium gone
expect reboot_touch     5     10  2     1         9000   1   # touch wins the ladder
expect usb_power_cycle  3     10  2     1         9000   1   # ... and the cheap touch rung outranks a net reboot

if [ "$failures" -eq 0 ]; then
  echo "all checks passed"
else
  echo "$failures check(s) failed"
  exit 1
fi
