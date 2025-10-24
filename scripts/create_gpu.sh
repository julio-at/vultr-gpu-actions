#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/create_gpu.sh \
#     --region <REGION> \
#     --plan <PLAN_ID> \
#     --os <OS_ID> \
#     --label <LABEL> \
#     [--sshkeys "id1,id2"] \
#     [--sshpub "<ssh-rsa AAAA... user@host>"] \
#     [--sshpubfile </path/to/key.pub>]
#
# What it does:
#   - Creates a Vultr instance via REST API
#   - Polls until the instance is active and has a public IP
#   - Writes instance-<ID>.json to the current directory
#   - Ensures SSH key injection by:
#       * Passing ssh_key_ids (if provided), and/or
#       * Injecting the public key via cloud-init user_data (root + ubuntu)
#
# Requirements:
#   - Env: VULTR_API_KEY
#   - Tools: curl, jq, base64

# ------------------- Parse args -------------------
REGION=""
PLAN=""
OS=""
LABEL="gpu-from-actions"
SSHKEYS=""      # Vultr SSH Key IDs (comma-separated): e.g. "ssh-aaaa,ssh-bbbb"
SSHPUB=""       # literal public key text: e.g. "$(cat ~/.ssh/id_ed25519.pub)"
SSHPUBFILE=""   # path to a .pub file

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="$2"; shift 2;;
    --plan) PLAN="$2"; shift 2;;
    --os) OS="$2"; shift 2;;
    --label) LABEL="$2"; shift 2;;
    --sshkeys) SSHKEYS="$2"; shift 2;;
    --sshpub) SSHPUB="$2"; shift 2;;
    --sshpubfile) SSHPUBFILE="$2"; shift 2;;
    *) echo "Unrecognized argument: $1" >&2; exit 1;;
  esac
done

# ------------------- Validations -------------------
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

# ------------------- Load public key (file wins) -------------------
if [[ -n "$SSHPUBFILE" ]]; then
  if [[ ! -f "$SSHPUBFILE" ]]; then
    echo "ERROR: --sshpubfile '$SSHPUBFILE' does not exist" >&2
    exit 1
  fi
  SSHPUB="$(tr -d '\r' < "$SSHPUBFILE")"
else
  # already in SSHPUB or empty
  SSHPUB="$(printf '%s' "$SSHPUB" | tr -d '\r')"
fi

# ------------------- Build ssh_key_ids JSON array -------------------
# Trim spaces and drop empties so "ssh-aaa, ssh-bbb" becomes ["ssh-aaa","ssh-bbb"]
jq_keys_array='[]'
if [[ -n "${SSHKEYS}" ]]; then
  jq_keys_array=$(jq -Rn --arg s "$SSHKEYS" '
    $s
    | split(",")
    | map(gsub("^\\s+|\\s+$";""))
    | map(select(length>0))
  ')
fi

# If --sshpub wasn't given but a single --sshkeys ID was, fetch its public key text from the API.
if [[ -z "$SSHPUB" && -n "$SSHKEYS" && "$SSHKEYS" != *","* ]]; then
  SSHPUB=$(curl -sS https://api.vultr.com/v2/ssh-keys \
    -H "Authorization: Bearer ${VULTR_API_KEY}" \
  | jq -r --arg id "$SSHKEYS" '.ssh_keys[]? | select(.id==$id) | .ssh_key // empty')
fi

# ------------------- Build user_data (cloud-init) -------------------
# Inject the pubkey to both root and ubuntu users (covers images that prefer one or the other).
user_data_b64=""
if [[ -n "$SSHPUB" ]]; then
  read -r -d '' cloudcfg <<'EOF' || true
#cloud-config
ssh_pwauth: false
users:
  - name: root
    ssh_authorized_keys:
      - __PUBKEY__
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
      - __PUBKEY__
write_files:
  - path: /root/.ssh/authorized_keys
    content: |
      __PUBKEY__
    permissions: '0600'
    owner: root:root
runcmd:
  - install -d -m 700 -o root -g root /root/.ssh
  - chmod 600 /root/.ssh/authorized_keys || true
EOF
  cloudcfg="${cloudcfg//__PUBKEY__/${SSHPUB}}"
  # base64 one line (-w 0 for GNU; macOS fallback without -w)
  user_data_b64=$(printf '%s' "$cloudcfg" | base64 -w 0 2>/dev/null || printf '%s' "$cloudcfg" | base64)
fi

# ------------------- Build JSON payload -------------------
payload=$(
  jq -n \
    --arg region "$REGION" \
    --arg plan "$PLAN" \
    --arg label "$LABEL" \
    --argjson os_id "$OS" \
    --argjson ssh_key_ids "$jq_keys_array" \
    --arg user_data "${user_data_b64:-}" '
{
  region: $region,
  plan:   $plan,
  os_id:  $os_id,
  label:  $label,
  ssh_key_ids: $ssh_key_ids
}
| if (.ssh_key_ids | length) == 0 then del(.ssh_key_ids) else . end
| if ($user_data != "") then . + {user_data: $user_data} else . end
'
)

echo "Creating GPU instance on Vultr (region=${REGION}, plan=${PLAN}, os=${OS})..."
# Debug the payload if needed:
# echo "$payload" | jq .

# ------------------- POST /v2/instances -------------------
create_resp=$(curl -sS -X POST "https://api.vultr.com/v2/instances" \
  -H "Authorization: Bearer ${VULTR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$payload")

INSTANCE_ID=$(echo "$create_resp" | jq -r '.instance.id // empty')
if [[ -z "$INSTANCE_ID" ]]; then
  echo "ERROR: Failed to create instance. API response:" >&2
  echo "$create_resp" | jq . >&2
  exit 1
fi
echo "Instance ID: $INSTANCE_ID"

# ------------------- Poll until active + IP -------------------
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

# ------------------- Save final JSON & summary -------------------
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

# ------------------- GitHub Actions outputs (ignored locally) -------------------
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "instance_id=${INSTANCE_ID}"
    echo "ip=${ip}"
  } >> "$GITHUB_OUTPUT"
fi

