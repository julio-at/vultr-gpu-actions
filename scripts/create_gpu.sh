#!/usr/bin/env bash
set -euo pipefail

# Usage:
# ./scripts/create_gpu.sh --region <REGION> --plan <PLAN> --os <OS> --label <LABEL> --sshkeys "id1,id2"
#
# Requirements:
# - Env: VULTR_API_KEY
# - vultr-cli and jq installed

REGION=""
PLAN=""
OS=""
LABEL="gpu-from-actions"
SSHKEYS=""

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

if [[ -z "${REGION}" || -z "${PLAN}" || -z "${OS}" ]]; then
  echo "Missing required parameters --region/--plan/--os" >&2
  exit 1
fi

# Build optional flags
SSH_FLAG=()
if [[ -n "${SSHKEYS}" ]]; then
  # vultr-cli accepts multiple --ssh-key-id flags
  IFS=',' read -ra KEYS <<< "${SSHKEYS}"
  for k in "${KEYS[@]}"; do
    SSH_FLAG+=( --ssh-key-id "$k" )
  done
fi

echo "Creating GPU instance on Vultr..."
CREATE_JSON=$(vultr-cli instance create   --region "${REGION}"   --plan "${PLAN}"   --os "${OS}"   --label "${LABEL}"   --format json   "${SSH_FLAG[@]}")

INSTANCE_ID=$(echo "${CREATE_JSON}" | jq -r '.instance.id // .id // empty')
if [[ -z "${INSTANCE_ID}" ]]; then
  echo "Failed to obtain Instance ID" >&2
  echo "${CREATE_JSON}" >&2
  exit 1
fi
echo "Instance ID: ${INSTANCE_ID}"

# Wait until it's "active" and has a public IP assigned
echo "Waiting for the instance to become active..."
for i in {1..60}; do
  INFO=$(vultr-cli instance get "${INSTANCE_ID}" --format json)
  STATUS=$(echo "${INFO}" | jq -r '.instance.status // .status // empty')
  MAIN_IP=$(echo "${INFO}" | jq -r '.instance.main_ip // .main_ip // empty')
  if [[ "${STATUS}" == "active" && -n "${MAIN_IP}" && "${MAIN_IP}" != "0.0.0.0" ]]; then
    break
  fi
  sleep 10
done

# Get final info
FINAL=$(vultr-cli instance get "${INSTANCE_ID}" --format json | jq '.instance // .')
echo "${FINAL}" > "instance-${INSTANCE_ID}.json"

IP=$(echo "${FINAL}" | jq -r '.main_ip // empty')
REGION_NAME=$(echo "${FINAL}" | jq -r '.region // empty')
LABEL_OUT=$(echo "${FINAL}" | jq -r '.label // empty')

echo "Instance is active:"
echo " - ID: ${INSTANCE_ID}"
echo " - Label: ${LABEL_OUT}"
echo " - Region: ${REGION_NAME}"
echo " - IP: ${IP}"

# Export outputs to GitHub Actions, if applicable
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "instance_id=${INSTANCE_ID}"
    echo "ip=${IP}"
  } >> "$GITHUB_OUTPUT"
fi
