# Cloudflare Dashboard Service Routing Plan

Status: planned
Last updated: 2026-07-21

## Goal

Give authenticated users stable HTTPS access to home-lab web interfaces without
opening new inbound router ports. Keep browser dashboards on Cloudflare Tunnel
published hostnames, while keeping high-bandwidth media playback off Cloudflare's
CDN path.

This plan covers:

- Existing Home Assistant and action-runner routes.
- Grafana, Prometheus, and Uptime Kuma.
- Three moOde control interfaces.
- Jellyfin and Plex management/playback access.

Related specs:

- `specs/zakharhome-dashboard.md`
- `specs/observability-homepage-plan.md`

## Current Baseline

- Remotely managed Cloudflare Tunnel: `themachine`.
- `cloudflared` runs in k3s and sends all current published hostnames to
  in-cluster Traefik over
  `http://traefik.kube-system.svc.cluster.local:80`.
- `clusters/themachine/platform/cloudflared/setup-tunnel.sh` owns published
  hostname and DNS bootstrap.
- Already published:
  - `dashboard.zakharhome.org`
  - `homeassistant.zakharhome.org`
  - `actions.zakharhome.org`
- Home Assistant already has Service + Ingress resources and is already listed
  in tunnel bootstrap. No new route is required.
- Action runner already has Service + Ingress resources, a tunnel hostname, and
  a Cloudflare Access application. No new route is required.
- Observability UIs currently use LAN NodePorts:
  - Grafana: `192.168.1.3:30300`
  - Prometheus: `192.168.1.3:30090`
  - Uptime Kuma: `192.168.1.3:30081`
- Jellyfin and Plex run on `homeserver` at `192.168.1.2:8096` and
  `192.168.1.2:32400`.
- moOde targets:
  - Living room: `192.168.1.46`
  - Basement: `192.168.1.40`
  - Console: `192.168.1.28`

## Routing Decision

Use two Cloudflare Tunnel patterns.

### Pattern A: Published HTTPS hostname + Cloudflare Access

Use for browser-native, low-bandwidth control and observability UIs.

Request path:

`browser -> Cloudflare Access -> themachine tunnel -> Traefik -> Service -> origin`

Targets:

| Service | Public hostname | Access group | Decision |
| --- | --- | --- | --- |
| Homepage | `dashboard.zakharhome.org` | Family | Existing; keep |
| Home Assistant | `homeassistant.zakharhome.org` | Family | Existing; keep |
| Action runner | `actions.zakharhome.org` | Admin | Existing; keep |
| Grafana | `grafana.zakharhome.org` | Admin | Add first |
| Uptime Kuma | `uptime.zakharhome.org` | Admin | Add after Grafana |
| Prometheus | `prometheus.zakharhome.org` | Admin | Add only if raw query UI is needed remotely |
| Living-room moOde | `livingroom-audio.zakharhome.org` | Family | Pilot moOde route |
| Basement moOde | `basement-audio.zakharhome.org` | Family | Add after pilot |
| Console moOde | `console-audio.zakharhome.org` | Family | Add after pilot |

Cloudflare supports multiple published applications on one tunnel. Each
published hostname maps to an HTTP origin. Cloudflare Access self-hosted apps
are deny-by-default when an Allow policy is present. Create Access applications
before publishing new hostnames so no origin becomes briefly public.

### Pattern B: Private network route + Cloudflare One Client

Use for media services when remote browser administration is needed. Advertise
only `192.168.1.2/32` through the tunnel, require Cloudflare One Client, and
apply private-application policies for ports `8096` and `32400`.

Request path:

`enrolled device -> Cloudflare One Client -> private tunnel route -> homeserver`

Targets:

| Service | Address | Decision |
| --- | --- | --- |
| Jellyfin | `http://192.168.1.2:8096` | Private route for admin/browser use; no published Cloudflare hostname for playback |
| Plex | `http://192.168.1.2:32400/web` | Prefer Plex native remote access; private route only for server administration |

Do not publish Jellyfin or Plex video playback through a proxied Cloudflare
hostname on a self-serve plan. Current Cloudflare application-service terms
require designated paid services for video and other large files served through
the CDN. Cloudflare Access also relies on a browser authorization cookie, making
it a poor boundary for native TV/mobile media clients.

