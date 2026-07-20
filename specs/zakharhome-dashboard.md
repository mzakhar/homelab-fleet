# Zakharhome Dashboard Spec

Status: deployed and Access-protected
Last updated: 2026-07-20

## Goal

Turn `zakharhome.org` from a blank site into a home-lab front door:

- Public root website for non-sensitive context and family-friendly links.
- Protected dashboard/control center for hosted apps, operational status, and later administrative actions.
- Source-controlled in `homelab-fleet`, deployed to `themachine` through the existing Flux/k3s model.
- Reflected in Obsidian Home Lab notes as implementation decisions land.

## Current Context

- Fleet repo: `homelab-fleet`
- Cluster: `themachine`, k3s, Flux CD
- Public routing: Cloudflare Tunnel named `themachine`
- Existing routed hosts:
  - `synth.zakharhome.org`
  - `books.zakharhome.org`
  - `cleanmail.zakharhome.org`
- Existing auth precedent: Clean Mail is behind Cloudflare Access.

## Product Shape

Use `zakharhome.org` as the public front door and keep the operational dashboard behind authentication.

URL model:

- `https://zakharhome.org/` - public landing/home page
- `https://dashboard.zakharhome.org/` - protected dashboard/control center

This uses two hostnames instead of path-based protection. Homepage is a Next.js app and is simpler to operate at `/`; a separate protected dashboard hostname avoids subpath/base-URL edge cases while leaving `zakharhome.org` free for a public landing page.

Public landing page content principles:

- Public-safe only: no private family details, internal work details, IP addresses, secrets, or operational endpoints.
- Tone: concise personal front door for software experiments, AI systems work, home-lab learning, and private family tools.
- Visual direction: dark image background, glass panels/cards, restrained neon accent lines.
- Implementation: static nginx site in `clusters/themachine/sites/zakharhome/`.

## Authn/Authz

Initial authn provider: Google account through Cloudflare Access.

Initial authz model:

- Admin: Mark
- Users: family members
- Default deny for protected dashboard routes
- Public landing page remains unauthenticated

Near-term Cloudflare Access policy:

- Application: `dashboard.zakharhome.org`
- IdP: Google
- Allow: Mark and explicit family Google accounts
- Admin authorization is not enforced inside Homepage in v1; admin-only controls wait for action-runner phase.

Security notes:

- Homepage should not be treated as an auth boundary.
- Sensitive widgets/API keys stay in Kubernetes Secrets or Cloudflare-protected paths, not committed YAML.
- Origin protection should prefer Cloudflare Access/tunnel token validation where possible.

## Implementation Target

Target Homepage first.

Reasons:

- Configured by YAML, fits this fleet repo.
- Static dashboard with service cards, bookmarks, and widgets.
- Kubernetes integration can show pod CPU/memory and discover annotated services later.
- Broad widget ecosystem for common home-lab services.

Homepage config files expected:

- `settings.yaml`
- `services.yaml`
- `bookmarks.yaml`
- `widgets.yaml`
- `kubernetes.yaml`

Deployment ownership:

- Keep Homepage manifests/config in `homelab-fleet`.
- Keep it under `clusters/themachine/platform/homepage/` rather than creating a separate app repo unless custom code becomes necessary.

## Phase Plan

### Phase 0 - Spec and Inventory

- Create this spec.
- Confirm final list of initial dashboard links.
- Decide exact public/protected routing shape.
- Update vault Home Lab notes once implementation starts.

### Phase 1 - Homepage MVP

- [x] Add Homepage namespace, config, deployment, service, and ingress manifests.
- [x] Add Flux registration via `clusters/themachine/kustomization.yaml`.
- [x] Push to GitHub and reconcile Flux on `themachine`.
- [x] Verify `homepage` Deployment ready in k3s.
- [x] Verify Traefik ingress returns `200 OK` locally for `dashboard.zakharhome.org`.
- [x] Configure root dashboard cards for:
  - Clean Mail
  - Synth
  - Books
  - k3s/themachine
  - Cloudflare Tunnel
  - Home Lab docs/bookmarks
- [x] Add non-secret status checks where useful.

### Phase 2 - Public Landing + Protected Dashboard

