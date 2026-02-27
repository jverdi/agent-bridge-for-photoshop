#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOT_RELOAD_PORT="${PSAGENT_HOT_RELOAD_PORT:-43121}"
HOT_RELOAD_TIMEOUT_SEC="${PSAGENT_HOT_RELOAD_TIMEOUT_SEC:-45}"
LOG_FILE="${PSAGENT_HOT_RELOAD_LOG:-/tmp/ps-agent-bridge-hotreload-verify.log}"

cd "${REPO_ROOT}"

json_eval() {
  local json="$1"
  local expr="$2"
  node -e "const j=JSON.parse(process.argv[1]); const f=new Function('j', 'return (' + process.argv[2] + ');'); const out=f(j); if (out===undefined) process.exit(2); process.stdout.write(String(out));" "$json" "$expr"
}

status_json="$(npm run -s dev -- bridge status --json)"
active_connected="$(json_eval "$status_json" "j.activeConnected")"
active_client_before="$(json_eval "$status_json" "j.activeClientId || ''")"

if [[ "${active_connected}" != "true" ]]; then
  echo "Bridge is not connected. Start daemon and run bridge reload first." >&2
  exit 1
fi

if [[ -z "${active_client_before}" ]]; then
  echo "Bridge status did not return activeClientId." >&2
  exit 1
fi

echo "bridge-connected client=${active_client_before}"

