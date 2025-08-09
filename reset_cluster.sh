#!/bin/bash

# Destroys local Galera data (node1..4) and reboots a fresh cluster using ./.env settings.
# DATA LOSS WARNING: this removes ./node*/data contents.

set -euo pipefail
cd "$(dirname "$0")"

echo "[WARN] This will PERMANENTLY delete all data under ./node{1..4}/data." >&2
echo "       Use only for local dev/demo resets."
read -r -p "Type WIPE to continue: " CONFIRM
if [ "${CONFIRM}" != "WIPE" ]; then
  echo "Aborted."; exit 1
fi

echo "[INFO] Stopping containers..."
docker compose down || true

for i in 1 2 3 4; do
  d="./node${i}/data"
  if [ -d "$d" ]; then
    echo "[INFO] Wiping $d ..."
    # Remove contents but keep the directory
    rm -rf "$d"/* "$d"/.[!.]* "$d"/..?* 2>/dev/null || true
  fi
done

echo "[INFO] Bootstrap fresh cluster..."
./setup_haproxy_user.sh

echo "[DONE] Cluster reset and bootstrapped."
