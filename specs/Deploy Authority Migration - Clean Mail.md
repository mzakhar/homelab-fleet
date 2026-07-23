# Deploy Authority Migration - Clean Mail

Status: planning, no manifests changed
Last updated: 2026-07-22

## Goal

Take deploy authority for the Clean Mail app (currently `mzakhar/gmail-frontend-replacement`,
Flux `path: ./deploy/k8s`) fully into this repo, and rename every runtime
identity from `gmail-*` to `clean-mail-*` as one coordinated change. Both
decisions are frozen inputs from the owner, not open for re-litigation here:

1. **Full coordinated rename** to `clean-mail-*` runtime identities: GHCR
   images, k8s namespace, Flux refs, secret names.
2. **Deploy authority moves into `homelab-fleet`.** Live k8s manifests
   (today `deploy/k8s/` in the app repo) become fleet-owned. Code repos
   (`mzakhar/CleanMail-backend`, new `mzakhar/CleanMail-web-frontend`)
   publish GHCR images only.

Cross-repo execution plan (repo split, history policy, contract boundary,
issue routing): vault note `Clean Mail\specs\Repo Split & Coordinated Rename -
Execution Plan.md`. That note owns the source-repo side; this spec owns only
fleet-side mechanics — manifest layout, identity rename table, Flux
cutover, and rollback. As of this writing that vault note does not exist yet;
confirm it before executing phases below, since it is expected to fix the
final repo names and history policy this spec assumes.

Related app-repo spec (decision record, now resolved):
`docs/specs/15-backend-web-repo-split.md` in `gmail-frontend-replacement`.

## Current State (verified against this repo and the app repo)

- `clusters/themachine/apps/gmail-frontend.yaml`: `GitRepository` name
  `gmail-frontend`, url `https://github.com/mzakhar/gmail-frontend-replacement`,
  `secretRef: gmail-frontend-github`; `Kustomization` name `gmail-frontend`
  reads `path: ./deploy/k8s` from that source, `prune: true`, `wait: true`.
- App repo manifests (`deploy/k8s/`): `namespace.yaml`, `backend.yaml`,
  `frontend.yaml`, `ingress.yaml`, `kustomization.yaml`,
  `secret.template.yaml`, `alembic-baseline-stamp-job.yaml`.
- Namespace `gmail-app`. Images `ghcr.io/mzakhar/gmail-backend`,
  `ghcr.io/mzakhar/gmail-frontend`, both digest-pinned. Secrets
  `gmail-app-secrets` (app config, `Secret/Opaque`) and `ghcr-pull`
  (image pull secret, referenced by name in `backend.yaml`/`frontend.yaml`/
  `alembic-baseline-stamp-job.yaml`, not defined in-repo — applied manually).
  ServiceAccount `gmail-backend`, PVC `gmail-data`, Services
  `gmail-backend-svc` / `gmail-frontend-svc`.
- Ingress hosts: `cleanmail.zakharhome.org` (public, Cloudflare Access),
  LAN path `http://192.168.1.3/gmail/` (Traefik `stripPrefix` middleware
  `gmail-strip-prefix`), plus `cleanmail-api.zakharhome.org` (mobile-only,
  bearer-auth `/api/classification/v1/mobile` prefix straight to backend
  Service, deliberately outside Cloudflare Access).
- Digest pinning today: app-repo `scripts/update-deploy-image.ps1`, invoked
  via root `npm run deploy:pin-image`, edits `deploy/k8s/*.yaml` in place;
  commit/push/PR stay manual/explicit.

## Target Topology

