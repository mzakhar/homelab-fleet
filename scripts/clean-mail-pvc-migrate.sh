#!/usr/bin/env bash
# Clean Mail P6 PVC cold-copy migration: gmail-app/gmail-data -> clean-mail/clean-mail-data.
#
# Run ON themachine (ssh mzakhar@themachine), NOT locally. Needs sudo (tar/cp
# into /var/lib/rancher/k3s/storage) and kubectl + flux CLIs.
#
# Procedure source of truth: specs/Deploy Authority Migration - Clean Mail.md
# §"PVC Data Migration" (cold tar copy decided 2026-07-22). Summary:
#   - App goes OFFLINE for the copy (~150 MB, minutes). Announce first.
#   - Old backend scaled to 0 so the ~45 MB SQLite WAL checkpoints into app.db
#     and Chroma closes. NEVER hot-copy.
#   - Backup tarball kept in /root as the rollback backstop (reclaimPolicy is
#     Delete — pruning the old PVC wipes its dir irreversibly).
#   - Do NOT run the alembic baseline-stamp job afterwards: this is a data
#     copy, alembic_version comes across intact.
#
# Prerequisites (script checks): clean-mail namespace + clean-mail-data PVC
# already applied (P6 flip reconciled, or apply apps/clean-mail/namespace.yaml
# + the PVC manually), clean-mail-secrets + clean-mail-ghcr-pull applied.
set -euo pipefail

OLD_NS=gmail-app
OLD_PVC=gmail-data
OLD_DEPLOY=gmail-backend
NEW_NS=clean-mail
NEW_PVC=clean-mail-data
NEW_DEPLOY=clean-mail-backend
BINDER_POD=clean-mail-pvc-binder

confirm() {
  read -rp "$1 [y/N] " ans
  [[ "${ans,,}" == y* ]] || { echo "Aborted."; exit 1; }
}

pv_path() { # namespace pvc -> host path
  local pv
  pv=$(kubectl -n "$1" get pvc "$2" -o jsonpath='{.spec.volumeName}')
  [[ -n "$pv" ]] || { echo "PVC $1/$2 not bound" >&2; return 1; }
  # k3s local-path PVs use spec.local.path (newer) or spec.hostPath.path (older)
  kubectl get pv "$pv" -o jsonpath='{.spec.local.path}{.spec.hostPath.path}'
}

echo "== Clean Mail PVC cold-copy migration =="
kubectl get ns "$NEW_NS" >/dev/null
kubectl -n "$NEW_NS" get pvc "$NEW_PVC" >/dev/null 2>&1 || \
  { echo "PVC $NEW_NS/$NEW_PVC not applied yet — apply apps/clean-mail first."; exit 1; }
kubectl -n "$NEW_NS" get secret clean-mail-secrets clean-mail-ghcr-pull >/dev/null

confirm "App will go OFFLINE for the copy. Continue?"

echo "-- 1/6 Suspending Flux on the old app (no scale-back-up mid-copy)"
flux -n flux-system suspend kustomization gmail-frontend

echo "-- 2/6 Quiescing writer: scaling $OLD_NS/$OLD_DEPLOY to 0 (WAL checkpoint + Chroma close)"
kubectl -n "$OLD_NS" scale "deploy/$OLD_DEPLOY" --replicas=0
kubectl -n "$OLD_NS" wait --for=delete pod -l "app=$OLD_DEPLOY" --timeout=120s

OLD_DIR=$(pv_path "$OLD_NS" "$OLD_PVC")
echo "   Old PV dir: $OLD_DIR"

echo "-- 3/6 Backup tarball (rollback backstop, keep until soak ends)"
TARBALL="/root/gmail-data-$(date +%Y%m%d).tgz"
sudo tar czf "$TARBALL" -C "$OLD_DIR" .
sudo ls -lh "$TARBALL"

echo "-- 4/6 Binding new PVC (WaitForFirstConsumer needs a consumer to provision)"
# Keep the new backend down so it cannot create a fresh app.db before the copy.
kubectl -n "$NEW_NS" get deploy "$NEW_DEPLOY" >/dev/null 2>&1 && \
  kubectl -n "$NEW_NS" scale "deploy/$NEW_DEPLOY" --replicas=0 || true
kubectl -n "$NEW_NS" apply -f - <<PODEOF
apiVersion: v1
kind: Pod
metadata:
  name: $BINDER_POD
spec:
  restartPolicy: Never
  containers:
    - name: binder
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: $NEW_PVC
PODEOF
kubectl -n "$NEW_NS" wait --for=condition=Ready "pod/$BINDER_POD" --timeout=180s

NEW_DIR=$(pv_path "$NEW_NS" "$NEW_PVC")
echo "   New PV dir: $NEW_DIR"

echo "-- 5/6 Copying data forward (cp -a preserves ownership/perms)"
sudo cp -a "$OLD_DIR/." "$NEW_DIR/"
echo "   Old:"; sudo du -sh "$OLD_DIR"
echo "   New:"; sudo du -sh "$NEW_DIR"
sudo ls -la "$NEW_DIR" | head -15

echo "-- 6/6 Cleanup binder pod"
kubectl -n "$NEW_NS" delete pod "$BINDER_POD" --wait=false

cat <<'NEXT'
== Copy done. Next (manual, per spec step f/8): ==
  1. Scale up:   kubectl -n clean-mail scale deploy/clean-mail-backend --replicas=1
  2. Verify:     pods Ready, alembic_version intact, row counts, Chroma loads,
                 https://cleanmail.zakharhome.org/ + LAN /gmail/ + mobile API.
  3. Do NOT run the alembic baseline-stamp job (data copy, not fresh volume).
  4. Old stack stays suspended-but-present for rollback; only after verified
     green: remove apps/gmail-frontend.yaml (Flux prunes gmail-app), then drop
     gmail-frontend-github secret. Keep the tarball through the soak period.
Rollback: flux -n flux-system resume kustomization gmail-frontend
          kubectl -n gmail-app scale deploy/gmail-backend --replicas=1
NEXT
