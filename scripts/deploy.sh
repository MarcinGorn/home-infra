#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ ! -f .env ]]; then
  echo "ERROR: Missing .env"
  exit 1
fi

set -a
source .env
set +a

: "${HA_CONFIG_DIR:?HA_CONFIG_DIR must be set}"

if [[ ! -d "$HA_CONFIG_DIR" ]]; then
  echo "ERROR: Config directory does not exist: $HA_CONFIG_DIR"
  exit 1
fi

echo "==> Validating Docker Compose"
docker compose config --quiet

echo "==> Syncing Home Assistant configuration"
for file in configuration.yaml automations.yaml scripts.yaml scenes.yaml; do
  install -m 0644 "homeassistant/$file" "$HA_CONFIG_DIR/$file"
done

echo "==> Deploying Home Assistant"
docker compose up -d --remove-orphans

echo "==> Container status"
docker compose ps