Plex already provides account-authenticated Remote Access and client discovery.
Keep that as playback path while Plex remains in service. Jellyfin supports a
normal HTTPS reverse proxy and WebSockets, but its remote playback path should
use either private-network access or a separate non-Cloudflare-CDN design.

## Origin Design

### In-cluster services

Add Traefik Ingress resources in
`clusters/themachine/platform/observability/` for Grafana, Uptime Kuma, and
optionally Prometheus. Point each Ingress directly at existing ClusterIP/NodePort
Services by named port. A NodePort Service remains addressable inside cluster;
no second Service is required.

Update application base URLs where needed:

- Grafana: set `GF_SERVER_ROOT_URL=https://grafana.zakharhome.org/`.
- Uptime Kuma: verify Socket.IO/WebSocket traffic and generated links use public
  HTTPS hostname.
- Prometheus: no base-path change needed when hosted at `/`.

Do not publish Tempo, OpenTelemetry Collector receivers, node exporter,
kube-state-metrics, or Alertmanager in first pass. Grafana is investigation UI;
raw telemetry/storage endpoints remain internal.

### LAN services behind Traefik

For each moOde target, add a selectorless Kubernetes Service plus EndpointSlice
using fixed LAN IP and port 80, then add matching Ingress. Keep these adapters in
a dedicated `clusters/themachine/platform/lan-dashboards/` kustomization.

Use IP-backed EndpointSlices because `themachine` does not reliably resolve
bare moOde hostnames. Do not use an unrestricted generic proxy. Each hostname
must map to one allowlisted endpoint.

Pilot living-room moOde first. Verify:

- HTML, JS, CSS, artwork, and API calls load through HTTPS.
- WebSocket/SSE or long-poll controls still work.
- Origin does not emit absolute `http://livingroommoode/` URLs.
- Playback, volume, queue, and reboot/shutdown UI behavior remain correct.
- Cloudflare caching is bypassed for dynamic/API responses.

Only add basement and console after pilot passes.

## Access And Security Policy

- Create Access application before each published tunnel hostname.
- Default deny. Explicit Google-account allowlists only.
- Admin-only: action runner, Grafana, Uptime Kuma admin UI, Prometheus.
- Family: Homepage, Home Assistant, moOde control UIs.
- Keep each sensitive hostname as its own Access application unless identical
  policy and session settings justify one multi-domain application.
- Use short admin sessions; family control UIs may use longer sessions.
- Keep Access binding-cookie features disabled where WebSockets or non-browser
  compatibility tests fail.
- Do not treat origin application auth as replaced by Access. Keep Grafana,
  Uptime Kuma, Home Assistant, Jellyfin, and Plex auth enabled.
- Validate Access JWTs at origin or enable tunnel-side Protect with Access where
  supported. Header presence alone is not proof of origin authenticity.
- Never expose OTLP, Prometheus write endpoints, media API keys, Plex tokens, or
  Jellyfin API keys through public unauthenticated paths.
- Add Cloudflare cache rules to bypass cache for all authenticated dashboard
  hostnames.

## Implementation Phases

### Phase 0: Inventory And Policy

- [ ] Confirm Cloudflare plan and current service-specific terms before media
  routing changes.
- [ ] Confirm Google accounts in Admin and Family groups.
- [ ] Create reusable Access policies for both groups.
- [ ] Record current tunnel config version and exported Access application list.
- [ ] Decide whether remote raw Prometheus UI adds enough value beyond Grafana.

### Phase 1: Observability Pilot

- [ ] Create Access app for `grafana.zakharhome.org`.
- [ ] Add Grafana Ingress.
- [ ] Add hostname to tunnel/DNS bootstrap.
- [ ] Change Grafana root URL to public HTTPS hostname.
- [ ] Update Homepage Grafana links.
- [ ] Validate locally through Traefik, externally unauthenticated, then
  externally authenticated.
- [ ] Verify dashboard navigation, datasource queries, Explore, and Tempo links.

### Phase 2: Remaining Observability UIs

- [ ] Create Access app and Ingress for `uptime.zakharhome.org`.
- [ ] Verify Uptime Kuma login, status pages, Socket.IO/WebSockets, and monitor
  editing.
