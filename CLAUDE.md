# CLAUDE.md

## Repo Purpose

This repo is the GitOps source of truth for the home lab fleet. Flux on
`themachine` reconciles `clusters/themachine/` into the k3s cluster.

## Environment

- Primary project path: `E:\Projects\homelab-fleet`.
- Obsidian vault: `E:\Obsidian\Hivemind`.
- Home lab reference notes live in the vault and must stay current when
  deployment patterns, host roles, routes, secrets handling, or operational
  decisions change.
- Use `mzakhar` as the SSH username for basically every homelab box, Raspberry
  Pi, and moOde device.
- Exception: this Windows PC does not use that homelab username convention.

## Deployment Model

- Cluster target: `themachine`, k3s, Flux CD.
- Root kustomization: `clusters/themachine/kustomization.yaml`.
- App registrations: `clusters/themachine/apps/`.
- Shared platform workloads: `clusters/themachine/platform/`.
- Fleet-owned sites: `clusters/themachine/sites/`.
- App manifests usually live in their app repos under `deploy/k8s` or
  `k8s/base`; this repo registers those repos with Flux.
- Platform services owned here include Cloudflare Tunnel, Homepage,
  observability, action-runner, and Home Assistant.

## Zakharhome Surfaces

- Public landing site: `https://zakharhome.org/`.
- Landing site manifests/source: `clusters/themachine/sites/zakharhome/`.
- Protected dashboard: `https://dashboard.zakharhome.org/`.
- Dashboard implementation: Homepage under
  `clusters/themachine/platform/homepage/`.
- Admin actions: `https://actions.zakharhome.org/`, implemented by
  `clusters/themachine/platform/action-runner/`.
- Cloudflare Tunnel bootstrap/config helper:
  `clusters/themachine/platform/cloudflared/setup-tunnel.sh`.

## Operational Rules

- Keep secrets out of git. Apply secrets manually on `themachine` or through a
  proper secret-management flow.
- Large ConfigMaps should be split into editable source files and generated with
  Kustomize `configMapGenerator`.
- After changes, run `kubectl kustomize clusters/themachine` before pushing
  unless the change is docs-only.
- Push GitOps changes to `origin/main` so Flux can reconcile them.
- If immediate deployment is needed, SSH to `mzakhar@themachine` and apply or
  reconcile there.

## Specs And Notes

- Use `specs/` for implementation plans and decision logs.
- Primary dashboard/control-center spec:
  `specs/zakharhome-dashboard.md`.
- Observability plan:
  `specs/observability-homepage-plan.md`.
- After each completed piece of work, update the relevant spec and the Home Lab
  vault reference when the operational state changes.
