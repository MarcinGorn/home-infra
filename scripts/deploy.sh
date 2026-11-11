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

echo "==> Preparing temporary HA configuration"

TEST_DIR="$(docker exec homeassistant mktemp -d /tmp/ha-deploy.XXXXXX)"

cleanup() {
  docker exec homeassistant rm -rf -- "$TEST_DIR" || true
}
trap cleanup EXIT

docker exec homeassistant cp -a /config/. "$TEST_DIR/"

for file in configuration.yaml automations.yaml scripts.yaml scenes.yaml; do
  docker cp "homeassistant/$file" \
    "homeassistant:$TEST_DIR/$file"
done

docker exec homeassistant mkdir -p "$TEST_DIR/dashboards"

for dashboard in homeassistant/dashboards/*.yaml; do
  [[ -f "$dashboard" ]] || continue
  docker cp "$dashboard" \
    "homeassistant:$TEST_DIR/dashboards/$(basename "$dashboard")"
done

echo "==> Validating Home Assistant configuration"

docker exec homeassistant python -m homeassistant \
  --script check_config -c "$TEST_DIR"

echo "==> Syncing Home Assistant configuration"
for file in configuration.yaml automations.yaml scripts.yaml scenes.yaml; do
  install -m 0644 "homeassistant/$file" "$HA_CONFIG_DIR/$file"
done

install -d "$HA_CONFIG_DIR/dashboards"

for dashboard in homeassistant/dashboards/*.yaml; do
  [[ -f "$dashboard" ]] || continue

  install -m 0644 \
    "$dashboard" \
    "$HA_CONFIG_DIR/dashboards/$(basename "$dashboard")"
done

echo "==> Deploying Home Assistant"
docker compose up -d --remove-orphans

echo "==> Restarting Home Assistant to load YAML changes"
docker compose restart homeassistant

echo "==> Container status"
docker compose ps


