#!/usr/bin/env bash
# =============================================================================
# dns-cutover.sh — DNS/Traffic Cutover from Azure to T-Cloud
# =============================================================================
# This script assists with the final cutover step of the migration: redirecting
# live traffic from the Azure Load Balancer to the T-Cloud Elastic Load Balancer.
#
# IN A REAL-WORLD SCENARIO:
# You would update a DNS record (e.g., app.example.com) to point from the
# Azure LB IP to the T-Cloud ELB IP. With a low TTL, this provides a
# near-zero-downtime cutover.
#
# FOR THIS DEMO:
# Since we're using raw IPs (not DNS names), this script:
# 1. Retrieves the Azure LB IP (source) and T-Cloud ELB IP (target)
# 2. Validates both endpoints are responding
# 3. Provides the presenter with the new IP to use
# 4. Updates the traffic simulator to point at the new target
#
# PREREQUISITES:
#   - kubectl access to BOTH clusters (via separate kubeconfig files)
#   - The OpenTelemetry demo deployed and healthy on BOTH clusters
#
# USAGE:
#   chmod +x dns-cutover.sh
#   ./dns-cutover.sh <azure-kubeconfig> <cce-kubeconfig>
#
#   Example:
#   ./dns-cutover.sh ~/.kube/aks-config ~/.kube/cce-config
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
AKS_KUBECONFIG="${1:-}"
CCE_KUBECONFIG="${2:-}"
OTEL_NAMESPACE="opentelemetry"
FRONTEND_SERVICE="opentelemetry-demo-frontendproxy"

if [[ -z "${AKS_KUBECONFIG}" || -z "${CCE_KUBECONFIG}" ]]; then
  echo "Usage: $0 <azure-kubeconfig-path> <cce-kubeconfig-path>"
  echo ""
  echo "Example:"
  echo "  $0 ~/.kube/aks-config ~/.kube/cce-config"
  exit 1
fi

echo "=============================================="
echo " DNS / Traffic Cutover: Azure → T-Cloud"
echo "=============================================="
echo ""

# ---------------------------------------------------------------------------
# Step 1: Get the Azure (Source) Load Balancer IP
# ---------------------------------------------------------------------------
echo "[1/4] Retrieving Azure Load Balancer IP..."
AZURE_IP=$(KUBECONFIG="${AKS_KUBECONFIG}" kubectl get svc "${FRONTEND_SERVICE}" \
  -n "${OTEL_NAMESPACE}" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) || AZURE_IP=""

if [[ -n "${AZURE_IP}" ]]; then
  echo "  ✓ Azure LB IP:  ${AZURE_IP}"
else
  echo "  ✗ Could not retrieve Azure LB IP"
  echo "    Check: KUBECONFIG=${AKS_KUBECONFIG} kubectl get svc -n ${OTEL_NAMESPACE}"
fi
echo ""

# ---------------------------------------------------------------------------
# Step 2: Get the T-Cloud (Target) ELB IP
# ---------------------------------------------------------------------------
echo "[2/4] Retrieving T-Cloud ELB IP..."
TCLOUD_IP=$(KUBECONFIG="${CCE_KUBECONFIG}" kubectl get svc "${FRONTEND_SERVICE}" \
  -n "${OTEL_NAMESPACE}" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) || TCLOUD_IP=""

if [[ -n "${TCLOUD_IP}" ]]; then
  echo "  ✓ T-Cloud ELB IP:  ${TCLOUD_IP}"
else
  echo "  ✗ Could not retrieve T-Cloud ELB IP"
  echo "    Check: KUBECONFIG=${CCE_KUBECONFIG} kubectl get svc -n ${OTEL_NAMESPACE}"
fi
echo ""

# ---------------------------------------------------------------------------
# Step 3: Validate both endpoints are responding
# ---------------------------------------------------------------------------
echo "[3/4] Validating endpoint health..."

# Check Azure endpoint
if [[ -n "${AZURE_IP}" ]]; then
  AZURE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://${AZURE_IP}:8080" 2>/dev/null) || AZURE_STATUS="000"
  echo "  Azure  (http://${AZURE_IP}:8080):   HTTP ${AZURE_STATUS}"
else
  echo "  Azure:  SKIPPED (no IP)"
fi

# Check T-Cloud endpoint
if [[ -n "${TCLOUD_IP}" ]]; then
  TCLOUD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://${TCLOUD_IP}:8080" 2>/dev/null) || TCLOUD_STATUS="000"
  echo "  T-Cloud (http://${TCLOUD_IP}:8080):  HTTP ${TCLOUD_STATUS}"
else
  echo "  T-Cloud: SKIPPED (no IP)"
fi
echo ""

# ---------------------------------------------------------------------------
# Step 4: Cutover instructions
# ---------------------------------------------------------------------------
echo "[4/4] Cutover Instructions"
echo ""
echo "=============================================="
echo " CUTOVER SUMMARY"
echo "=============================================="
echo ""
echo "  OLD (Azure):   http://${AZURE_IP:-<unknown>}:8080"
echo "  NEW (T-Cloud): http://${TCLOUD_IP:-<unknown>}:8080"
echo ""
echo "  ─────────────────────────────────────────────"
echo "  FOR THE DEMO (IP-based cutover):"
echo "  ─────────────────────────────────────────────"
echo ""
echo "  1. Stop the traffic simulator pointing at Azure:"
echo "     (Ctrl+C in the traffic-simulator terminal)"
echo ""
echo "  2. Restart the traffic simulator pointing at T-Cloud:"
echo "     ./migration-scripts/traffic-simulator.sh http://${TCLOUD_IP:-<TCLOUD_IP>}:8080"
echo ""
echo "  3. Open the T-Cloud frontend in your browser:"
echo "     http://${TCLOUD_IP:-<TCLOUD_IP>}:8080"
echo ""
echo "  ─────────────────────────────────────────────"
echo "  FOR PRODUCTION (DNS-based cutover):"
echo "  ─────────────────────────────────────────────"
echo ""
echo "  1. Before migration, set DNS TTL to 60 seconds:"
echo "     app.example.com  A  ${AZURE_IP:-<AZURE_IP>}  TTL=60"
echo ""
echo "  2. After verifying T-Cloud app health, update DNS:"
echo "     app.example.com  A  ${TCLOUD_IP:-<TCLOUD_IP>}  TTL=60"
echo ""
echo "  3. Wait for TTL expiration (60s), then verify:"
echo "     dig app.example.com"
echo "     curl -I http://app.example.com:8080"
echo ""
echo "  4. Once stable, increase TTL back to normal (3600s)."
echo ""
echo "=============================================="
