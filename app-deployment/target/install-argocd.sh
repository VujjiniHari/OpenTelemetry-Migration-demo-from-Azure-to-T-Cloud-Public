#!/usr/bin/env bash
# =============================================================================
# install-argocd.sh — Install ArgoCD on the T-Cloud CCE Target Cluster
# =============================================================================
# This script installs a fresh ArgoCD instance on the T-Cloud CCE cluster.
# It mirrors the source cluster's ArgoCD setup but with T-Cloud-specific
# annotations for the Elastic Load Balancer (ELB).
#
# WHY A FRESH ARGOCD INSTALL (not migrated via Velero)?
# ArgoCD itself is infrastructure tooling, not application workload. We want
# a clean ArgoCD install on the target that points to T-Cloud SWR images.
# Migrating ArgoCD via Velero would carry over Azure-specific configuration
# that would break on T-Cloud.
#
# PREREQUISITES:
#   - kubectl configured to point at the CCE target cluster
#   - Helm 3.x installed
#   - CCE cluster has outbound internet access (via NAT Gateway)
#
# USAGE:
#   chmod +x install-argocd.sh
#   ./install-argocd.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ARGOCD_CHART_VERSION="5.51.6"
ARGOCD_NAMESPACE="argocd"

echo "=============================================="
echo " ArgoCD Installation — T-Cloud CCE Target Cluster"
echo "=============================================="
echo ""

# ---------------------------------------------------------------------------
# Step 1: Verify kubectl connectivity
# ---------------------------------------------------------------------------
echo "[1/5] Verifying kubectl connectivity to CCE cluster..."
if ! kubectl cluster-info &>/dev/null; then
  echo "ERROR: Cannot connect to the Kubernetes cluster."
  echo "Ensure KUBECONFIG is set to the CCE cluster's kubeconfig.json"
  exit 1
fi
echo "  ✓ Connected to cluster: $(kubectl config current-context)"
echo ""

# ---------------------------------------------------------------------------
# Step 2: Add the ArgoCD Helm repository
# ---------------------------------------------------------------------------
echo "[2/5] Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update
echo "  ✓ Helm repo 'argo' is up to date"
echo ""

# ---------------------------------------------------------------------------
# Step 3: Create the ArgoCD namespace
# ---------------------------------------------------------------------------
echo "[3/5] Creating namespace '${ARGOCD_NAMESPACE}'..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
echo "  ✓ Namespace '${ARGOCD_NAMESPACE}' ready"
echo ""

# ---------------------------------------------------------------------------
# Step 4: Install ArgoCD via Helm (with T-Cloud ELB annotations)
# ---------------------------------------------------------------------------
# KEY DIFFERENCE FROM AZURE:
# The LoadBalancer annotations are T-Cloud-specific. These annotations tell
# the CCE cloud-controller-manager to automatically provision a T-Cloud
# Elastic Load Balancer (ELB) with a public IP.
#
# T-Cloud ELB Annotation Breakdown:
# - kubernetes.io/elb.class: "union"
#     Specifies the ELB type. "union" is the recommended type for CCE.
# - kubernetes.io/elb.autocreate: JSON config for the ELB
#     - type: "public" → Internet-facing LB (vs. "inner" for private)
#     - bandwidth_name: Human-readable name for the EIP bandwidth
#     - bandwidth_chargemode: "traffic" → Pay per GB (cost-effective for demo)
#     - bandwidth_size: 5 → 5 Mbps (sufficient for demo dashboard)
#     - bandwidth_sharetype: "PER" → Dedicated bandwidth (not shared)
#     - eip_type: "5_bgp" → Dynamic BGP IP (most reliable option)
echo "[4/5] Installing ArgoCD v${ARGOCD_CHART_VERSION} with T-Cloud ELB..."

# Create a temporary values file for the T-Cloud-specific configuration
# WHY a values file (not --set): The ELB autocreate annotation contains
# nested JSON which is very hard to escape correctly with --set flags.
ARGOCD_VALUES=$(mktemp)
cat > "${ARGOCD_VALUES}" <<'EOF'
server:
  service:
    type: LoadBalancer
    annotations:
      # T-Cloud CCE ELB annotations — these trigger automatic provisioning
      # of a public Elastic Load Balancer by the CCE cloud controller.
      kubernetes.io/elb.class: "union"
      kubernetes.io/elb.autocreate: '{"type":"public","bandwidth_name":"argocd-bandwidth","bandwidth_chargemode":"traffic","bandwidth_size":5,"bandwidth_sharetype":"PER","eip_type":"5_bgp"}'
  extraArgs:
    - --insecure
EOF

helm upgrade --install argocd argo/argo-cd \
  --namespace "${ARGOCD_NAMESPACE}" \
  --version "${ARGOCD_CHART_VERSION}" \
  --values "${ARGOCD_VALUES}" \
  --timeout 600s \
  --wait

rm -f "${ARGOCD_VALUES}"
echo "  ✓ ArgoCD installed with T-Cloud ELB"
echo ""

# ---------------------------------------------------------------------------
# Step 5: Retrieve access credentials
# ---------------------------------------------------------------------------
echo "[5/5] Retrieving ArgoCD access details..."
sleep 5

ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d) || true

echo "  Waiting for T-Cloud ELB IP assignment (may take 2-3 minutes)..."
EXTERNAL_IP=""
for i in $(seq 1 36); do
  EXTERNAL_IP=$(kubectl get svc argocd-server -n "${ARGOCD_NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) || true
  if [[ -n "${EXTERNAL_IP}" ]]; then
    break
  fi
  sleep 10
done

echo ""
echo "=============================================="
echo " ArgoCD is Ready on T-Cloud!"
echo "=============================================="
echo ""
echo "  Dashboard URL:  http://${EXTERNAL_IP:-<pending>}"
echo "  Username:       admin"
echo "  Password:       ${ARGOCD_PASSWORD:-<retrieve manually>}"
echo ""
echo "  Next Step: Apply the target ArgoCD Application manifest:"
echo "    kubectl apply -f app-deployment/target/opentelemetry-app.yaml"
echo ""
echo "=============================================="
