#!/usr/bin/env bash
set -euo pipefail

# Usage:
# ./scripts/destroy_gpu.sh <INSTANCE_ID>

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <INSTANCE_ID>" >&2
  exit 1
fi

INSTANCE_ID="$1"

echo "Destroying instance ${INSTANCE_ID}..."
vultr-cli instance delete --id "${INSTANCE_ID}"
echo "Done."