- [ ] Add `prometheus.zakharhome.org` only if approved in Phase 0.
- [ ] Update Homepage links from LAN NodePorts to protected HTTPS hostnames.
- [ ] Keep internal widget URLs on Kubernetes service DNS; only browser `href`
  values change.

### Phase 3: moOde Pilot And Rollout

- [ ] Add `lan-dashboards` namespace/kustomization.
- [ ] Add allowlisted Service + EndpointSlice + Ingress for living-room moOde.
- [ ] Create Family Access app before publishing hostname.
- [ ] Add tunnel/DNS hostname and run compatibility checks.
- [ ] Add basement and console adapters after pilot passes.
- [ ] Replace Homepage bare-host links with protected HTTPS hostnames.
- [ ] Keep action-runner status proxy allowlist unchanged unless endpoint data
  source changes.

### Phase 4: Media Administration

- [ ] Confirm Plex native Remote Access health and use it for playback.
- [ ] Decide whether remote Jellyfin administration is required.
- [ ] If required, advertise `192.168.1.2/32` as private tunnel route.
- [ ] Create least-privilege private Access rules for TCP ports 8096 and 32400.
- [ ] Enroll only admin devices in Cloudflare One Client.
- [ ] Test split DNS/LAN behavior and confirm local clients stay local.
- [ ] Do not add `jellyfin.zakharhome.org` or `plex.zakharhome.org` to published
  hostname bootstrap without a separate terms, client-compatibility, and
  bandwidth decision.

### Phase 5: Hardening And Operations

- [ ] Add Uptime Kuma checks for new public hostnames that expect Access redirect
  or authenticated service-token response.
- [ ] Alert on tunnel replica loss and route failure.
- [ ] Run two `cloudflared` replicas after checking k3s capacity and rollout
  behavior.
- [ ] Document Access app IDs, policy intent, private routes, and rollback steps
  without storing secrets.
- [ ] Update Home Lab vault notes with final routes and client requirements.

## Validation Checklist

For every published hostname:

1. `kubectl kustomize clusters/themachine` renders successfully.
2. Local Traefik request with correct `Host` header reaches intended origin.
3. Unauthenticated public request redirects to Cloudflare Access or returns
   expected Access denial.
4. Authorized browser request returns intended UI.
5. Unauthorized Google account remains denied.
6. Browser dev tools show no mixed content, failed WebSockets, redirect loops,
   or leaked internal IP URLs.
7. Direct LAN access still works for recovery.
8. Rollback means removing hostname from tunnel bootstrap and reverting Ingress;
   no origin data migration is involved.

For private media routes:

1. Non-enrolled device cannot reach private route.
2. Enrolled admin device can reach only approved host and ports.
3. Plex/Jellyfin native playback behavior is tested separately from browser UI.
4. LAN playback remains direct and does not hairpin through Cloudflare.

## Source References

- Cloudflare Tunnel routing and multiple published applications:
  https://developers.cloudflare.com/tunnel/routing/
- Cloudflare Access self-hosted applications and token validation:
  https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/
- Cloudflare Access authorization cookies:
  https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/
- Cloudflare private self-hosted applications and device-client routing:
  https://developers.cloudflare.com/cloudflare-one/access-controls/applications/choose-application-type/
- Cloudflare application-service terms:
  https://www.cloudflare.com/service-specific-terms-application-services/
- Jellyfin reverse proxy requirements:
  https://jellyfin.org/docs/general/post-install/networking/reverse-proxy/
- Plex Remote Access:
  https://support.plex.tv/articles/200289506-remote-access/

## Decisions

- 2026-07-21: Reuse `themachine` tunnel and Traefik for browser dashboard
  hostnames.
- 2026-07-21: Treat Home Assistant and action runner as completed tunnel routes,
  not new work.
- 2026-07-21: Publish Grafana first; make Prometheus optional and keep Tempo,
  OTel, exporters, and Alertmanager internal.
- 2026-07-21: Pilot one moOde UI through an explicit IP-backed Kubernetes
  adapter before adding all three.
- 2026-07-21: Keep Plex/Jellyfin playback off published Cloudflare hostnames.
  Prefer Plex native Remote Access and Cloudflare private routing for admin-only
  access.
