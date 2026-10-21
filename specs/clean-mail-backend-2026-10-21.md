# Clean Mail backend deployment: 2026-10-21

Deploy backend PR #134, commit `9463e70e1b9110daf89125de2ca482828a75cbac`.
Main CI run `39541825655` succeeded; local backend verification passed all 698 tests.

- New image: `ghcr.io/mzakhar/clean-mail-backend@sha256:4374e9f9c185ed01e4c6a4bced035c786f6c75653cdf158f4cf737989a2cc68e`.
- Previous image: `ghcr.io/mzakhar/clean-mail-backend@sha256:685a7c3c9cc321144e05017f18457fdf96298fbf79b8a18254f490c7cc02c1c1`.
- Backend digest change only; no secret, feature flag, or frontend change.
- Mailbox recovery rollout remains gated on Android #267 and web #31 acceptance.
- Rollback: restore previous digest in a fleet PR; retain database and checkpoints.
- Validation: render root Kustomization before merge; verify Flux revision, ready
  backend image, and health endpoint after reconciliation.

## Verified rollout

Fleet PR #75 merged as `d103c4ffbd7700b1daf16580b77873e65ebfd31b`.
Flux applied that revision; backend rollout completed. Pod
`clean-mail-backend-7b747cdf6b-h7hh7` was Ready (1/1), with zero restarts.
Health endpoint returned HTTP 200 and `{"status":"ok"}`. Read-only database
verification confirmed schema `0015_mailbox_recovery`; recovery flag remains false.
No secrets or frontend changed. Client rollout/real-device acceptance remain pending.
