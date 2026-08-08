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

---

## Closing the TLS gap (2026-08-08) — cert-manager DNS-01

The second option above is now built, driven by `hub.zakharhome.org` rather than by
Home Assistant. **Home Assistant tolerates the plain-HTTP tailnet path; Family Hub
cannot.** Its `PUBLIC_ORIGIN` is `https://hub.zakharhome.org`, which makes the session
cookie `Secure` — a browser on `http://` never stores it — and its OAuth `redirect_uri`
sends the browser to `https://` no matter which way it arrived. Adding an `address=/…/`
line for `hub` without a certificate produces a wall screen that cannot log in.

So the rule for every future service on the tailnet path: **check whether the app pins
an https origin before adding its dnsmasq line.**

Manifests live in `clusters/themachine/platform/cert-manager/`:

| File | What |
|---|---|
| `helmrepository.yaml` | jetstack charts, `flux-system` namespace |
| `helmrelease.yaml` | cert-manager v1.21.1, CRDs installed by the chart |
| `clusterissuer.yaml` | `letsencrypt-prod`, ACME DNS-01 against Cloudflare |
| `cloudflare-api-token.template.yaml` | reference only — filled and applied by hand |

**DNS-01, not HTTP-01.** An HTTP-01 challenge has to reach Traefik from the public
internet, and every `zakharhome.org` hostname sits behind Cloudflare Access — the
challenge path would need its own bypass policy, which is exactly the construct this
spec exists to retire. DNS-01 also issues for hostnames that are not publicly reachable
at all, which is the point of the tailnet path.

**This is the fleet's first HelmRelease**; every other app here is plain manifests.
cert-manager ships as a chart plus a CRD set that must be installed and upgraded
together, and vendoring its ~5 MB static manifest into git to avoid one chart is the
worse trade.

The token is a zone-scoped Cloudflare API token (`Zone/DNS/Edit` + `Zone/Zone/Read` on
`zakharhome.org`), **not** the Global API Key — the Global Key would authenticate
deleting the tunnel and the Access policies too.

The certificate itself is requested from the app repo, not from here: the ingress in
`mzakhar/family-hub` at `deploy/k8s/app.yaml` carries the
`cert-manager.io/cluster-issuer` annotation and a `tls:` block, and cert-manager's
ingress-shim turns that into a Certificate. The `:80` router is untouched, so the
Cloudflare Tunnel keeps using it exactly as before.