- [x] Add public landing surface for `zakharhome.org/`.
- Protect dashboard route with Cloudflare Access using Google IdP.
- [x] Update Cloudflare Tunnel bootstrap script to include `dashboard.zakharhome.org`.
- [x] Update Cloudflare Tunnel bootstrap script to include apex `zakharhome.org`.
- [x] Re-run Cloudflare tunnel bootstrap with `CLOUDFLARE_API_TOKEN` after adding apex `zakharhome.org`.
- [x] Verify public `https://zakharhome.org` returns the landing page through Cloudflare.
- [x] Verify public DNS resolves for `dashboard.zakharhome.org`.
- [x] Verify unauthenticated requests redirect to Cloudflare Access.
- Document required manual Cloudflare Access configuration.

### Phase 3 - Observability Widgets

- [x] Add Kubernetes resource visibility for the `themachine` k3s cluster.
- [x] Add dashboard inventory cards for `homeserver`, Plex, and observability roadmap placeholders.
- [x] Deploy central observability stack on `themachine`: Prometheus, Grafana, Tempo, OpenTelemetry Collector, and Uptime Kuma.
- [x] Add host health metrics for `themachine` and `homeserver` through node exporter and Prometheus.
- [x] Link Homepage observability cards to Grafana host metrics, Uptime Kuma, and Grafana Explore.
- [ ] Add service widgets for apps that expose safe internal health/status APIs.
- [x] Add service uptime monitors in Uptime Kuma for the hosted apps and media services.
- [x] Add richer Homepage widgets for Prometheus/Grafana/Uptime Kuma if they expose safe internal status APIs.
- [x] Add distinct `themachine` and `homeserver` host metric cards backed by Prometheus/node exporter.
- [x] Add moOde audio endpoints for living room, basement, and console.
- [x] Add moOde playback summary widgets backed by each device's `engine-mpd.php` endpoint.
- [x] Add GitHub repository section with public repo metrics through Homepage `customapi`.
- [x] Add private GitHub repo metrics using a Kubernetes Secret-backed token instead of committing a token in Homepage config.
- [x] Add Jellyfin media widget after API key was provided through normal service UI flow.
- [x] Add Plex media widget after Plex token is provided through normal service UI flow.
- [x] Add Flux/Fleet Sync widget showing repo revision, applied revision, sync state, and failure count.

Phase 3 note: Homepage can show Kubernetes metrics for the cluster it runs in, but `homeserver` is a separate machine. The canonical host metric path is now node exporter on each Linux box -> Prometheus on `themachine` -> Grafana dashboard. `homeserver` node exporter now runs as a persistent systemd service under user `mzakhar`.

### Phase 4 - Action Runner

- [x] Add a separate, explicitly protected admin API/service for actions.
- [x] Re-run Cloudflare tunnel bootstrap so `actions.zakharhome.org` routes through the tunnel.
- [x] Add Cloudflare Access application/policy for `actions.zakharhome.org`.
- Candidate actions:
  - [x] Flux reconcile selected apps
  - [x] Restart selected deployments
  - [x] View recent pod status/log snippets
  - Trigger maintenance scripts
- Requirements before any action support:
  - [x] Admin-only authorization via Cloudflare Access authenticated-user email header
  - [x] Auditable action log in process memory
  - [x] Allowlist of actions/targets only
  - [x] No arbitrary shell execution from the browser
  - [x] Clear confirmation for disruptive actions in the action UI

Homepage remains the UI/jump point; action runner owns privileged operations.

## Initial Dashboard Groups

### Hosted Apps

- Clean Mail - `https://cleanmail.zakharhome.org`
- Synth - `https://synth.zakharhome.org`
- Books - `https://books.zakharhome.org/books/`

### Infrastructure

- `themachine` k3s
- Pi-hole once restored
- Grafana host metrics - `http://192.168.1.3:30300/d/linux-hosts/linux-hosts`
- Prometheus - `http://192.168.1.3:30090`
- Uptime Kuma - `http://192.168.1.3:30081`
- OpenTelemetry Collector - OTLP gRPC `192.168.1.3:30317`, OTLP HTTP `http://192.168.1.3:30318`

### Media

- Jellyfin/Plex migration target
- moOde audio Pis

### Docs

- Home Lab vault index/reference
- Fleet repo README
- App operational notes

## Decisions

