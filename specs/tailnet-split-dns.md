# Tailnet Split DNS For Home Assistant

Status: in place as of 2026-08-06.

## Why

`homeassistant.zakharhome.org` was reachable publicly with no Cloudflare Access
application in front of it — only Home Assistant's own login. Adding Access
would have gated it, but the HA companion app authenticates with long-lived
tokens and cannot complete the browser SSO redirect, so every phone in the house
would have lost HA.

The previous workaround for that class of problem was the `Home LAN bypass`
Access policy: a Bypass rule pinned to a single public IP (`24.183.32.222/32`).
Two failure modes killed it:

- The ISP rotated the WAN address to `96.42.117.150`, so the rule stopped
  matching home traffic and silently stopped doing its job.
- Bypass means Access does not protect the path at all. Once the old address is
  reassigned to another subscriber, that stranger matches the rule.

Tailnet membership replaces a rotating IP with a device key, which is the
property the bypass was reaching for and never had.

## Shape

Cloudflare guards the browser path. Tailscale carries the app path. No policy
depends on the WAN address.

| Path | Route |
|------|-------|
| Off-tailnet browser | Cloudflare tunnel, `Family oidc access` Access policy |
| On-tailnet device | WireGuard direct to Traefik, no Cloudflare, no Access |

## Host Config On themachine

Neither piece lives in this repo — both are host-level and survive outside Flux.

Tailscale joined with DNS explicitly disabled:

```
sudo tailscale up --accept-dns=false --hostname=themachine
```

`--accept-dns=false` is load-bearing. Without it Tailscale rewrites
`/etc/resolv.conf`, and k3s CoreDNS forwards upstream queries to that file, so
every in-cluster lookup would start routing through MagicDNS. cloudflared
already fails its edge-discovery SRV lookup when CoreDNS wobbles.

dnsmasq answers only on the tailnet address, `/etc/dnsmasq.d/tailnet-split.conf`:

```
listen-address=100.67.221.109
bind-interfaces
no-resolv
server=1.1.1.1
server=1.0.0.1
address=/homeassistant.zakharhome.org/100.67.221.109
```

`bind-interfaces` plus `listen-address` keeps it off the LAN and off loopback,
so it does not collide with systemd-resolved on `127.0.0.53`. Only the one
hostname is overridden; every other `zakharhome.org` name falls through to
upstream and keeps resolving to Cloudflare.

## Tailscale Admin

DNS → Nameservers → `100.67.221.109`, **Restrict to domain** = `zakharhome.org`
(Split DNS). Tailnet: `tail9185fb.ts.net`.

## Verification

From a tailnet node (`home-pc`):

```
homeassistant.zakharhome.org -> 100.67.221.109   (themachine tailnet IP)
dashboard.zakharhome.org     -> 104.21.54.79     (Cloudflare, unchanged)
curl http://homeassistant.zakharhome.org/  -> 200
```

From themachine, confirming the resolver is not exposed on the LAN:

```
dig homeassistant.zakharhome.org @192.168.1.3  -> connection refused
```

## Known Gap

HTTPS does not work on the tailnet path. Cloudflare was terminating TLS, and
Traefik holds no certificate for this hostname, so tailnet clients get plain
HTTP. WireGuard still encrypts the transport, but the app sees `http://`.

Two ways to close it when it matters:

- Set HA's internal URL to `http://homeassistant.zakharhome.org` and treat
  WireGuard as the encryption layer.
- Issue a real certificate via cert-manager DNS-01 with a Cloudflare token, so
  the same hostname serves HTTPS on both the tunnel and the tailnet path.

## Follow-ups

- `Home LAN bypass` still exists as a reusable policy and is now attached to
  nothing. Delete it, or it will get reused and reintroduce the stale-IP hole.
- Adding another service to the tailnet path is one more `address=/…/` line plus
  a dnsmasq restart. The Tailscale split-DNS entry already covers the whole zone.
