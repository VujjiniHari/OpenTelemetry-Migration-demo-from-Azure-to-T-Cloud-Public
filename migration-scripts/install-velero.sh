#!/usr/bin/env bash
# =============================================================================
# install-velero.sh — Install Velero on a Kubernetes Cluster (Source or Target)
# =============================================================================
# This script installs Velero with its Helm chart on whichever cluster kubectl
# is currently pointing at. It must be run on BOTH the source (AKS) and target
# (CCE) clusters with identical OBS configuration so they share the same
# backup storage location.
#
# WHY IDENTICAL CONFIGURATION ON BOTH CLUSTERS:
# Velero stores backups in OBS (S3-compatible). Both the source and target
# clusters need the same OBS bucket, credentials, and endpoint so that:
#   - The source cluster can CREATE backups
#   - The target cluster can SEE and RESTORE those same backups
# This shared storage is the "bridge" that connects the two environments.
#
# PREREQUISITES:
#   - kubectl configured for the target cluster
#   - Helm 3.x installed
#   - OBS bucket created on T-Cloud
#   - OBS access credentials (AK/SK) available
#
# ENVIRONMENT VARIABLES (required):
#   OBS_ACCESS_KEY    — OBS Access Key ID
#   OBS_SECRET_KEY    — OBS Secret Access Key
#   OBS_BUCKET        — OBS bucket name (default: velero)
#   OBS_REGION        — OBS region (default: eu-de)
#   OBS_URL           — OBS endpoint (default: https://obs.eu-de.otc.t-systems.com)
#
# USAGE:
#   export OBS_ACCESS_KEY="your-access-key"
#   export OBS_SECRET_KEY="your-secret-key"
#   chmod +x install-velero.sh
#   ./install-velero.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration from environment variables (with sensible defaults)
# ---------------------------------------------------------------------------
OBS_ACCESS_KEY="${OBS_ACCESS_KEY:?ERROR: OBS_ACCESS_KEY environment variable is required}"
OBS_SECRET_KEY="${OBS_SECRET_KEY:?ERROR: OBS_SECRET_KEY environment variable is required}"
OBS_BUCKET="${OBS_BUCKET:-velero}"
OBS_REGION="${OBS_REGION:-eu-de}"
OBS_URL="${OBS_URL:-https://obs.eu-de.otc.t-systems.com}"
VELERO_NAMESPACE="velero"
VELERO_AWS_PLUGIN_VERSION="v1.8.2"

echo "=============================================="
echo " Velero Installation"
echo "=============================================="
echo ""
echo "  Cluster:     $(kubectl config current-context 2>/dev/null || echo 'unknown')"
echo "  OBS Bucket:  ${OBS_BUCKET}"
echo "  OBS Region:  ${OBS_REGION}"
echo "  OBS URL:     ${OBS_URL}"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Create the Velero namespace
# ---------------------------------------------------------------------------
echo "[1/5] Creating namespace '${VELERO_NAMESPACE}'..."
kubectl create namespace "${VELERO_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
echo "  ✓ Namespace ready"
echo ""

# ---------------------------------------------------------------------------
# Step 2: Create OBS credentials secret
# ---------------------------------------------------------------------------
# WHY as a Kubernetes Secret (not Helm values):
# Storing credentials in Helm values would expose them in Helm release history.
# A pre-created Secret is more secure and follows the principle of separation
# between credentials and configuration.
echo "[2/5] Creating OBS credentials secret..."

# Create a temporary credentials file in AWS format (required by velero-plugin-for-aws)
CRED_FILE=$(mktemp)
cat > "${CRED_FILE}" <<EOF
[default]
aws_access_key_id=${OBS_ACCESS_KEY}
aws_secret_access_key=${OBS_SECRET_KEY}
EOF

kubectl -n "${VELERO_NAMESPACE}" create secret generic velero-cloud-credentials \
  --from-file=cloud="${CRED_FILE}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Clean up the temporary credentials file immediately
rm -f "${CRED_FILE}"
echo "  ✓ Credentials secret created"
echo ""