- 2026-07-19: Use `homelab-fleet` as source of truth for dashboard deployment/config.
- 2026-07-19: Use Homepage as first implementation target.
- 2026-07-19: Keep public landing option; protect dashboard/control center.
- 2026-07-19: Use Cloudflare Access with Google accounts for initial authn/authz.
- 2026-07-19: Plan for future admin actions, but do not put privileged command execution in v1.
- 2026-07-19: Host Homepage at `dashboard.zakharhome.org` instead of `/dashboard` to avoid path-prefix issues.
- 2026-07-19: Homepage deployed internally on `themachine` and verified through Traefik.
- 2026-07-19: Cloudflare tunnel/DNS updated and `dashboard.zakharhome.org` verified to redirect unauthenticated requests to Cloudflare Access.
- 2026-07-19: Added static public landing page manifests for `zakharhome.org`; page uses public-safe bio/home-lab framing and the same dark glass visual language.
- 2026-07-19: Apex `zakharhome.org` moved onto the Cloudflare Tunnel and verified with `HTTP/2 200`.
- 2026-07-19: Expanded Homepage dashboard inventory with `homeserver`, Plex, and observability placeholders; made dashboard cards more transparent.
- 2026-07-19: Chose `themachine` for the central observability stack because it has more memory/disk and already hosts the k3s/GitOps control plane; keep `homeserver` lightweight for media/NAS duties.
- 2026-07-19: Deployed Prometheus, Grafana, Tempo, OpenTelemetry Collector, and Uptime Kuma in the `observability` namespace through Flux.
- 2026-07-19: Installed node exporter on `themachine` through apt/systemd and installed node exporter on `homeserver` as a persistent systemd service under user `mzakhar`; Prometheus verified both scrape targets as up.
- 2026-07-19: Initialized Uptime Kuma with SQLite, created admin user `mark`, and added monitors for public sites, observability endpoints, node exporters, Jellyfin, and Plex; all initial checks returned up.
- 2026-07-19: Updated Homepage to show `themachine` and `homeserver` as separate Prometheus-backed host cards, added all moOde endpoints, and added a GitHub repo section with public repo metrics.
- 2026-07-19: Added `homepage-secrets` in-cluster with a GitHub token, wired private GitHub repo metric widgets through `${GITHUB_TOKEN}`, created Uptime Kuma status page `homelab`, and added the Homepage Uptime Kuma widget.
- 2026-07-19: Action runner deployment was held for explicit security approval before adding a persistent admin endpoint with restart/reconcile powers.
- 2026-07-19: After explicit approval, deployed `action-runner` namespace/service with allowlisted pod/log/restart/reconcile actions; local ingress verified with Cloudflare Access email header simulation.
- 2026-07-19: Added Jellyfin widget using `HOMEPAGE_VAR_JELLYFIN_KEY`; verified `Count` and `Sessions` widget endpoints return data.
- 2026-07-19: Added Plex widget using `HOMEPAGE_VAR_PLEX_TOKEN`; browser UI verification is still pending because direct pod-local Homepage API calls rejected manual requests with `400`.
- 2026-07-19: Re-ran Cloudflare Tunnel bootstrap after creating Access protection for `actions.zakharhome.org`; cloudflared loaded ingress version 7 and external request from `themachine` returned Cloudflare Access `302`.
- 2026-07-19: Renamed Homepage `Home` section to `Media`, moved Pi-hole into `Infrastructure`, and moved non-actionable Flux/Cloudflare cards out of `Infrastructure` into `Docs`.
- 2026-07-19: Added action-runner `/flux/status` read endpoint and Homepage `Fleet Sync` card using internal `customapi`; card shows cluster repo pickup/apply status instead of a non-actionable Flux link.
- 2026-07-19: Added action-runner `/flux/health` endpoint and wired Fleet Sync `siteMonitor` so Homepage can show native warning state when Flux is not synced or has failed objects.
- 2026-07-19: Fixed Homepage host metric cards by scaling Prometheus ratio queries to 0-100 values before `percent` formatting.
- 2026-07-20: Reorganized repo into `apps`, `platform`, and `sites`; moved Homepage, action-runner, observability, Cloudflare Tunnel, and public site under the new structure. Split Homepage config, action-runner Python, and public site HTML/nginx out of embedded ConfigMaps into source files generated by Kustomize.
- 2026-07-20: Updated moOde Homepage cards to use bare browser hostnames for links and direct LAN IPs for server-side `customapi` playback widgets because `themachine` does not resolve the bare Moode names.

## Open Questions

- Which family Google accounts should be allowed?
- Do we want a separate internal-only dashboard at `home.zakharhome.org` later?
- Should app repos add Homepage discovery annotations, or should `homelab-fleet` keep explicit service config?
