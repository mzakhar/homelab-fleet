# Mailbox Pixel testing enablement — 2026-10-24

Backend PR #134 is deployed (`9463e70`, image sha256:4374e9f9c185ed01e4c6a4bced035c786f6c75653cdf158f4cf737989a2cc68e).
Authenticated mailbox 404 is explained by MAILBOX_RECOVERY_ENABLED=false.

Enable MAILBOX_RECOVERY_ENABLED=true and GMAIL_BACKEND_UNITS_PER_MINUTE=300
using a merge patch preserving every other Secret key. Git-owned pod annotation
triggers a normal rolling update, retaining old healthy pod until replacement Ready.
No session/grant rotation, mail deletion, or checkpoint reset.

Production OAuth project number 310079203371 differs from Android project
android-cleanmail (298821923080). Prior same-project assumption does not apply.
Actual production project quota has not been retrieved; gcloud is unavailable.
300 units/minute is a conservative testing budget, not a claim about configured
Google quotas. Background allowance is 240 units/minute; initial hydration is slow.

Before enablement: schema 0015; 3676 legacy email rows, zero account-owned rows,
four mobile sessions, two active grants, zero mailbox checkpoints.
Authenticated smoke checks use short-lived JWTs bound to existing valid mobile
sessions; tokens stay in the pod and are not logged. No refresh token rotation.

Rollback: set recovery false with a merge patch and change config-revision via
fleet PR. Keep budget, all mail, sessions, grants, checkpoints and schema intact.
Endpoint verification follows rollout; Pixel destructive/outage drills are separate.