node scripts/dev/hot-reload-server.mjs --port "${HOT_RELOAD_PORT}" >"${LOG_FILE}" 2>&1 &
hotreload_pid="$!"
cleanup() {
  kill "${hotreload_pid}" >/dev/null 2>&1 || true
  wait "${hotreload_pid}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ready="false"
for _ in $(seq 1 20); do
  if curl -fsS --max-time 1 "http://127.0.0.1:${HOT_RELOAD_PORT}/version" >/dev/null 2>&1; then
    ready="true"
    break
  fi
  sleep 0.5
done

if [[ "${ready}" != "true" ]]; then
  echo "Hot-reload server did not become ready on port ${HOT_RELOAD_PORT}" >&2
  tail -n 80 "${LOG_FILE}" >&2 || true
  exit 1
fi

bump_json="$(curl -fsS -X POST "http://127.0.0.1:${HOT_RELOAD_PORT}/bump")"
bump_version="$(json_eval "$bump_json" "j.version")"
echo "hotreload-bump version=${bump_version}"

active_client_after=""
for _ in $(seq 1 "${HOT_RELOAD_TIMEOUT_SEC}"); do
  sleep 1
  loop_status="$(npm run -s dev -- bridge status --json)"
  candidate="$(json_eval "$loop_status" "j.activeClientId || ''")"
  if [[ -n "${candidate}" && "${candidate}" != "${active_client_before}" ]]; then
    active_client_after="${candidate}"
    break
  fi
done

if [[ -z "${active_client_after}" ]]; then
  echo "Hot reload check warning: bridge client id did not change after bump; continuing." >&2
else
  echo "hotreload-ok client=${active_client_after}"
fi

happy_payload="$(mktemp)"
cat >"${happy_payload}" <<'JSON'
{
  "transactionId": "live-ps-integration-001",
  "doc": { "ref": "active" },
  "ops": [
    { "op": "createDocument", "name": "Live Integration", "width": 900, "height": 900, "resolution": 72, "ref": "docA" },
    { "op": "createTextLayer", "name": "Title", "text": "Integration", "position": { "x": 120, "y": 160 }, "fontSize": 64, "ref": "title" },
    { "op": "setTextStyle", "target": "$title", "fontName": "Arial-BoldMT", "fontSize": 80, "maxWidth": 760 },
    { "op": "createLayer", "name": "TempLayer", "ref": "temp" },
    { "op": "setLayerProps", "target": "$temp", "opacity": 50, "visible": true },
    { "op": "deleteLayer", "target": "$temp" },
    { "op": "createShapeLayer", "name": "Badge", "x": 32, "y": 32, "width": 120, "height": 120, "fill": "#ff6600", "ref": "badge" },
    { "op": "deleteLayer", "target": "$badge" },
    { "op": "closeDocument", "save": false }
  ],
  "safety": {
    "dryRun": false,
    "checkpoint": true,
    "rollbackOnError": false,
    "onError": "abort"
  }
}
JSON

if ! happy_result="$(npm run -s dev -- op apply -f "${happy_payload}" --json 2>&1)"; then
  echo "Live happy-path integration command failed." >&2
  echo "${happy_result}" >&2
  exit 1
fi
happy_applied="$(json_eval "$happy_result" "j.result.applied")"
happy_failed="$(json_eval "$happy_result" "j.result.failed")"
happy_aborted="$(json_eval "$happy_result" "j.result.aborted")"

if [[ "${happy_applied}" != "9" || "${happy_failed}" != "0" || "${happy_aborted}" != "false" ]]; then
  echo "Live happy-path integration failed expectations." >&2
  echo "${happy_result}" >&2
  exit 1
fi
echo "live-integration-happy ok applied=${happy_applied} failed=${happy_failed}"

validation_payload="$(mktemp)"
cat >"${validation_payload}" <<'JSON'
{
  "transactionId": "live-ps-validation-001",
  "doc": { "ref": "active" },
  "ops": [
    { "op": "createDocument", "name": "Live Validation", "width": 640, "height": 640, "resolution": 72, "ref": "docA" },
    { "op": "createTextLayer", "name": "Title", "text": "Validation", "ref": "title" },
    { "op": "setTextStyle", "target": "$title", "onError": "continue" },
    { "op": "closeDocument", "save": false }
  ],
  "safety": {
    "dryRun": false,
    "onError": "abort"
  }
}
JSON

if ! validation_result="$(npm run -s dev -- op apply -f "${validation_payload}" --json 2>&1)"; then
  echo "Live validation-path integration command failed." >&2
  echo "${validation_result}" >&2
  exit 1
fi
validation_applied="$(json_eval "$validation_result" "j.result.applied")"
validation_failed="$(json_eval "$validation_result" "j.result.failed")"
validation_aborted="$(json_eval "$validation_result" "j.result.aborted")"
validation_msg="$(json_eval "$validation_result" "(j.result.opResults.find(r => r.status === 'failed') || {}).error?.message || ''")"

if [[ "${validation_applied}" != "3" || "${validation_failed}" != "1" || "${validation_aborted}" != "false" ]]; then
  echo "Live validation-path integration failed expectations." >&2
  echo "${validation_result}" >&2
  exit 1
fi

if [[ "${validation_msg}" != *"setTextStyle requires at least one supported field"* ]]; then
  echo "Expected setTextStyle preflight validation message not found." >&2
  echo "${validation_result}" >&2
  exit 1
fi
echo "live-integration-validation ok failed=${validation_failed}"

first_class_render="/tmp/psagent-live-first-class.png"
rm -f "${first_class_render}"

first_class_payload="$(mktemp)"
cat >"${first_class_payload}" <<JSON
{
  "transactionId": "live-ps-first-class-001",
  "doc": { "ref": "active" },
  "ops": [
    { "op": "createDocument", "name": "First Class Verify", "width": 1080, "height": 1080, "resolution": 72, "mode": "rgbColor", "fill": "white", "ref": "docA" },
    { "op": "createShapeLayer", "name": "Card", "shape": "rectangle", "x": 120, "y": 140, "width": 840, "height": 800, "cornerRadius": 52, "fillType": "gradient", "gradient": { "from": "#14532d", "to": "#4ade80", "angle": 90 }, "ref": "card" },
    { "op": "placeAsset", "name": "HeroPhoto", "input": "https://picsum.photos/seed/psagent-first-class/1024/1024.jpg", "ref": "photo" },
    { "op": "createClippingMask", "target": "\$photo" },
    { "op": "createTextLayer", "name": "Title", "text": "PLANT ERA", "fontName": "Arial-BoldMT", "fontSize": 88, "textColor": "#f8fafc", "alignment": "center", "position": { "x": 540, "y": 240 }, "maxWidth": 840, "ref": "title" },
    { "op": "setTextStyle", "target": "\$title", "textColor": "#ffffff", "alignment": "center", "maxWidth": 840 },
    { "op": "setLayerEffects", "target": "\$title", "dropShadow": { "color": "#000000", "opacity": 45, "distance": 10, "size": 18 }, "stroke": { "color": "#ffffff", "size": 2, "position": "outside", "opacity": 100 } },
    { "op": "applyAddNoise", "target": "\$photo", "amount": 4, "distribution": "uniform", "monochromatic": true },
    { "op": "exportDocument", "format": "png", "output": "${first_class_render}" },
    { "op": "closeDocument", "save": false }
  ],
  "safety": {
    "dryRun": false,
    "onError": "abort"
  }
}
JSON

if ! first_class_result="$(npm run -s dev -- op apply -f "${first_class_payload}" --json 2>&1)"; then
  echo "Live first-class feature integration command failed." >&2
  echo "${first_class_result}" >&2
  exit 1
fi
first_class_applied="$(json_eval "$first_class_result" "j.result.applied")"
first_class_failed="$(json_eval "$first_class_result" "j.result.failed")"
first_class_aborted="$(json_eval "$first_class_result" "j.result.aborted")"

if [[ "${first_class_applied}" != "10" || "${first_class_failed}" != "0" || "${first_class_aborted}" != "false" ]]; then
  echo "Live first-class feature integration failed expectations." >&2
  echo "${first_class_result}" >&2
  exit 1
fi

if [[ ! -s "${first_class_render}" ]]; then
  echo "Live first-class feature integration did not produce render output: ${first_class_render}" >&2
  echo "${first_class_result}" >&2
  exit 1
fi
echo "live-integration-first-class ok applied=${first_class_applied} render=${first_class_render}"

rm -f "${happy_payload}" "${validation_payload}" "${first_class_payload}"
echo "verify-photoshop-live=ok"
