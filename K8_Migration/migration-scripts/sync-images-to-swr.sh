#!/usr/bin/env bash
# =============================================================================
# sync-images-to-swr.sh — Container Registry Sync (ghcr.io → SWR)
# =============================================================================
# Copies all OpenTelemetry demo images from their public source registries to
# T-Cloud SWR using skopeo copy (no docker daemon pull/tag/push needed).
#
# WHY skopeo copy instead of docker pull/tag/push:
#   - skopeo copies directly registry-to-registry without storing locally
#   - No docker daemon authentication issues
#   - Faster (streams directly between registries)
#   - Works even when docker login to source registry fails
#
# WHY sync to SWR:
#   When CCE pulls images, it goes to SWR first (same region, fast, no egress).
#   Without this sync the CCE cluster would pull from public internet registries
#   on every pod start — slower and subject to rate limits.
#
# IMAGE TAG FORMAT (important):
#   OTel demo images use a flat tag format: ghcr.io/open-telemetry/demo:VERSION-SERVICE
#   NOT: ghcr.io/open-telemetry/demo/SERVICE:VERSION
#   This was discovered by inspecting running pods on the source AKS cluster.
#
# PREREQUISITES:
#   - skopeo installed (sudo apt-get install -y skopeo)
#   - docker login swr.eu-de.otc.t-systems.com already completed (via console)
#   - Environment variables sourced from .env
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SWR_REGISTRY="${SWR_REGISTRY:-swr.eu-de.otc.t-systems.com}"
SWR_ORG="${SWR_ORG:-otel-migration-demo}"
OTEL_VERSION="${OTEL_VERSION:-1.11.1}"

# SWR auth file — skopeo reads docker credentials from this file
DOCKER_AUTH="${HOME}/.docker/config.json"

echo "=============================================="
echo " Container Registry Sync: Public → SWR"
echo "=============================================="
echo ""
echo "  Target Registry:  ${SWR_REGISTRY}/${SWR_ORG}"
echo "  OTel Version:     ${OTEL_VERSION}"
echo ""

# Verify SWR login exists
if ! grep -q "${SWR_REGISTRY}" "${DOCKER_AUTH}" 2>/dev/null; then
  echo "✗ Not logged in to ${SWR_REGISTRY}"
  echo "  Run the login command from the T-Cloud SWR console first."
  exit 1
fi
echo "✓ SWR credentials found"
echo ""

# ---------------------------------------------------------------------------
# Image list — sourced from running AKS pods (kubectl get pods -o jsonpath)
# ---------------------------------------------------------------------------
# Format: "SOURCE_IMAGE TARGET_NAME TARGET_TAG"
# OTel demo uses flat tag: ghcr.io/open-telemetry/demo:VERSION-SERVICE
# Third-party images are synced as-is with their original tag.
# ---------------------------------------------------------------------------
declare -a IMAGES=(
  # OTel Astronomy Shop microservices (ghcr.io flat-tag format)
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-accountingservice     accountingservice    ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-adservice             adservice            ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-cartservice           cartservice          ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-checkoutservice       checkoutservice      ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-currencyservice       currencyservice      ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-emailservice          emailservice         ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-frauddetectionservice frauddetectionservice ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-frontend              frontend             ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-frontendproxy         frontendproxy        ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-imageprovider         imageprovider        ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-kafka                 kafka                ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-loadgenerator         loadgenerator        ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-paymentservice        paymentservice       ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-productcatalogservice productcatalogservice ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-quoteservice          quoteservice         ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-recommendationservice recommendationservice ${OTEL_VERSION}"
  "ghcr.io/open-telemetry/demo:${OTEL_VERSION}-shippingservice       shippingservice      ${OTEL_VERSION}"
  # Third-party dependencies (discovered from kubectl get pods -o jsonpath images)
  "ghcr.io/open-feature/flagd:v0.11.1                                flagd                v0.11.1"
  "docker.io/grafana/grafana:11.1.0                                   grafana              11.1.0"
  "jaegertracing/all-in-one:1.53.0                                    jaeger               1.53.0"
  "opensearchproject/opensearch:2.15.0                                opensearch           2.15.0"
  "otel/opentelemetry-collector-contrib:0.108.0                       otelcol              0.108.0"
  "quay.io/prometheus/prometheus:v2.53.1                              prometheus           v2.53.1"
  "valkey/valkey:7.2-alpine                                           valkey               7.2-alpine"
)

TOTAL=${#IMAGES[@]}
SUCCESS=0
FAILED=0

echo "Syncing ${TOTAL} images..."
echo ""

for entry in "${IMAGES[@]}"; do
  # Parse the three fields (extra whitespace between them is intentional for readability)
  read -r SRC TARGET_NAME TARGET_TAG <<< "$entry"
  DEST="${SWR_REGISTRY}/${SWR_ORG}/${TARGET_NAME}:${TARGET_TAG}"

  echo "--------------------------------------------"
  echo "  ${TARGET_NAME}:${TARGET_TAG}"
  echo "    From: ${SRC}"
  echo "    To:   ${DEST}"

  if skopeo copy \
    --dest-authfile "${DOCKER_AUTH}" \
    "docker://${SRC}" \
    "docker://${DEST}" 2>&1 | tail -1; then
    echo "    ✓ Synced"
    (( SUCCESS++ )) || true
  else
    echo "    ✗ Failed"
    (( FAILED++ )) || true
  fi
done

echo ""
echo "=============================================="
echo " Sync Complete!"
echo "=============================================="
echo ""
echo "  Successfully synced: ${SUCCESS}/${TOTAL}"
echo "  Failed:              ${FAILED}"
echo ""
if [[ $FAILED -gt 0 ]]; then
  echo "  ⚠ Some images failed. Check network and SWR credentials."
else
  echo "  ✓ All images available at:"
  echo "    ${SWR_REGISTRY}/${SWR_ORG}/<image>:<tag>"
fi
echo "=============================================="
