# homelab-fleet

Flux CD cluster configuration for the home lab (themachine, k3s). Moved out of mzakhar/vs-book-app 2026-07-12 so app repos don't carry cluster control-plane config.

- `clusters/themachine/` — Flux bootstrap (flux-system), app registrations (GitRepository + Kustomization per app repo), cloudflared tunnel deployment + bootstrap script.
- App manifests live in each app's own repo under `deploy/k8s` or `k8s/base`; this repo only registers them.
- `clusters/themachine/homepage/` owns the Homepage dashboard for `dashboard.zakharhome.org`; protect this hostname with Cloudflare Access.
- Secrets are applied manually on themachine, never committed.
