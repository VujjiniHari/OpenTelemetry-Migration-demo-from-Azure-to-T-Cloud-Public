#!/usr/bin/env bash
# =============================================================================
# velero-backup.sh — Create a Velero Backup of the Source AKS Cluster
# =============================================================================
# This script creates a Velero backup of the OpenTelemetry demo namespace
# on the Azure AKS source cluster. The backup captures:
#   - All Kubernetes resources (Deployments, Services, ConfigMaps, Secrets, etc.)
#   - Persistent Volume data (via File System Backup / FSB mode)
#
# WHY VELERO (not just kubectl get/apply)?
# Velero captures the COMPLETE state including:
#   - Resource relationships and ordering
#   - Persistent volume DATA (not just PVC definitions)
#   - Annotations, labels, and metadata
# A simple kubectl export would miss the PV data entirely.
#
# HOW IT WORKS:
# 1. Velero's server component (already installed in the cluster) communicates
#    with the Kubernetes API to snapshot all resources in the target namespace
# 2. The Node Agent (DaemonSet) handles file-system-level backup of PVs
# 3. Everything is stored in the OBS bucket configured during Velero install
# 4. The backup can then be restored on the target CCE cluster
#
# PREREQUISITES:
#   - Velero CLI installed (brew install velero)
#   - Velero server installed on the AKS cluster (see install-velero.sh)
#   - kubectl pointing at the AKS source cluster
#   - OBS bucket configured and accessible
#
# USAGE:
#   chmod +x velero-backup.sh
#   ./velero-backup.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# Backup name includes a timestamp for uniqueness across demo runs.
# This prevents conflicts if the demo is run multiple times.
BACKUP_NAME="${BACKUP_NAME:-otel-migration-$(date +%Y%m%d-%H%M%S)}"

# Namespace to back up — this is where the OpenTelemetry demo is deployed
TARGET_NAMESPACE="${TARGET_NAMESPACE:-opentelemetry}"

# Time-to-live for the backup. After this period, Velero automatically
# deletes the backup from OBS. 72h is generous for a demo.
BACKUP_TTL="${BACKUP_TTL:-72h}"

echo "=============================================="
echo " Velero Backup — AKS Source Cluster"
echo "=============================================="
echo ""
echo "  Backup Name:       ${BACKUP_NAME}"
echo "  Target Namespace:  ${TARGET_NAMESPACE}"
echo "  TTL:               ${BACKUP_TTL}"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Verify Velero is operational
# ---------------------------------------------------------------------------
echo "[1/4] Verifying Velero installation..."
if ! velero version &>/dev/null; then
  echo "ERROR: Velero CLI not found. Install with: brew install velero"
  exit 1
fi

# Check that the backup storage location is available
BSL_STATUS=$(velero get backup-locations -o json 2>/dev/null | grep -c '"phase":"Available"' || echo "0")
if [[ "${BSL_STATUS}" -eq 0 ]]; then
  echo "WARNING: No available backup storage locations found."
  echo "  Run: velero get backup-locations"
  echo "  Ensure OBS credentials are configured correctly."
fi
echo "  ✓ Velero is operational"
echo ""

# ---------------------------------------------------------------------------
# Step 2: Verify source namespace has resources to back up
# ---------------------------------------------------------------------------
echo "[2/4] Checking namespace '${TARGET_NAMESPACE}'..."
POD_COUNT=$(kubectl get pods -n "${TARGET_NAMESPACE}" --no-headers 2>/dev/null | wc -l || echo "0")
echo "  Found ${POD_COUNT} pods in namespace '${TARGET_NAMESPACE}'"
if [[ "${POD_COUNT}" -eq 0 ]]; then
  echo "  WARNING: No pods found. Are you sure the OpenTelemetry demo is deployed?"
fi
echo ""

# ---------------------------------------------------------------------------
# Step 3: Create the Velero backup
# ---------------------------------------------------------------------------
# KEY FLAGS:
# --include-namespaces: Only back up the OpenTelemetry namespace (not the
#   entire cluster). This keeps the backup focused and fast.
# --default-volumes-to-fs-backup: Use file-system backup for all PVs.
#   This is critical because Azure managed disks can't be snapshot-copied
#   to T-Cloud. FSB copies the actual file data, which is portable.
# --ttl: Auto-cleanup after the specified duration.
# --wait: Block until the backup completes (useful for scripted workflows).
echo "[3/4] Creating Velero backup '${BACKUP_NAME}'..."
echo "  This may take several minutes depending on PV data size..."
echo ""
velero backup create "${BACKUP_NAME}" \
  --include-namespaces "${TARGET_NAMESPACE}" \
  --default-volumes-to-fs-backup \
  --ttl "${BACKUP_TTL}" \
  --wait

echo ""
echo "  ✓ Backup '${BACKUP_NAME}' created successfully"
echo ""

# ---------------------------------------------------------------------------
# Step 4: Verify the backup
# ---------------------------------------------------------------------------
echo "[4/4] Verifying backup status..."
velero backup describe "${BACKUP_NAME}" --details
echo ""
echo "=============================================="
echo " Backup Complete!"
echo "=============================================="
echo ""
echo "  Backup Name:  ${BACKUP_NAME}"
echo "  Status:       $(velero backup get "${BACKUP_NAME}" -o json 2>/dev/null | grep -o '"phase":"[^"]*"' | head -1 || echo 'Check manually')"
echo ""
echo "  Next Steps:"
echo "    1. Switch kubectl to the target CCE cluster"
echo "    2. Apply the storage class ConfigMap (change-storage-class.yaml)"
echo "    3. Run velero-restore.sh to restore the backup"
echo ""
echo "=============================================="
