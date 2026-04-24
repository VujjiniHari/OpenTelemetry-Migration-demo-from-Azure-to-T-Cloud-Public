#!/usr/bin/env bash
# =============================================================================
# velero-restore.sh — Restore the Velero Backup to the Target CCE Cluster
# =============================================================================
# This script restores a Velero backup from OBS onto the target T-Cloud CCE
# cluster. It handles the critical pre-restore steps including:
#   - Applying the storage class translation ConfigMap
#   - Verifying Velero connectivity to OBS
#   - Running the restore with proper flags
#   - Validating the restored resources
#
# IMPORTANT: Before running this script, ensure:
#   1. kubectl is pointing at the TARGET CCE cluster (not Azure AKS)
#   2. Velero is installed on the CCE cluster with the same OBS configuration
#   3. The "change-storage-class" ConfigMap hasn't been applied yet (this
#      script applies it)
#
# PREREQUISITES:
#   - Velero CLI installed
#   - Velero server installed on the CCE cluster
#   - kubectl pointing at the CCE target cluster
#   - OBS bucket accessible from CCE cluster
#   - A completed backup exists in OBS (run velero-backup.sh first)
#
# USAGE:
#   chmod +x velero-restore.sh
#   ./velero-restore.sh <backup-name>
#
#   Example:
#   ./velero-restore.sh otel-migration-20260421-143000
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# The backup name must be passed as the first argument.
# This is the name used when creating the backup with velero-backup.sh.
BACKUP_NAME="${1:-}"
STORAGE_CLASS_MAP="../migration-scripts/change-storage-class.yaml"

if [[ -z "${BACKUP_NAME}" ]]; then
  echo "ERROR: Backup name is required."
  echo "Usage: $0 <backup-name>"
  echo ""
  echo "Available backups:"
  velero backup get 2>/dev/null || echo "  (could not list backups — is Velero installed?)"
  exit 1
fi

echo "=============================================="
echo " Velero Restore — T-Cloud CCE Target Cluster"
echo "=============================================="
echo ""
echo "  Backup Name:  ${BACKUP_NAME}"
echo "  Target:       $(kubectl config current-context 2>/dev/null || echo 'unknown')"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Safety check — confirm we're on the TARGET cluster
# ---------------------------------------------------------------------------
# WHY THIS CHECK: Accidentally restoring to the source cluster would create
# duplicate resources and potentially break the running application. We ask
# the presenter to confirm they're on the right cluster.
echo "[1/6] Cluster context verification..."
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "unknown")
echo "  Current kubectl context: ${CURRENT_CONTEXT}"
echo ""
read -rp "  Is this the TARGET (T-Cloud CCE) cluster? [y/N]: " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
  echo "  Aborting. Switch to the CCE cluster with:"
  echo "    export KUBECONFIG=/path/to/cce-kubeconfig.json"
  exit 1
fi
echo ""

# ---------------------------------------------------------------------------
# Step 2: Apply the Storage Class Translation ConfigMap
# ---------------------------------------------------------------------------
# THIS IS THE CRITICAL STEP for cross-cloud migration.
# Without this ConfigMap, all PVCs would fail because Azure storage classes
# (managed-csi, managed-premium, etc.) don't exist on T-Cloud.
# Velero reads this ConfigMap during restore and rewrites PVC storage classes.
echo "[2/6] Applying storage class translation ConfigMap..."
if [[ -f "${STORAGE_CLASS_MAP}" ]]; then
  kubectl apply -f "${STORAGE_CLASS_MAP}"
  echo "  ✓ Storage class mapping applied"
elif [[ -f "change-storage-class.yaml" ]]; then
  kubectl apply -f "change-storage-class.yaml"
  echo "  ✓ Storage class mapping applied (from current directory)"
else
  echo "  WARNING: change-storage-class.yaml not found."
  echo "  PVC restore may fail if Azure storage classes are referenced."
  echo "  Create the ConfigMap manually or provide the correct path."
fi
echo ""

# ---------------------------------------------------------------------------
# Step 3: Verify Velero sees the backup from OBS
# ---------------------------------------------------------------------------
# WHY: The backup was created on the source cluster but stored in OBS.
# The target cluster's Velero must be able to see it via the shared OBS bucket.
echo "[3/6] Verifying backup '${BACKUP_NAME}' is visible from this cluster..."
if velero backup get "${BACKUP_NAME}" &>/dev/null; then
  echo "  ✓ Backup '${BACKUP_NAME}' found in OBS"
else
  echo "  ✗ Backup not found. Possible causes:"
  echo "    - Different OBS bucket or credentials on this cluster"
  echo "    - Backup hasn't synced yet (wait 60s and retry)"
  echo "    - Backup name is misspelled"
  echo ""
  echo "  Available backups:"
  velero backup get 2>/dev/null
  exit 1
fi
echo ""

# ---------------------------------------------------------------------------
# Step 4: Run the Velero restore
# ---------------------------------------------------------------------------
# KEY FLAGS:
# --restore-volumes: Restore persistent volume data (not just PVC definitions).
#   This ensures the actual data is copied from OBS to T-Cloud EVS disks.
# --wait: Block until the restore completes.
#
# NOTE: Velero will automatically read the "change-storage-class" ConfigMap
# and translate any Azure storage class references to their T-Cloud equivalents.
echo "[4/6] Starting Velero restore..."
echo "  This may take several minutes depending on PV data size..."
echo ""
velero restore create \
  --from-backup "${BACKUP_NAME}" \
  --restore-volumes \
  --wait

echo ""
echo "  ✓ Restore completed"
echo ""

# ---------------------------------------------------------------------------
# Step 5: Verify restored resources
# ---------------------------------------------------------------------------
echo "[5/6] Verifying restored resources..."
echo ""
echo "  Namespaces:"
kubectl get namespaces | grep -E "opentelemetry|velero" || echo "  (none found)"
echo ""
echo "  Pods in 'opentelemetry' namespace:"
kubectl get pods -n opentelemetry 2>/dev/null || echo "  (namespace not yet available)"
echo ""
echo "  PVCs in 'opentelemetry' namespace:"
kubectl get pvc -n opentelemetry 2>/dev/null || echo "  (no PVCs found)"
echo ""

# ---------------------------------------------------------------------------
# Step 6: Wait for pods to reach Ready state
# ---------------------------------------------------------------------------
echo "[6/6] Waiting for pods to stabilize (up to 5 minutes)..."
kubectl wait --for=condition=Ready pods --all -n opentelemetry --timeout=300s 2>/dev/null || {
  echo "  ⚠ Some pods may still be starting. Check with:"
  echo "    kubectl get pods -n opentelemetry"
}
echo ""

echo "=============================================="
echo " Restore Complete!"
echo "=============================================="
echo ""
echo "  The OpenTelemetry demo has been restored to the CCE cluster."
echo ""
echo "  Next Steps:"
echo "    1. Verify pods: kubectl get pods -n opentelemetry"
echo "    2. Check PVC status: kubectl get pvc -n opentelemetry"
echo "    3. Deploy via ArgoCD for ongoing GitOps management"
echo "    4. Update DNS to point to the T-Cloud ELB IP"
echo ""
echo "=============================================="
