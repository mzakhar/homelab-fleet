# Secret Management Plan

Status: proposed, not started
Last updated: 2026-07-30

## Problem

Every other piece of cluster state in this repo is declarative and reconciled by
Flux. Secrets are the one hole: they are applied by hand on `themachine`, so
correctness depends on an operator or an agent remembering a rule. That is why
the merge-patch rule had to be written into `AGENTS.md` at all — a documented
footgun is a workaround, not a fix.

Concrete failure already hit on 2026-07-26: piping
`kubectl create secret generic --dry-run=client -o yaml` into `kubectl apply`
declares the *whole* Secret, so using it to add one key drops every key it was
not given and crashes pods consuming the Secret via `envFrom`.

## Live Inventory

Taken from `themachine` on 2026-07-30, Opaque secrets only, excluding
`flux-system` and Helm release state:

| Secret | Keys | Notes |
|---|---|---|
| `clean-mail/clean-mail-secrets` | 31 | The problem case. See below. |
| `homepage/homepage-secrets` | 3 | GitHub, Jellyfin, Plex tokens. All genuine secrets. |
| `vs-book-app/vs-book-app-admin` | 2 | Admin username/password. |
| `vs-book-app/vs-book-app-github` | 1 | GitHub token. |
| `cloudflared/cloudflared-tunnel-token` | 1 | Tunnel credential. |
| `action-runner/action-runner-ntfy` | 1 | ntfy topic URL. |

## The Real Finding

`clean-mail-secrets` holds 31 keys, and most of them are not secrets. They are
feature flags and config:

- Booleans: `LOST_MAIL_SCAN_ENABLED`, `LOST_MAIL_WEB_ENABLED`,
  `LOST_MAIL_WEB_ACTIONS_ENABLED`, `LOST_MAIL_MOBILE_READ_ENABLED`,
  `LOST_MAIL_MOBILE_ACTIONS_ENABLED`, `CLASSIFICATION_JOBS_ENABLED`,
  `CLASSIFICATION_CHANGE_FEED_ENABLED`, `CLASSIFICATION_READY_FCM_ENABLED`,
  `LIVE_CLASSIFICATION_SYNC_ENABLED`, `MOBILE_CLASSIFICATION_SHADOW_ENABLED`,
  `MOBILE_FCM_REGISTRATION_ENABLED`, `GMAIL_PUBSUB_PULL_ENABLED`,
  `GMAIL_WATCH_RENEWAL_ENABLED`
- Intervals: `CLASSIFICATION_WORKER_INTERVAL_SECONDS`,
  `GMAIL_WATCH_CHECK_INTERVAL_MINUTES`
- Non-secret identifiers and paths: `APP_ENV`, `ADMIN_EMAIL`, `CHROMA_PATH`,
  `FRONTEND_URL`, `GOOGLE_REDIRECT_URI`, `GOOGLE_CLIENT_ID`, `FCM_PROJECT_ID`,
  `GMAIL_WATCH_TOPIC`, `GMAIL_PUBSUB_SUBSCRIPTION`, `GITHUB_FEEDBACK_REPO`

Genuinely secret, roughly 7 keys: `GOOGLE_CLIENT_SECRET`,
`GOOGLE_PUBSUB_CREDENTIALS_JSON`, `GITHUB_FEEDBACK_TOKEN`,
`SESSION_SECRET_KEY`, `TOKEN_ENCRYPTION_KEY`, `DATABASE_URL`, and the Gmail
OAuth material behind it.

This inverts the priority. Flags are what get edited, one key at a time, by hand
— which is exactly the operation that nearly wiped the Secret. Moving config out
removes most of the reason anyone touches the Secret at all, and it is simpler
than adopting SOPS.

Doing the split first also aligns with the existing rule in `CLAUDE.md` that
large ConfigMaps should be split into editable source files and generated with
Kustomize `configMapGenerator`.

## Phases

### Phase 1 - Split config out of secrets

- [ ] Move the flag, interval, and non-secret identifier keys from
  `clean-mail-secrets` into a Flux-managed ConfigMap, generated with
  `configMapGenerator` from an editable source file.
- [ ] Add a second `envFrom` entry to the Clean Mail backend and any job that
  reads these values, keeping the Secret for the ~7 real secrets.
- [ ] Verify flag changes now ship through git and Flux with no `kubectl`.
- [ ] Remove the flag keys from the live Secret only after the ConfigMap path is
  confirmed working, so a rollback still has them.

Flag flips become reviewable, diffable, and revertable, and the remaining Secret
is small enough that full-replace is safe again.

### Phase 2 - SOPS with age for the real secrets

Flux on `themachine` is v2.8.6 with kustomize-controller v1.8.4, which supports
SOPS decryption natively.

- [ ] Generate an age key on `themachine`. Public key committed, private key
  never.
- [ ] Create the `sops-age` secret in `flux-system` from the private key.
- [ ] Add `.sops.yaml` with a creation rule scoping encryption to
  `data` and `stringData` fields only, so metadata stays readable in diffs.
- [ ] Set `decryption.provider: sops` and the key secret ref on the root
  Kustomization.
- [ ] Migrate one low-risk secret first — `action-runner-ntfy`, since alert push
  degrades to a no-op if it breaks.
- [ ] Migrate `homepage-secrets`, `vs-book-app-*`, `cloudflared-tunnel-token`,
  then `clean-mail-secrets` last.
- [ ] Delete `*.secret.template.yaml` files and the merge-patch rule from
  `AGENTS.md` once nothing is applied by hand.

### Phase 3 - Key custody

- [ ] Back up the age private key somewhere that survives losing `themachine`.
      Losing it means every committed secret is unrecoverable ciphertext.
- [ ] Write down the recovery procedure: restore key, recreate `sops-age`,
      reconcile.
- [ ] Decide and record a rotation story for the age key itself.

## Rejected Alternatives

- **Sealed Secrets** — ties ciphertext to a controller-held key that must be
  backed up separately, and the sealed values are not decryptable locally for
  review. SOPS with age keeps the operator able to read and edit.
- **External Secrets plus a real secret store** — correct for a team with an
  existing vault. For a single-operator homelab it adds a dependency and an
  availability failure mode to buy nothing this repo needs.
- **Keeping the status quo and relying on the `AGENTS.md` rule** — it already
  failed once. A rule that must be remembered by every future operator and agent
  is weaker than a mechanism that cannot be got wrong.

## Decisions

- 2026-07-30: Split non-secret config out of `clean-mail-secrets` before
  adopting any encryption tooling. Most manual Secret edits are flag flips, so
  this removes the majority of the clobbering exposure and is the smaller
  change.
- 2026-07-30: Prefer SOPS with age over Sealed Secrets or External Secrets.
  Flux decrypts it natively, secrets stay reviewable in git, and there is no
  extra controller or network dependency.
- 2026-07-30: Treat age key custody as part of the migration, not an afterthought.
  The failure mode of losing it is worse than the manual-apply problem being
  solved.
