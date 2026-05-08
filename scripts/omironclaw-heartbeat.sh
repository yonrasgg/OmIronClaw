#!/usr/bin/env bash
# OmIronClaw Heartbeat — Ollama + OpenClaw + nftables state dumper
# ------------------------------------------------------------
# Read-only snapshot of the AI stack (Ollama, OpenClaw, Caddy, Snort-free)
# into the Syncthing-synced Vault.
#
# Target host: any Debian 13 node running the OmIronClaw stack
# Invocation: systemd timer every 5 min, non-blocking, read-only
#
# Install as:
#   /opt/OmIronClaw/scripts/omironclaw-heartbeat.sh
#   Managed by: templates/systemd/heartbeat.service + heartbeat.timer

set -euo pipefail

DATA_MOUNT="${DATA_MOUNT:-/mnt/data}"
SYNC_SERVICE="${SYNC_SERVICE:-syncthing@${SSH_USER:-$USER}}"
VAULT_ROOT="${VAULT_ROOT:-${DATA_MOUNT}/ai-data/documents/HOME_LAB}"
OUT_DIR="${VAULT_ROOT}/40_Telemetry/Heartbeats"
HOST_ID="$(hostname -s)"
TS_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TS_FILE="$(date -u +%Y%m%d-%H%M%S)"

mkdir -p "${OUT_DIR}"
TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

# --- System metrics ----------------------------------------------------------
UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime)
LOAD1=$(awk '{print $1}' /proc/loadavg)
MEM_AVAIL_KB=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
MEM_TOTAL_KB=$(awk '/MemTotal/     {print $2}' /proc/meminfo)
DISK_ROOT_PCT=$(df -P / | awk 'NR==2 {gsub("%",""); print $5}')
DISK_DATA_PCT=$(df -P "$DATA_MOUNT" 2>/dev/null | awk 'NR==2 {gsub("%",""); print $5}' || echo "NA")
CPU_TEMP_MC=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
CPU_TEMP_C=$(( CPU_TEMP_MC / 1000 ))

# --- Service status (best-effort, read-only) --------------------------------
svc_state() {
  systemctl is-active "$1" 2>/dev/null || echo "inactive"
}
OLLAMA_STATE=$(svc_state ollama)
OPENCLAW_STATE=$(svc_state openclaw)
CADDY_STATE=$(svc_state caddy)
FAIL2BAN_STATE=$(svc_state fail2ban)
AUDITD_STATE=$(svc_state auditd)
SYNCTHING_STATE=$(svc_state "$SYNC_SERVICE")

# --- Ollama models (if responsive) ------------------------------------------
OLLAMA_MODELS="unknown"
if [ "${OLLAMA_STATE}" = "active" ] && command -v curl >/dev/null 2>&1; then
  OLLAMA_MODELS=$(curl -s --max-time 3 http://127.0.0.1:11434/api/tags \
    | grep -oE '"name":"[^"]+"' | cut -d'"' -f4 | paste -sd',' - || echo "unreachable")
fi

# --- Frontmatter + body ------------------------------------------------------
cat > "${TMP}" <<EOF
---
title: "Heartbeat ${HOST_ID} ${TS_ISO}"
type: "telemetry"
domain: "system"
sensitivity: "internal"
agent_access: "true"
host: "${HOST_ID}"
source: "omironclaw-heartbeat.sh"
created: ${TS_ISO}
updated: ${TS_ISO}
tags: ["heartbeat", "ollama", "openclaw"]
uptime_sec: ${UPTIME_SEC}
load1: ${LOAD1}
mem_total_kb: ${MEM_TOTAL_KB}
mem_available_kb: ${MEM_AVAIL_KB}
disk_root_pct: ${DISK_ROOT_PCT}
disk_data_pct: ${DISK_DATA_PCT}
cpu_temp_c: ${CPU_TEMP_C}
ollama_state: "${OLLAMA_STATE}"
openclaw_state: "${OPENCLAW_STATE}"
caddy_state: "${CADDY_STATE}"
fail2ban_state: "${FAIL2BAN_STATE}"
auditd_state: "${AUDITD_STATE}"
syncthing_state: "${SYNCTHING_STATE}"
ollama_models: "${OLLAMA_MODELS}"
---

# Heartbeat — ${HOST_ID} @ ${TS_ISO}

## AI Stack
- Ollama: \`${OLLAMA_STATE}\` — models: \`${OLLAMA_MODELS}\`
- OpenClaw: \`${OPENCLAW_STATE}\`
- Caddy: \`${CADDY_STATE}\`

## Security
- Fail2ban: \`${FAIL2BAN_STATE}\`
- auditd: \`${AUDITD_STATE}\`

## System
- Load1: ${LOAD1} | Temp: ${CPU_TEMP_C} °C
- Disk / : ${DISK_ROOT_PCT}% | ${DATA_MOUNT} : ${DISK_DATA_PCT}%
- Mem available: ${MEM_AVAIL_KB} / ${MEM_TOTAL_KB} KB
EOF

OUT_FILE="${OUT_DIR}/${HOST_ID}_${TS_FILE}.md"
mv "${TMP}" "${OUT_FILE}"
chmod 640 "${OUT_FILE}" 2>/dev/null || true
trap - EXIT

# Retention: keep last 288 files (~24 h @ 5 min)
ls -1t "${OUT_DIR}/${HOST_ID}_"*.md 2>/dev/null \
  | tail -n +289 \
  | xargs -r rm -f