Fleet layout precedent: `clusters/themachine/apps/*.yaml` registers app
repos via a `GitRepository` + `Kustomization` pair pointing at a path *inside
the app repo* (`vs-book-app.yaml` -> `./k8s/base`, current
`gmail-frontend.yaml` -> `./deploy/k8s`). Fleet-owned workloads (no
per-repo GitRepository at all) live directly under
`clusters/themachine/platform/<app>/` (e.g. `platform/homepage/`) with their
own `namespace.yaml`, `deployment.yaml`, `service.yaml`, `ingress.yaml`,
`kustomization.yaml`, wired into the root
`clusters/themachine/kustomization.yaml` resources list directly (no
`GitRepository` needed, since there's no external source to pull).

Clean Mail's manifests, once fleet-owned, are just Kubernetes YAML — they no
longer need to be fetched from a code repo at all. **Recommendation: drop the
per-app `GitRepository`/`Kustomization` pair entirely and manage Clean Mail
the same way `platform/homepage` is managed** — a directory of manifests
reconciled directly by the root kustomization, digest-pinned in place by a
fleet-side script. This matches decision 2 literally (manifests belong to
fleet, not a code repo) and matches the one other precedent in this repo for
an app with no external manifest source.

Proposed path: `clusters/themachine/apps/clean-mail/` (not `platform/`,
since Clean Mail is a personal app the owner interacts with directly, same
category as `vs-book-app`/`synth` today — just without their external
`GitRepository`). Contents, ported 1:1 from `deploy/k8s/` with renames
applied (see table below):

- `namespace.yaml`
- `backend.yaml`
- `frontend.yaml`
- `ingress.yaml`
- `alembic-baseline-stamp-job.yaml`
- `kustomization.yaml`
- `secret.template.yaml` (reference only — never applied by Flux; kept
  alongside for the same manual-apply workflow as today)

Root `clusters/themachine/kustomization.yaml` gains
`apps/clean-mail` (a directory kustomization resource, like
`platform/homepage` is added) and drops `apps/gmail-frontend.yaml`.

Alternative considered and rejected: keep a `GitRepository` per code repo
(one for `CleanMail-backend`, maybe none for web since it has no manifests)
and have fleet's `Kustomization` still pull `path:` from one of those repos.
Rejected because decision 2 says manifests move *into* fleet — leaving Flux
reading `path:` from a code repo re-creates exactly the ownership split
being eliminated, and neither code repo would have a natural single owner
for combined backend+frontend+ingress manifests post-split.

## Identity Rename Table

| Kind | Old | New |
|---|---|---|
| GHCR image (backend) | `ghcr.io/mzakhar/gmail-backend` | `ghcr.io/mzakhar/clean-mail-backend` |
| GHCR image (frontend) | `ghcr.io/mzakhar/gmail-frontend` | `ghcr.io/mzakhar/clean-mail-frontend` |
| Namespace | `gmail-app` | `clean-mail` |
| App secret | `gmail-app-secrets` | `clean-mail-secrets` |
| Pull secret | `ghcr-pull` | `ghcr-pull` (unchanged — see open questions) |
| Flux GitRepository | `gmail-frontend` (name), secretRef `gmail-frontend-github` | removed (see Target Topology) |
| Flux Kustomization | `gmail-frontend` | `clean-mail` (or removed if folded into root kustomization directly, matching `platform/homepage`) |
| ServiceAccount | `gmail-backend` | `clean-mail-backend` |
| PVC | `gmail-data` | `clean-mail-data` |
| Deployment (backend) | `gmail-backend` | `clean-mail-backend` |
| Deployment (frontend) | `gmail-frontend` | `clean-mail-frontend` |
| Service (backend) | `gmail-backend-svc` | `clean-mail-backend-svc` |
| Service (frontend) | `gmail-frontend-svc` | `clean-mail-frontend-svc` |
| Traefik Middleware | `gmail-strip-prefix` | `clean-mail-strip-prefix` |
| Ingress (LAN) | `gmail-app` | `clean-mail` |
| Ingress (public) | `gmail-app-external` | `clean-mail-external` |
| Ingress (mobile API) | `gmail-app-mobile` | `clean-mail-mobile` |
| Alembic stamp Job | `gmail-backend-alembic-baseline-stamp` | `clean-mail-backend-alembic-baseline-stamp` |
| Ingress host (public) | `cleanmail.zakharhome.org` | unchanged (already `cleanmail`, not `gmail`) |
| Ingress host (mobile) | `cleanmail-api.zakharhome.org` | unchanged |
| LAN path prefix | `/gmail` | open question — see below |

## Migration Steps

### a. Port manifests into fleet with renames

Copy the 7 files from app-repo `deploy/k8s/` into
`clusters/themachine/apps/clean-mail/`, applying every rename in the table
above (metadata `name`, `namespace`, `image`, label selectors, `envFrom`/
`secretRef` names, `imagePullSecrets` name, `serviceAccountName`,
`volumeMounts`/`claimName`, ingress `middlewares` annotation string). Keep
the readiness-probe `Host: localhost` header verbatim (see Gotchas below).
Root kustomization's per-namespace default (`namespace: gmail-app` in
`kustomization.yaml`) becomes `namespace: clean-mail`.

