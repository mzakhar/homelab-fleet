# homelab-fleet

Flux CD cluster configuration for the home lab (`themachine`, k3s). Moved out of `mzakhar/vs-book-app` on 2026-07-12 so app repos do not carry cluster control-plane config.

- `clusters/themachine/` - root Flux kustomization for the `themachine` k3s cluster.
- `clusters/themachine/apps/` - GitRepository + Kustomization registrations for app repos.
- `clusters/themachine/platform/` - in-cluster platform services: Cloudflare Tunnel, Homepage, observability, and action runner.
- `clusters/themachine/sites/` - sites owned by this fleet repo, including the public `zakharhome.org` landing page.
- `scripts/` - one-off/bootstrap helpers that are not directly reconciled by Flux.
- `specs/` - current dashboard/control-center design notes and implementation log.

App manifests live in each app's own repo under `deploy/k8s` or `k8s/base`; this repo registers them and owns shared platform surfaces.

## Zakharhome

- Public site: `clusters/themachine/sites/zakharhome/`
- Protected dashboard: `clusters/themachine/platform/homepage/`
- Admin action runner: `clusters/themachine/platform/action-runner/`
- Observability stack: `clusters/themachine/platform/observability/`
- Tunnel config/bootstrap: `clusters/themachine/platform/cloudflared/`

Large embedded ConfigMaps have been split into editable source files and generated with Kustomize `configMapGenerator`.

## Secrets

Secrets are applied manually on `themachine`, never committed. Current secret-backed integrations include Homepage GitHub, Jellyfin, Plex, and Cloudflare Tunnel credentials.
