#!/usr/bin/env bash
set -euo pipefail

REGION="${1:-ewr}"   # allow overriding: ./list_helpers.sh fra

echo "== Regions =="
vultr-cli regions list || true
echo

echo "== Operating Systems (common IDs) =="
vultr-cli os list | head -n 50 || true
echo "Tip: Ubuntu 22.04 is often 215; Ubuntu 24.04 is often 477 (verify with the command)."
echo

echo "== GPU-capable plans available in region: ${REGION} =="
vultr-cli regions availability "${REGION}" --type gpu || true

echo
echo "Use one of the Plan IDs above with:"
echo "  --region ${REGION} --plan <PLAN_ID> --os <OS_ID>"