### b. Secrets

- Create `clean-mail-secrets` in the new `clean-mail` namespace (copy
  values from the live `gmail-app-secrets`, do not regenerate
  `TOKEN_ENCRYPTION_KEY`/`SESSION_SECRET_KEY` — regenerating invalidates
  existing sessions and encrypted tokens at rest).
- `ghcr-pull`: recreate in the `clean-mail` namespace under the same or a
  renamed name (open question below). Whatever name is chosen, it must
  authenticate against the *new* image repos
  (`ghcr.io/mzakhar/clean-mail-backend`, `ghcr.io/mzakhar/clean-mail-frontend`)
  before the new Deployments can pull — this is a hard precondition for
  cutover, not a nice-to-have.
- `secret.template.yaml` moves into `apps/clean-mail/` for reference,
  updated to the new secret name and namespace; still never applied by
  Flux.

### c. Flux GitRepository / Kustomization repoint

- Recommended (per Target Topology): delete
  `clusters/themachine/apps/gmail-frontend.yaml` entirely (both the
  `GitRepository` and `Kustomization` it defines). Add
  `clusters/themachine/apps/clean-mail/` as a plain manifest directory,
  referenced directly from the root `clusters/themachine/kustomization.yaml`
  resources list, same as `platform/homepage`.
- `gmail-frontend-github` deploy-key secret becomes unused once the
  `GitRepository` is deleted; leave it in place until cutover is verified
  green, then remove (see Rollback).

### d. Digest pinning moves into fleet

- Bring an equivalent of `scripts/update-deploy-image.ps1` into this repo's
  `scripts/`, retargeted at `apps/clean-mail/*.yaml` and the new image
  names. Keep the same shape: script edits manifests only, commit/push/PR
  stay explicit manual steps (matches this repo's existing pattern of no
  auto-commit tooling).
- App repos' CI still publishes tagged images
  (`ghcr.io/mzakhar/clean-mail-backend:main`, etc.); fleet is the only place
  that resolves a tag to a digest and writes it into a manifest.
- Retire `npm run deploy:pin-image` and `scripts/update-deploy-image.ps1` in
  the app repo once the fleet-side equivalent is live, to avoid two tools
  editing manifests in different repos.

### e. Cutover order

New identities must exist and be pullable before the old namespace is
pruned, or pods chase a half-renamed image/namespace and the app goes down
mid-migration:

1. Land the coordinated rename in the code repo(s) first: CI publishes
   `ghcr.io/mzakhar/clean-mail-backend` / `clean-mail-frontend` images.
   Fleet cutover cannot start before these exist (see Sequencing below).
2. Apply `clean-mail` namespace, `clean-mail-secrets`, and the (possibly
   renamed) pull secret manually on `themachine` — these are prerequisites,
   not reconciled content, same as today's `gmail-app-secrets`/`ghcr-pull`.
3. Add `apps/clean-mail/` manifests to this repo, verified digest-pinned to
   the newly published images (`kubectl kustomize clusters/themachine`
   locally first).
