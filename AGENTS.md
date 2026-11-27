# AGENTS.md

Single source of agent instructions for this repo (`CLAUDE.md` only imports this file).

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

## Change Flow

- Flux on `themachine` deploys from `origin/main`, so every change lands through a PR: branch
  `mzakhar/<short-description>` from an up-to-date `main`, commit, push, open a PR, merge it.
  Never push directly to `main`.
- Stage explicit paths; the checkout can hold unrelated untracked files.
- Validate cluster manifests with `kubectl kustomize clusters/themachine`
  before pushing when YAML changes (skip for docs-only changes).
- Flux reconciles within about 10 minutes of the merge. Verify read-only with
  `ssh mzakhar@themachine 'kubectl get/describe/logs ...'`; anything that writes cluster
  state (Secret edits, pod deletes, manual applies) is a separately approved step.

### Clean Mail image pins

`clusters/themachine/apps/clean-mail/` pins `clean-mail-backend` and `clean-mail-frontend` by
digest. Deploy = after the app repo's merged `main` CI run succeeds, on a fleet branch run
`scripts/pin-clean-mail-image.ps1 -Service backend|frontend|all` (refuses to run on `main`;
resolves the digest on `themachine`), then commit, PR, merge. App repos: `mzakhar/CleanMail-backend`,
`mzakhar/CleanMail-web-frontend`.

## Deployment Patterns

- App repos usually own their Kubernetes manifests under `deploy/k8s` or
  `k8s/base`; this repo registers them.
- Platform workloads and fleet-owned sites are declared directly here.
- Split large ConfigMaps into source files and wire them with Kustomize
  `configMapGenerator`.

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
- For a one-key live Secret update, use a merge patch on `data`; never pipe
  `kubectl create secret generic ... --dry-run=client -o yaml` into
  `kubectl apply`, because it can remove every existing key. `envFrom` values
  load at Pod creation, so restart only after patching and keep a healthy old
  Pod until its replacement is Ready.
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