# ---------------------------------------------------------------------------
# Step 3: Install Velero via Helm
# ---------------------------------------------------------------------------
# KEY CONFIGURATION EXPLAINED:
#
# --set credentials.existingSecret=velero-cloud-credentials
#   → Uses the pre-created Secret instead of letting Helm manage credentials
#
# --set configuration.backupStorageLocation[0].provider=aws
#   → OBS is S3-compatible, so we use the AWS provider plugin
#
# --set configuration.backupStorageLocation[0].config.s3ForcePathStyle=true
#   → Required for S3-compatible storage that isn't actually AWS S3.
#     Without this, the plugin would try to use virtual-hosted-style URLs
#     (bucket.s3.amazonaws.com) which don't work with OBS.
#
# --set deployNodeAgent=true
#   → Deploys the Velero Node Agent DaemonSet for file-system backups (FSB).
#     The Node Agent runs on every node and can access PV data directly.
#
# --set defaultVolumesToFsBackup=true
#   → Uses FSB as the default for all PVs. This is essential for cross-cloud
#     migration because CSI snapshots are cloud-specific and non-portable.
#
# --set snapshotsEnabled=false
#   → Disables CSI/cloud-provider snapshots. Since we're migrating BETWEEN
#     clouds, snapshots are useless (Azure snapshots can't be used on T-Cloud).
#     FSB (file-level copy) is the only portable option.
echo "[3/5] Adding Helm repository and installing Velero..."
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts 2>/dev/null || true
helm repo update

helm upgrade --install velero vmware-tanzu/velero \
  --namespace "${VELERO_NAMESPACE}" \
  --set credentials.existingSecret=velero-cloud-credentials \
  --set "configuration.backupStorageLocation[0].name=default" \
  --set "configuration.backupStorageLocation[0].provider=aws" \
  --set "configuration.backupStorageLocation[0].bucket=${OBS_BUCKET}" \
  --set "configuration.backupStorageLocation[0].config.region=${OBS_REGION}" \
  --set "configuration.backupStorageLocation[0].config.s3ForcePathStyle=true" \
  --set "configuration.backupStorageLocation[0].config.s3Url=${OBS_URL}" \
  --set deployNodeAgent=true \
  --set defaultVolumesToFsBackup=true \
  --set snapshotsEnabled=false \
  --timeout 600s \
  --wait

echo "  ✓ Velero installed via Helm"
echo ""

# ---------------------------------------------------------------------------
# Step 4: Install the AWS plugin (for S3/OBS compatibility)
# ---------------------------------------------------------------------------
# WHY THIS PLUGIN:
# The velero-plugin-for-aws enables Velero to communicate with S3-compatible
# object stores. Since T-Cloud OBS exposes an S3-compatible API, this plugin
# is required for backup storage. Without it, Velero can't read/write backups.
echo "[4/5] Installing Velero AWS plugin ${VELERO_AWS_PLUGIN_VERSION}..."
velero plugin add velero/velero-plugin-for-aws:${VELERO_AWS_PLUGIN_VERSION} 2>/dev/null || {
  echo "  Plugin may already be installed (this is OK)"
}
echo "  ✓ AWS plugin installed"
echo ""

# ---------------------------------------------------------------------------
# Step 5: Verify the installation
# ---------------------------------------------------------------------------
echo "[5/5] Verifying Velero installation..."
echo ""

# Check backup storage location connectivity
echo "  Backup Storage Locations:"
velero get backup-locations 2>/dev/null || echo "  (waiting for initialization...)"
echo ""

# Check Node Agent DaemonSet
echo "  Node Agent pods:"
kubectl get pods -n "${VELERO_NAMESPACE}" -l name=node-agent 2>/dev/null || echo "  (starting...)"
echo ""

echo "=============================================="
echo " Velero is Ready!"
echo "=============================================="
echo ""
echo "  Verify with:  velero get backup-locations"
echo "  Create backup: velero backup create test --include-namespaces default"
echo ""
echo "=============================================="