4. Push. Let Flux reconcile the *new* `clean-mail` namespace/workloads
   alongside the still-running `gmail-app` namespace (both can coexist —
   different namespaces, no port/host collision as long as ingress hosts
   aren't claimed by both simultaneously; stage ingress last, step 6).
5. Verify new pods healthy in `clean-mail` namespace before touching
   ingress or DNS (see Verification below).
6. Cut ingress over: apply the new `clean-mail`/`clean-mail-external`/
   `clean-mail-mobile` Ingress objects (new hostnames are unchanged
   `cleanmail.zakharhome.org`/`cleanmail-api.zakharhome.org`, so this is the
   point of user-visible traffic switch — Traefik will have two Ingress
   objects claiming the same host briefly if old ones aren't removed in the
   same change; remove old Ingress objects in the same commit as adding the
   new ones to avoid ambiguous routing).
7. Only after step 6 verifies green: remove
   `clusters/themachine/apps/gmail-frontend.yaml` (old GitRepository +
   Kustomization) and let Flux prune the old `gmail-app` namespace.
8. Remove now-unused `gmail-frontend-github` deploy-key secret.

### f. Verification

- `kubectl -n clean-mail get pods` — backend and frontend Deployments
  Ready.
- Readiness probe: backend probe pins `Host: localhost` in the httpGet
  header (`TrustedHostMiddleware` otherwise rejects the kubelet's pod-IP
  Host) — confirm this survives the copy verbatim, and that
  `backend/core/config.py` `allowed_hosts` (app-repo side, out of scope
  here) still includes whatever hostnames the renamed ingress uses.
- `https://cleanmail.zakharhome.org/` loads, OAuth/session login round-trips
  (cookie session depends on `SESSION_SECRET_KEY` carried over unchanged in
  step b).
- LAN path `http://192.168.1.3/gmail/` (or renamed path, see open questions)
  loads through the renamed `clean-mail-strip-prefix` middleware.
- `cleanmail-api.zakharhome.org` mobile bearer-auth prefix still 404s
  everything except `/api/classification/v1/mobile`.
- Alembic stamp Job only needs re-running if a fresh PVC is provisioned;
  if `clean-mail-data` PVC is a copy of `gmail-data` (not a fresh volume),
  skip re-stamping — confirm data migration approach before running.

### g. Rollback

Keep `gmail-app` namespace, `gmail-app-secrets`, `ghcr-pull`, and
`clusters/themachine/apps/gmail-frontend.yaml` untouched (not deleted, not
pruned) until step (f) verification is fully green. Flux `prune: true` on
the old Kustomization means simply leaving the old `apps/gmail-frontend.yaml`
file in place keeps the old namespace alive and reconciled in parallel; only
delete that file (triggering prune) as the last migration step, well after
confirming the new namespace serves production traffic correctly.

## Sequencing Dependency

Fleet cutover has a hard external dependency: the renamed GHCR images
(`clean-mail-backend`, `clean-mail-frontend`) are produced by the code
repos' CI, not by fleet. Do not create `apps/clean-mail/` manifests pointing
at digests that don't exist yet. Confirm the CleanMail-backend /
CleanMail-web-frontend CI pipelines are live and have published at least one
tagged build under the new names before starting step (e).

Namespace rename is effectively destructive once cut over: Flux's
`prune: true` on the old `Kustomization` will delete every object it manages
(Deployments, Services, PVC-referencing objects, Ingress) when
`gmail-frontend.yaml` is removed. The `local-path` StorageClass has
`reclaimPolicy: Delete`, so pruning the PVC **deletes the on-node data
directory** — this is irreversible. The **PVC data itself** (`gmail-data`)
must be copied forward *and* a backup tarball retained *before* the old
namespace is pruned. Procedure resolved below (§"PVC Data Migration").

## PVC Data Migration (RESOLVED 2026-07-22)

**Decision: cold tar copy into a fresh `clean-mail-data` PVC.** Not PV
rebind, not an in-cluster two-PVC copy Job.

Verified ground truth (from `themachine` on 2026-07-22):

| Fact | Value |
|------|-------|
| StorageClass | `local-path` (default), `WaitForFirstConsumer` |
| Reclaim policy | **`Delete`** — pruning the PVC wipes the on-disk dir |
| PV host path | `/var/lib/rancher/k3s/storage/pvc-0ebae5a3-5695-4daf-8b23-655009982698_gmail-app_gmail-data` |
| Total size | **~150 MB** (`app.db` 45 MB, `app.db-wal` **45 MB uncheckpointed**, `app.db-shm`, plus app-managed `backups/`) |
| Contents | SQLite `app.db` + Chroma dir + app's own `backups/` — all file-based on one node-local RWO volume |

**Why cold copy, not PV rebind:** the volume is only ~150 MB, so copy cost is
seconds — the "no data copy" advantage of rebind is worthless here. Rebind
would require first flipping `reclaimPolicy` to `Retain` and manually patching
the PV `claimRef` to the new namespace; a slip during that flip permanently
deletes the only DB copy (policy is `Delete` today). Cold copy also yields a
portable backup tarball for free and is storage-class-agnostic (survives a
future move off `local-path`).

**Why cold (quiesce first):** `app.db-wal` is ~45 MB of uncheckpointed writes —
copying `app.db` alone would silently lose them. Scaling the backend to 0
closes the SQLite handle, which checkpoints the WAL into `app.db` on clean
shutdown, and also stops Chroma writers so its files aren't captured mid-write.
Do **not** hot-copy.

Procedure (runs inside migration step (e), before the old namespace is pruned):

1. **Announce downtime.** This is a cold migration; the app is offline for the
   copy (minutes for ~150 MB).
2. **Freeze Flux on the old app** so it can't scale the backend back up:
   `flux -n flux-system suspend kustomization gmail-frontend`.
3. **Quiesce the writer:**
   `kubectl -n gmail-app scale deploy/gmail-backend --replicas=0` and wait for
   the pod to terminate (confirms WAL checkpointed, Chroma closed).
4. **Backup artifact (rollback):** on `themachine`,
   `sudo tar czf /root/gmail-data-$(date +%Y%m%d).tgz -C <PV host path> .`
   Retain this tarball until the new namespace is verified green — it is the
   irreversibility backstop against the `Delete` reclaim policy.
5. **Provision the new PVC:** apply the `clean-mail` namespace + `clean-mail-data`
   PVC manifest. `WaitForFirstConsumer` means the PV dir isn't created until a
   pod mounts it — bring up the new backend (step f) or a throwaway pod so the
   provisioner creates the target dir.
6. **Copy forward:** single-node, so copy node-to-node directly —
   `sudo cp -a <old PV dir>/. <new PV dir>/` (or extract the step-4 tarball into
   the new dir). Fix ownership/perms to match the original (`app.db` was
   `root:root 0644`, dir `0777`).
7. **Skip alembic re-stamp:** because this is a data copy (not a fresh volume),
   `alembic_version` comes across intact — do **not** re-run the baseline stamp
   Job (aligns with step-e note on the Job).
8. **Bring up + verify** (step f): confirm `alembic_version` matches, spot-check
   row counts against pre-migration, Chroma loads, app reachable at the ingress.
9. **Only after green:** remove `gmail-frontend.yaml` so Flux prunes the old
   `gmail-app` namespace — its PVC delete now wipes the old dir harmlessly
   (copy verified, tarball retained).

Rollback: if step 8 fails, re-point to the old namespace (still present until
step 9) or restore the step-4 tarball. Never delete the old namespace before
verification.

## Open Questions for Owner

1. Keep `ghcr-pull` secret name unchanged (simplest, name doesn't reference
   the app) or rename to `clean-mail-ghcr-pull` for consistency with every
   other renamed identity?
2. Confirm dropping the per-app `GitRepository`/`Kustomization` pair
   entirely (manifests become plain fleet YAML, like `platform/homepage`)
   rather than keeping a `GitRepository` pointed at one of the two new code
   repos. This spec recommends dropping it; confirm before executing.
2b. Given (2), where should `clusters/themachine/apps/clean-mail/` truly
    live — `apps/` (personal app precedent: `vs-book-app`, `synth`) as
    proposed, or `platform/` (shared-service precedent: `homepage`,
    `cloudflared`)? Proposal above uses `apps/`.
3. LAN path `/gmail` -> rename to `/clean-mail` (and update the Traefik
   `stripPrefix` middleware + `GOOGLE_REDIRECT_URI`/`FRONTEND_URL` secret
   values + Google Cloud Console authorized redirect URI to match), or
   leave the LAN path as legacy `/gmail` since it's not user-facing product
   branding and a path rename adds an OAuth-redirect-URI coordination step
   with no functional benefit?
4. ~~PVC data migration: copy vs PV rebind.~~ **RESOLVED 2026-07-22 —
   cold tar copy into a fresh `clean-mail-data` PVC.** See §"PVC Data
   Migration" below.
5. Does the vault execution spec (`Clean Mail\specs\Repo Split & Coordinated
   Rename - Execution Plan.md`) already answer any of the above? It did not
   exist in the vault at the time this spec was written — confirm its
   contents don't conflict before executing.

## Status

2026-07-22: planning only. No manifests changed, no k8s objects touched, no
commits made in this repo or the app repo. This spec records the fleet-side
target state and phased migration for later execution once the code-repo
split (backend/web) and image rename land.
