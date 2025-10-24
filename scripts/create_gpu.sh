#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/create_gpu.sh --region <REGION> --plan <PLAN_ID> --os <OS_ID> --label <LABEL> --sshkeys "id1,id2"
#
# Requirements:
#   - Env: VULTR_API_KEY
#   - Tools: curl, jq
#
# Notes:
#   - Creates the instance via REST API and polls until it's active + has a public IP.
#   - Writes instance-<ID>.json to the current directory.
#   - Works regardless of vultr-cli version (does not rely on CLI JSON flags).

# ---------- parse args ----------
REGION=""
PLAN=""
OS=""
LABEL="gpu-from-actions"
SSHKEYS=""   # comma-separated Vultr SSH Key IDs

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="$2"; shift 2;;
    --plan) PLAN="$2"; shift 2;;
    --os) OS="$2"; shift 2;;
    --label) LABEL="$2"; shift 2;;
    --sshkeys) SSHKEYS="$2"; shift 2;;
    *) echo "Unrecognized argument: $1" >&2; exit 1;;
  esac
done

# ---------- validations ----------
if [[ -z "${VULTR_API_KEY:-}" ]]; then
  echo "ERROR: VULTR_API_KEY is not set" >&2; exit 1
fi
if [[ -z "${REGION}" || -z "${PLAN}" || -z "${OS}" ]]; then
  echo "ERROR: Missing required --region / --plan / --os" >&2; exit 1
fi
if ! [[ "${OS}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --os must be a numeric OS ID (e.g., 215 or 477). Got: '${OS}'" >&2
  exit 1
fi

# ---------- build payload (jq 1.5/1.6 safe) ----------
# Build ssh_key_ids as JSON array (or [] if empty)
jq_keys_array='[]'
if [[ -n "${SSHKEYS}" ]]; then
  jq_keys_array=$(jq -Rn --arg s "$SSHKEYS" '$s|split(",")|map(select(length>0))')
fi

# Build payload; delete ssh_key_ids if it's empty
payload=$(
  jq -n \
    --arg region "$REGION" \
    --arg plan "$PLAN" \
    --arg label "$LABEL" \
    --argjson os_id "$OS" \
    --argjson ssh_key_ids "$jq_keys_array" '
{
  region: $region,
  plan:   $plan,
  os_id:  $os_id,
  label:  $label,
  ssh_key_ids: $ssh_key_ids
}
| if (.ssh_key_ids | length) == 0 then del(.ssh_key_ids) else . end
'
)

echo "Creating GPU instance on Vultr (region=${REGION}, plan=${PLAN}, os=${OS})..."

# ---------- POST /v2/instances ----------
create_resp=$(curl -sS -X POST "https://api.vultr.com/v2/instances" \
  -H "Authorization: Bearer ${VULTR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$payload")

# Extract instance id or show error
INSTANCE_ID=$(echo "$create_resp" | jq -r '.instance.id // empty')
if [[ -z "$INSTANCE_ID" ]]; then
  echo "ERROR: Failed to create instance. API response:" >&2
  echo "$create_resp" | jq . >&2
  exit 1
fi
echo "Instance ID: $INSTANCE_ID"

# ---------- poll until active + has IP ----------
echo "Waiting for the instance to become active and get a public IP (up to ~10 minutes)..."
for i in {1..60}; do
  info=$(curl -sS -X GET "https://api.vultr.com/v2/instances/${INSTANCE_ID}" \
    -H "Authorization: Bearer ${VULTR_API_KEY}")
  status=$(echo "$info" | jq -r '.instance.status // empty')
  ip=$(echo "$info" | jq -r '.instance.main_ip // empty')
  if [[ "$status" == "active" && -n "$ip" && "$ip" != "0.0.0.0" ]]; then
    break
  fi
  sleep 10
done

# ---------- fetch final object, save file, print summary ----------
final=$(curl -sS -X GET "https://api.vultr.com/v2/instances/${INSTANCE_ID}" \
  -H "Authorization: Bearer ${VULTR_API_KEY}")

echo "$final" | jq '.instance' > "instance-${INSTANCE_ID}.json"

label_out=$(echo "$final" | jq -r '.instance.label // empty')
region_name=$(echo "$final" | jq -r '.instance.region // empty')
ip=$(echo "$final" | jq -r '.instance.main_ip // empty')

echo "Instance is active:"
echo " - ID: ${INSTANCE_ID}"
echo " - Label: ${label_out}"
echo " - Region: ${region_name}"
echo " - IP: ${ip}"

# ---------- GitHub Actions outputs (ignored locally) ----------
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "instance_id=${INSTANCE_ID}"
    echo "ip=${ip}"
  } >> "$GITHUB_OUTPUT"
fi

