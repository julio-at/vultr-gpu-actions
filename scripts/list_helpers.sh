#!/usr/bin/env bash
set -euo pipefail

# Helpers to discover IDs and GPU plans

echo "== Regions =="
vultr-cli regions list || true
echo

echo "== Operating Systems (common IDs) =="
vultr-cli os list | head -n 50 || true
echo "Tip: Ubuntu 22.04 is often 215; Ubuntu 24.04 is often 477 (verify with the command)."
echo

echo "== Plans (try to filter GPU if possible) =="
# Show all plans and grep for common GPU hints; fall back to full list if grep returns nothing.
vultr-cli plans list | grep -i -E 'gpu|l40|a100|mi|h100' || vultr-cli plans list || true
echo
