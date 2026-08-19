#!/usr/bin/env bash
# k3s control-plane datastore backup — node-local, not GitOps-managed (same category as
# containerd trust config / Docker Desktop registry trust in RUNBOOK.md's "Local container
# registry" section: host-level setup outside k8s's own object model).
#
# Backs up the master's SQLite/kine datastore (/var/lib/rancher/k3s/server/db/state.db) plus
# the static cluster-identity material (TLS CA, join token, credentials) needed to restore
# this exact cluster identity onto replacement hardware — not just the data, but the trust
# material so existing workers can reconnect without re-joining.
#
# Destination: /mnt/k8s (already NFS-mounted on this host at nas.local:/mnt/md0/k8s), the same
# NAS that backs every PVC in this cluster.
set -euo pipefail

BACKUP_ROOT="/mnt/k8s/k3s-master-backups"
RETENTION_DAYS=14
TS="$(date +%Y%m%d-%H%M%S)"
WORKDIR="$(mktemp -d)"
trap 'sudo rm -rf "$WORKDIR"' EXIT

fail() {
  echo "k3s-backup FAILED: $1" >&2
  WEBHOOK="$(kubectl get secret discord-webhook -n monitoring -o jsonpath='{.data.address}' 2>/dev/null | base64 -d || true)"
  if [ -n "$WEBHOOK" ]; then
    curl -s -X POST "$WEBHOOK" -H "Content-Type: application/json" \
      -d "{\"username\": \"k8s homelab\", \"content\": \"🔴 **k3s-backup** | Master datastore backup failed on $(hostname): $1\"}" \
      >/dev/null 2>&1 || true
  fi
  exit 1
}

mkdir -p "$BACKUP_ROOT" || fail "cannot create $BACKUP_ROOT (NFS mount down?)"

# 1. Consistent, online snapshot of the live SQLite datastore (WAL-safe — does not require
#    stopping k3s; sqlite3's .backup uses the official SQLite backup API, not a raw file copy,
#    so it can't catch a torn/inconsistent write mid-checkpoint the way `cp` could).
DB_SRC="/var/lib/rancher/k3s/server/db/state.db"
sudo test -f "$DB_SRC" || fail "no datastore found at $DB_SRC — is this actually the k3s server node?"
sudo sqlite3 "$DB_SRC" ".backup '$WORKDIR/state.db'" || fail "sqlite3 .backup failed"

# 2. Static cluster-identity material — TLS CA/certs, join token, credentials. These change
#    rarely (only on cert rotation or initial bootstrap), so a plain copy is fine; no
#    live-consistency concern the way the active database has.
sudo cp -a /var/lib/rancher/k3s/server/tls "$WORKDIR/tls" || fail "failed to copy tls/"
sudo cp -a /var/lib/rancher/k3s/server/cred "$WORKDIR/cred" || fail "failed to copy cred/"
sudo cp /var/lib/rancher/k3s/server/token "$WORKDIR/token" || fail "failed to copy token"

# 3. Package and ship to NFS.
ARCHIVE="k3s-master-backup-${TS}.tar.gz"
sudo tar -czf "/tmp/${ARCHIVE}" -C "$WORKDIR" state.db tls cred token || fail "tar failed"
sudo chown "$(id -u):$(id -g)" "/tmp/${ARCHIVE}"
mv "/tmp/${ARCHIVE}" "${BACKUP_ROOT}/${ARCHIVE}" || fail "failed to move archive to NFS"

# 4. Prune anything older than RETENTION_DAYS.
find "$BACKUP_ROOT" -name 'k3s-master-backup-*.tar.gz' -mtime "+${RETENTION_DAYS}" -delete || true

echo "k3s-backup OK: ${BACKUP_ROOT}/${ARCHIVE} ($(du -h "${BACKUP_ROOT}/${ARCHIVE}" | cut -f1))"
