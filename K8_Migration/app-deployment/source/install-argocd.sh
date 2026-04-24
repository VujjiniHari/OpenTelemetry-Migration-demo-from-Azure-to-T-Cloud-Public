#!/usr/bin/env bash
# =============================================================================
# install-argocd.sh — Install ArgoCD on the Azure AKS Source Cluster
# =============================================================================
# This script installs ArgoCD onto the AKS cluster using its official Helm
# chart. ArgoCD provides GitOps-based continuous delivery, which means the
# OpenTelemetry demo app will be deployed and managed declaratively.
#
# WHY ArgoCD (not Flux or plain kubectl apply)?
# - ArgoCD provides a visual dashboard that makes the demo more compelling
# - It demonstrates a production-grade GitOps workflow
# - The same ArgoCD pattern will be replicated on T-Cloud CCE, showing
#   how GitOps makes multi-cloud migrations seamless
#
# PREREQUISITES:
#   - kubectl configured to point at the AKS cluster
#   - Helm 3.x installed
#   - Active internet connection (to pull the Helm chart)
#
# USAGE:
#   chmod +x install-argocd.sh
#   ./install-argocd.sh
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# ArgoCD Helm chart version — pinned for reproducibility.
# Check https://github.com/argoproj/argo-helm/releases for latest version.
ARGOCD_CHART_VERSION="5.51.6"
ARGOCD_NAMESPACE="argocd"

echo "=============================================="
echo " ArgoCD Installation — Azure AKS Source Cluster"
echo "=============================================="
echo ""

# ---------------------------------------------------------------------------
# Step 1: Verify kubectl connectivity
# ---------------------------------------------------------------------------
# Before installing anything, confirm we can reach the AKS cluster.
# This catches common issues like expired credentials or wrong context.
echo "[1/5] Verifying kubectl connectivity..."
if ! kubectl cluster-info &>/dev/null; then
  echo "ERROR: Cannot connect to the Kubernetes cluster."
  echo "Run: az aks get-credentials --resource-group <RG> --name <CLUSTER>"
  exit 1
fi
echo "  ✓ Connected to cluster: $(kubectl config current-context)"
echo ""

# ---------------------------------------------------------------------------
# Step 2: Add the ArgoCD Helm repository
# ---------------------------------------------------------------------------
# The official Argo Helm repo contains the argo-cd chart along with other
# Argo project charts (Argo Workflows, Argo Events, etc.)
echo "[2/5] Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update
echo "  ✓ Helm repo 'argo' is up to date"
echo ""

# ---------------------------------------------------------------------------
# Step 3: Create the ArgoCD namespace
# ---------------------------------------------------------------------------
# We create the namespace separately (rather than letting Helm do it) so we
# have explicit control and can verify it exists before installation.
echo "[3/5] Creating namespace '${ARGOCD_NAMESPACE}'..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
echo "  ✓ Namespace '${ARGOCD_NAMESPACE}' ready"
echo ""

# ---------------------------------------------------------------------------
# Step 4: Install ArgoCD via Helm
# ---------------------------------------------------------------------------
# KEY CONFIGURATION:
# - server.service.type=LoadBalancer: Exposes the ArgoCD UI via an Azure
#   Standard Load Balancer with a public IP. This is essential for the demo
#   so the presenter can access ArgoCD's web dashboard.
# - server.extraArgs=--insecure: Disables TLS on the ArgoCD server itself.
#   In production you'd use a proper TLS cert, but for a demo this avoids
#   certificate warnings and simplifies access.
# - The health probe annotation is required by Azure's Standard LB to
#   correctly determine the backend health of the ArgoCD server pod.
echo "[4/5] Installing ArgoCD v${ARGOCD_CHART_VERSION} via Helm..."
helm upgrade --install argocd argo/argo-cd \
  --namespace "${ARGOCD_NAMESPACE}" \
  --version "${ARGOCD_CHART_VERSION}" \
  --set server.service.type=LoadBalancer \
  --set "server.service.annotations.service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path=/healthz" \
  --set server.extraArgs="{--insecure}" \
  --timeout 600s \
  --wait
echo "  ✓ ArgoCD installed successfully"
echo ""

# ---------------------------------------------------------------------------
# Step 5: Retrieve access credentials
# ---------------------------------------------------------------------------
# ArgoCD generates a random initial admin password stored as a Kubernetes
# secret. We decode and display it here for convenience.
echo "[5/5] Retrieving ArgoCD access details..."
echo ""

# Wait briefly for the secret to be created by the ArgoCD server
sleep 5

ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d) || true

# Get the LoadBalancer external IP (may take a minute for Azure to assign)
echo "  Waiting for LoadBalancer IP assignment (this may take 1-2 minutes)..."
EXTERNAL_IP=""
for i in $(seq 1 30); do
  EXTERNAL_IP=$(kubectl get svc argocd-server -n "${ARGOCD_NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) || true
  if [[ -n "${EXTERNAL_IP}" ]]; then
    break
  fi
  sleep 10
done

echo ""
echo "=============================================="
echo " ArgoCD is Ready!"
echo "=============================================="
echo ""
echo "  Dashboard URL:  http://${EXTERNAL_IP:-<pending>}"
echo "  Username:       admin"
echo "  Password:       ${ARGOCD_PASSWORD:-<retrieve manually>}"
echo ""
echo "  If the IP is still pending, check with:"
echo "    kubectl get svc argocd-server -n ${ARGOCD_NAMESPACE}"
echo ""
echo "  To retrieve the password later:"
echo "    kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret \\"
echo "      -o jsonpath=\"{.data.password}\" | base64 -d && echo"
echo "=============================================="
