#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/destroy_gpu.sh <INSTANCE_ID>
#
# Requirements:
#   - Env: VULTR_API_KEY
#   - Tools: curl

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <INSTANCE_ID>" >&2
  exit 1
fi
if [[ -z "${VULTR_API_KEY:-}" ]]; then
  echo "ERROR: VULTR_API_KEY is not set" >&2
  exit 1
fi

INSTANCE_ID="$1"

echo "Destroying instance ${INSTANCE_ID}..."
resp_code=$(curl -sS -o /dev/null -w "%{http_code}" -X DELETE \
  "https://api.vultr.com/v2/instances/${INSTANCE_ID}" \
  -H "Authorization: Bearer ${VULTR_API_KEY}")

if [[ "$resp_code" != "204" ]]; then
  echo "ERROR: Unexpected HTTP $resp_code while deleting ${INSTANCE_ID}" >&2
  exit 1
fi

echo "Done."

