#!/usr/bin/env bash
# =============================================================================
# traffic-simulator.sh — Live Traffic Simulator for Migration Demo
# =============================================================================
# This script continuously pings the OpenTelemetry frontend UI to prove that
# the application remains available during the migration process. It runs in
# the foreground and outputs timestamped HTTP status codes.
#
# WHY THIS MATTERS:
# During a real cloud migration, stakeholders need proof that the application
# experiences minimal or zero downtime. This script provides that evidence by
# continuously hitting the frontend endpoint and logging the results.
#
# HOW TO USE IN THE DEMO:
# 1. Start this script pointing at the AZURE Load Balancer IP
# 2. Perform the migration (registry sync, Velero backup/restore, ArgoCD repoint)
# 3. Update the TARGET_URL to the T-Cloud ELB IP (or use DNS cutover)
# 4. Show the audience that HTTP 200s continued throughout
#
# PREREQUISITES:
#   - curl installed
#   - The OpenTelemetry frontend accessible via a public IP or DNS name
#
# USAGE:
#   chmod +x traffic-simulator.sh
#   ./traffic-simulator.sh http://<AZURE_LB_IP>:8080
#   ./traffic-simulator.sh http://<TCLOUD_ELB_IP>:8080
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# The target URL is passed as the first argument. Default to localhost for
# local testing.
TARGET_URL="${1:-http://localhost:8080}"

# How often to send a request (in seconds).
# WHY 2 seconds: Frequent enough to detect short outages, but not so
# aggressive that it looks like a DDoS attack during the demo.
INTERVAL="${2:-2}"

# Request timeout in seconds. If the server doesn't respond within this
# window, we log it as a failure rather than hanging indefinitely.
TIMEOUT=5

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo "=============================================="
echo " Live Traffic Simulator"
echo "=============================================="
echo ""
echo "  Target:    ${TARGET_URL}"
echo "  Interval:  ${INTERVAL}s"
echo "  Timeout:   ${TIMEOUT}s"
echo ""
echo "  Press Ctrl+C to stop"
echo ""
echo "  Timestamp               | Status | Latency  | Result"
echo "  ------------------------+--------+----------+--------"

# ---------------------------------------------------------------------------
# Counters for summary statistics
# ---------------------------------------------------------------------------
TOTAL=0
SUCCESS=0
FAIL=0

# ---------------------------------------------------------------------------
# Cleanup handler — display summary when the script is stopped
# ---------------------------------------------------------------------------
# WHY trap: When the presenter hits Ctrl+C during the demo, we want to show
# a summary of results (total requests, success rate) rather than just dying.
cleanup() {
  echo ""
  echo "=============================================="
  echo " Traffic Simulation Summary"
  echo "=============================================="
  echo ""
  if [[ ${TOTAL} -gt 0 ]]; then
    SUCCESS_RATE=$(echo "scale=1; ${SUCCESS} * 100 / ${TOTAL}" | bc 2>/dev/null || echo "N/A")
    echo "  Total Requests:  ${TOTAL}"
    echo "  Successful:      ${SUCCESS} (HTTP 200)"
    echo "  Failed:          ${FAIL}"
    echo "  Success Rate:    ${SUCCESS_RATE}%"
  else
    echo "  No requests were sent."
  fi
  echo ""
  echo "=============================================="
  exit 0
}
trap cleanup SIGINT SIGTERM

# ---------------------------------------------------------------------------
# Main loop — continuously ping the target URL
# ---------------------------------------------------------------------------
# Each iteration:
# 1. Records the current timestamp
# 2. Sends an HTTP GET request with a timeout
# 3. Captures the HTTP status code and response time
# 4. Logs the result in a formatted table row
# 5. Sleeps for the configured interval
while true; do
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  TOTAL=$((TOTAL + 1))

  # Use curl's write-out feature to capture HTTP status code and timing.
  # -s: Silent mode (no progress bar)
  # -o /dev/null: Discard the response body (we only care about status)
  # -w: Write out the HTTP code and timing info
  # --connect-timeout: Fail fast if TCP connection can't be established
  # --max-time: Total request timeout
  HTTP_RESPONSE=$(curl -s -o /dev/null \
    -w "%{http_code}|%{time_total}" \
    --connect-timeout "${TIMEOUT}" \
    --max-time "${TIMEOUT}" \
    "${TARGET_URL}" 2>/dev/null) || HTTP_RESPONSE="000|0.000"

  # Parse the response into status code and latency
  HTTP_CODE=$(echo "${HTTP_RESPONSE}" | cut -d'|' -f1)
  LATENCY=$(echo "${HTTP_RESPONSE}" | cut -d'|' -f2)

  # Determine result label and update counters
  if [[ "${HTTP_CODE}" == "200" ]]; then
    RESULT="✓ OK"
    SUCCESS=$((SUCCESS + 1))
  elif [[ "${HTTP_CODE}" == "000" ]]; then
    RESULT="✗ TIMEOUT"
    FAIL=$((FAIL + 1))
  else
    RESULT="✗ ERROR"
    FAIL=$((FAIL + 1))
  fi

  # Output formatted result line
  printf "  %s | %s    | %ss | %s\n" "${TIMESTAMP}" "${HTTP_CODE}" "${LATENCY}" "${RESULT}"

  sleep "${INTERVAL}"
done
