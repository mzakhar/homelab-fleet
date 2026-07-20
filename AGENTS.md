# AGENTS.md

## Purpose

`homelab-fleet` owns GitOps configuration for the home lab. Treat this repo as
the source of truth for the `themachine` k3s cluster and shared
`zakharhome.org` surfaces.

## Host And Access Notes

- Cluster host: `themachine`.
- SSH user for homelab boxes, Raspberry Pis, and moOde devices: `mzakhar`.
- Do not use that username assumption for this Windows PC.
- Prefer `E:\Projects\` for local project work.
- Home Lab vault reference: `E:\Obsidian\Hivemind`. Keep it up to date when
  host roles, deployment patterns, routes, or operational decisions change.

## Repo Layout

- `clusters/themachine/kustomization.yaml` is the root reconciled by Flux.
- `clusters/themachine/apps/` registers app repos with Flux.
- `clusters/themachine/platform/` owns shared in-cluster services:
  Cloudflare Tunnel, Homepage, observability, action-runner, Home Assistant.
- `clusters/themachine/sites/` owns fleet-managed sites, including the public
  `zakharhome.org` landing page.
- `scripts/` holds bootstrap helpers not directly reconciled by Flux.
- `specs/` holds plans, specs, and implementation decision logs.

## Deployment Patterns

- Flux on `themachine` deploys from `origin/main`.
- App repos usually own their Kubernetes manifests under `deploy/k8s` or
  `k8s/base`; this repo registers them.
- Platform workloads and fleet-owned sites are declared directly here.
- Split large ConfigMaps into source files and wire them with Kustomize
  `configMapGenerator`.
- Validate cluster manifests with `kubectl kustomize clusters/themachine`
  before pushing when YAML changes.
- For immediate rollout or verification, use `ssh mzakhar@themachine`.

## Zakharhome Targets

- Public landing site: `https://zakharhome.org/`.
- Landing site source: `clusters/themachine/sites/zakharhome/`.
- Protected Homepage dashboard: `https://dashboard.zakharhome.org/`.
- Homepage config: `clusters/themachine/platform/homepage/config/`.
- Admin action runner: `https://actions.zakharhome.org/`.
- Tunnel/DNS bootstrap helper:
  `clusters/themachine/platform/cloudflared/setup-tunnel.sh`.

## Secrets And Safety

- Never commit secrets, tokens, API keys, tunnel credentials, or private account
  lists.
- Current secret-backed integrations include Homepage GitHub, Jellyfin, Plex,
  and Cloudflare Tunnel credentials.
- Keep protected routes behind Cloudflare Access; Homepage is not an auth
  boundary by itself.
- Action-runner must stay allowlisted. Do not add arbitrary shell execution from
  the browser.

## Specs And Documentation

- Update `specs/zakharhome-dashboard.md` for dashboard, landing site, Homepage,
  action-runner, and routing decisions.
- Update `specs/observability-homepage-plan.md` for telemetry, Grafana,
  Prometheus, Tempo, OTel, Uptime Kuma, and related Homepage status widgets.
- Also update the Home Lab notes in `E:\Obsidian\Hivemind` when changes matter
  operationally outside this repo.
