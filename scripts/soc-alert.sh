#!/usr/bin/env bash
# soc-alert.sh — Forward SecOps events to OpenClaw (local) for triage + Telegram push.
# -----------------------------------------------------------------------------
# Called by:
#   - Snort3 alert_json output (via a systemd path watcher)
#   - Fail2ban action (jail.local: action = soc-alert[...] )
#   - Ad-hoc from any LAN host
#
# Writes:
#   1) A Markdown incident stub into 40_Telemetry/SecOps/ (Vault, via Syncthing).
#   2) A POST to the OpenClaw gateway so Clawbot can analyse + push Telegram.
#
# Never embeds secrets: the gateway token is sourced from /etc/openclaw.env.

set -euo pipefail

# --- Defaults (override via env or CLI) --------------------------------------
SOURCE="${SOURCE:-manual}"        # snort3 | fail2ban | auditd | manual
HOST="${HOST:-$(hostname -s)}"
SEVERITY="${SEVERITY:-medium}"    # info | low | medium | high
SIGNATURE="${SIGNATURE:-unknown}"
SRC_IP="${SRC_IP:-unknown}"
DST_IP="${DST_IP:-unknown}"
MESSAGE="${MESSAGE:-no message}"

# Positional overrides: soc-alert.sh <source> <severity> <signature> <src_ip> <dst_ip> <message>
[ $# -ge 1 ] && SOURCE="$1"
[ $# -ge 2 ] && SEVERITY="$2"
[ $# -ge 3 ] && SIGNATURE="$3"
[ $# -ge 4 ] && SRC_IP="$4"
[ $# -ge 5 ] && DST_IP="$5"
[ $# -ge 6 ] && MESSAGE="$6"

DATA_MOUNT="${DATA_MOUNT:-/mnt/data}"
VAULT_ROOT="${VAULT_ROOT:-${DATA_MOUNT}/ai-data/vault/HOME_LAB}"
OUT_DIR="${VAULT_ROOT}/40_Telemetry/SecOps"
mkdir -p "${OUT_DIR}"

TS_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TS_FILE="$(date -u +%Y%m%d-%H%M%S)"
SLUG="$(echo "${SIGNATURE}" | tr '[:upper:] ' '[:lower:]_' | tr -cd 'a-z0-9_-' | cut -c1-40)"
OUT_FILE="${OUT_DIR}/${TS_FILE}_${HOST}_${SLUG:-event}.md"

# --- Vault incident stub -----------------------------------------------------
cat > "${OUT_FILE}" <<EOF
---
title: "[${SEVERITY^^}] ${SOURCE} on ${HOST}: ${SIGNATURE}"
type: "incident"
domain: "security"
sensitivity: "internal"
agent_access: "true"
source: "${SOURCE}"
host: "${HOST}"
severity: "${SEVERITY}"
status: "open"
signature: "${SIGNATURE}"
src_ip: "${SRC_IP}"
dst_ip: "${DST_IP}"
created: ${TS_ISO}
updated: ${TS_ISO}
tags: ["alert", "secops", "${SOURCE}"]
---

# SecOps event — ${SOURCE} on ${HOST}

- **Signature**: \`${SIGNATURE}\`
- **Src → Dst**: \`${SRC_IP}\` → \`${DST_IP}\`
- **Severity**: ${SEVERITY}
- **Detected**: ${TS_ISO}

## Raw message
\`\`\`
${MESSAGE}
\`\`\`

## Triage
_Pending — Clawbot (SecOps skill) will attach analysis._
EOF

chmod 640 "${OUT_FILE}" || true

# --- OpenClaw webhook (best-effort, fail-open) -------------------------------
OPENCLAW_ENV="${OPENCLAW_ENV:-/etc/openclaw.env}"
OPENCLAW_URL="${OPENCLAW_URL:-http://127.0.0.1:18789/webhooks/soc-alert}"

if [ -r "${OPENCLAW_ENV}" ]; then
  # shellcheck disable=SC1090
  . "${OPENCLAW_ENV}"
fi
TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"

if [ -n "${TOKEN}" ] && command -v curl >/dev/null 2>&1; then
  PAYLOAD=$(cat <<JSON
{
  "source": "${SOURCE}",
  "host": "${HOST}",
  "severity": "${SEVERITY}",
  "signature": "${SIGNATURE}",
  "src_ip": "${SRC_IP}",
  "dst_ip": "${DST_IP}",
  "message": $(printf '%s' "${MESSAGE}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo "\"${MESSAGE//\"/\\\"}\""),
  "vault_file": "${OUT_FILE}",
  "timestamp": "${TS_ISO}"
}
JSON
  )
  curl -sS --max-time 5 \
       -X POST "${OPENCLAW_URL}" \
       -H "Content-Type: application/json" \
       -H "X-OpenClaw-Token: ${TOKEN}" \
       --data "${PAYLOAD}" >/dev/null 2>&1 || true
fi

echo "${OUT_FILE}"
