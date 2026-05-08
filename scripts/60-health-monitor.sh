#!/usr/bin/env bash
# =================================================================
# Phase 6 — Health Monitor Script
# CIS Benchmark: 4.2.3 (Log review) / NIST SI-4 (Monitoring)
#
# Checks: temperature, memory, disk, services, ports, AppArmor,
#          fail2ban, auditd, sudo I/O, DNS, journal health,
#          firewall posture and local AI inference
#
# Usage:  sudo ./60-health-monitor.sh [--quiet]
#   --quiet: only print WARN/FAIL lines (for cron/timer use)
#
# Exit codes: 0 = all PASS, 1 = warnings, 2 = failures
#
# Phase 6 — T6.4 — 2026-04-17
# =================================================================
set -euo pipefail

# --- Configuration ---
TEMP_WARN=75000    # millidegrees C
TEMP_CRIT=82000
MEM_WARN=80        # percent used
MEM_CRIT=95
DISK_WARN=85       # percent used
DISK_CRIT=95
EXPECTED_SERVICES=(sshd caddy ollama openclaw fail2ban auditd systemd-resolved)
EXPECTED_PORTS=("22/tcp" "80/tcp" "443/tcp")
BASELINE_MODEL="gemma3:1b"
OLLAMA_INFER_TIMEOUT=90
JOURNAL_VERIFY_TIMEOUT=20

# --- State ---
WARN_COUNT=0
FAIL_COUNT=0
PASS_COUNT=0
QUIET=false

[[ "${1:-}" == "--quiet" ]] && QUIET=true

# --- Helpers ---
pass()  { PASS_COUNT=$((PASS_COUNT + 1));  $QUIET || printf "  [PASS] %s\n" "$1"; }
warn()  { WARN_COUNT=$((WARN_COUNT + 1)); printf "  [WARN] %s\n" "$1"; }
fail()  { FAIL_COUNT=$((FAIL_COUNT + 1)); printf "  [FAIL] %s\n" "$1"; }
header(){ $QUIET || printf "\n=== %s ===\n" "$1"; }

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Must run as root (sudo)" >&2
    exit 2
fi

echo "Health Monitor — $(date '+%Y-%m-%d %H:%M:%S') — $(hostname)"
echo "============================================================"

# =================================================================
# 1. TEMPERATURE
# =================================================================
header "Temperature"
if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP_C=$((TEMP / 1000))
    if [[ $TEMP -ge $TEMP_CRIT ]]; then
        fail "CPU temperature: ${TEMP_C}°C (critical ≥$((TEMP_CRIT/1000))°C)"
    elif [[ $TEMP -ge $TEMP_WARN ]]; then
        warn "CPU temperature: ${TEMP_C}°C (warn ≥$((TEMP_WARN/1000))°C)"
    else
        pass "CPU temperature: ${TEMP_C}°C"
    fi
else
    warn "Temperature sensor not found"
fi

# =================================================================
# 2. MEMORY
# =================================================================
header "Memory"
MEM_TOTAL=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
MEM_AVAIL=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
MEM_AVAIL_MB=$((MEM_AVAIL / 1024))

if [[ $MEM_PCT -ge $MEM_CRIT ]]; then
    fail "Memory: ${MEM_PCT}% used (${MEM_AVAIL_MB}M available) — critical ≥${MEM_CRIT}%"
elif [[ $MEM_PCT -ge $MEM_WARN ]]; then
    warn "Memory: ${MEM_PCT}% used (${MEM_AVAIL_MB}M available) — warn ≥${MEM_WARN}%"
else
    pass "Memory: ${MEM_PCT}% used (${MEM_AVAIL_MB}M available)"
fi

# =================================================================
# 3. DISK
# =================================================================
header "Disk"
DISK_PCT=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')

if [[ $DISK_PCT -ge $DISK_CRIT ]]; then
    fail "Root disk: ${DISK_PCT}% used (${DISK_AVAIL} free) — critical ≥${DISK_CRIT}%"
elif [[ $DISK_PCT -ge $DISK_WARN ]]; then
    warn "Root disk: ${DISK_PCT}% used (${DISK_AVAIL} free) — warn ≥${DISK_WARN}%"
else
    pass "Root disk: ${DISK_PCT}% used (${DISK_AVAIL} free)"
fi

# =================================================================
# 4. SERVICES
# =================================================================
header "Services"
for svc in "${EXPECTED_SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        pass "Service $svc: active"
    else
        fail "Service $svc: NOT active"
    fi
done

# =================================================================
# 5. LISTENING PORTS
# =================================================================
header "Ports"
LISTENING=$(ss -tlnp 2>/dev/null)
for port_proto in "${EXPECTED_PORTS[@]}"; do
    PORT="${port_proto%%/*}"
    if echo "$LISTENING" | grep -q ":${PORT} "; then
        pass "Port ${port_proto}: listening"
    else
        fail "Port ${port_proto}: NOT listening"
    fi
done

# =================================================================
# 6. AI INFERENCE
# =================================================================
header "AI Inference"
if OLLAMA_RESP=$(timeout "$((OLLAMA_INFER_TIMEOUT + 5))" curl -s -m "$OLLAMA_INFER_TIMEOUT" http://127.0.0.1:11434/api/generate \
    -d '{"model":"'"${BASELINE_MODEL}"'","prompt":"Reply OK.","stream":false,"keep_alive":"24h","options":{"num_predict":1}}' 2>/dev/null); then
    if echo "$OLLAMA_RESP" | grep -q '"done":true'; then
        pass "Ollama inference: ${BASELINE_MODEL} responded"
    else
        fail "Ollama inference: ${BASELINE_MODEL} returned malformed response"
    fi
else
    fail "Ollama inference: ${BASELINE_MODEL} timed out or failed"
fi

# =================================================================
# 7. APPARMOR
# =================================================================
header "AppArmor"
if command -v aa-status &>/dev/null; then
    AA_ENFORCE=$(aa-status 2>/dev/null | awk '/profiles are in enforce/ {print $1}')
    AA_COMPLAIN=$(aa-status 2>/dev/null | awk '/profiles are in complain/ {print $1}')
    AA_TOTAL=$(aa-status 2>/dev/null | awk '/profiles are loaded/ {print $1}')
    pass "AppArmor: ${AA_TOTAL:-0} loaded, ${AA_ENFORCE:-0} enforce, ${AA_COMPLAIN:-0} complain"

    # Check for recent denials (last 24h)
    AA_DENIALS=$(journalctl -k --since "24 hours ago" --grep="apparmor=\"DENIED\"" --no-pager 2>/dev/null | wc -l) || AA_DENIALS=0
    if [[ $AA_DENIALS -gt 0 ]]; then
        warn "AppArmor: ${AA_DENIALS} denial(s) in last 24h"
    else
        pass "AppArmor: no denials in last 24h"
    fi
else
    fail "AppArmor: aa-status not found"
fi

# =================================================================
# 8. FAIL2BAN
# =================================================================
header "Fail2Ban"
if systemctl is-active --quiet fail2ban 2>/dev/null; then
    F2B_JAILS=$(fail2ban-client status 2>/dev/null | awk -F: '/Jail list/ {gsub(/[[:space:]]/,"",$2); print $2}')
    F2B_BANNED=$(fail2ban-client status sshd 2>/dev/null | awk '/Currently banned/ {print $NF}')
    F2B_TOTAL=$(fail2ban-client status sshd 2>/dev/null | awk '/Total banned/ {print $NF}')
    pass "Fail2Ban: jails=[${F2B_JAILS}], sshd banned now=${F2B_BANNED:-0} total=${F2B_TOTAL:-0}"
else
    fail "Fail2Ban: not active"
fi

# =================================================================
# 9. AUDITD
# =================================================================
header "Auditd"
if systemctl is-active --quiet auditd 2>/dev/null; then
    AUDIT_RULES=$(auditctl -l 2>/dev/null | wc -l)
    AUDIT_ENABLED=$(auditctl -s 2>/dev/null | awk '/enabled/ {print $2}')
    if [[ "${AUDIT_ENABLED}" == "2" ]]; then
        pass "Auditd: ${AUDIT_RULES} rules, enabled=${AUDIT_ENABLED} (immutable)"
    else
        warn "Auditd: ${AUDIT_RULES} rules, enabled=${AUDIT_ENABLED} (NOT immutable)"
    fi
else
    fail "Auditd: not active"
fi

# =================================================================
# 10. SUDO I/O LOGGING
# =================================================================
header "Sudo I/O"
if [[ -d /var/log/sudo-io ]]; then
    SUDO_SESSIONS=$(find /var/log/sudo-io -name "log" -type f 2>/dev/null | wc -l)
    pass "Sudo I/O: ${SUDO_SESSIONS} recorded sessions"
else
    warn "Sudo I/O: /var/log/sudo-io not found"
fi

# =================================================================
# 11. DNS-OVER-TLS
# =================================================================
header "DNS"
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    PROTO_LINE=$(SYSTEMD_PAGER=cat resolvectl status 2>/dev/null | grep 'Protocols:' | head -1)
    if echo "$PROTO_LINE" | grep -q '+DNSOverTLS'; then
        pass "DNS-over-TLS: active"
    elif echo "$PROTO_LINE" | grep -q 'DNSOverTLS'; then
        warn "DNS-over-TLS: not enforced"
    else
        warn "DNS-over-TLS: unknown"
    fi
    if echo "$PROTO_LINE" | grep -q 'DNSSEC=yes'; then
        pass "DNSSEC: active"
    else
        warn "DNSSEC: not active"
    fi
else
    fail "systemd-resolved: not active"
fi

# =================================================================
# 12. JOURNAL HEALTH
# =================================================================
header "Journal"
JOURNAL_USAGE=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+[KMGT]')
pass "Journal disk usage: ${JOURNAL_USAGE}"

if JOURNAL_VERIFY_OUTPUT=$(timeout "$JOURNAL_VERIFY_TIMEOUT" journalctl --verify 2>&1); then
    JOURNAL_ERRORS=$(printf '%s\n' "$JOURNAL_VERIFY_OUTPUT" | grep -c "FAIL" || true)
    if [[ $JOURNAL_ERRORS -gt 0 ]]; then
        warn "Journal: ${JOURNAL_ERRORS} corrupt file(s)"
    else
        pass "Journal: integrity OK"
    fi
elif [[ $? -eq 124 ]]; then
    warn "Journal: verification exceeded ${JOURNAL_VERIFY_TIMEOUT}s"
else
    warn "Journal: verify command failed"
fi

# =================================================================
# 13. FIREWALL
# =================================================================
header "Firewall"
if command -v nft &>/dev/null; then
    NFT_TABLES=$(nft list tables 2>/dev/null | wc -l)
    NFT_INPUT_POLICY=$(nft list chain inet filter input 2>/dev/null | awk '/policy/ {print $NF}' | tr -d ';')
    if [[ "$NFT_INPUT_POLICY" == "drop" ]]; then
        pass "nftables: input policy=drop, ${NFT_TABLES} table(s)"
    else
        fail "nftables: input policy=${NFT_INPUT_POLICY:-unknown} (expected drop)"
    fi
else
    fail "nftables: nft command not found"
fi

# =================================================================
# SUMMARY
# =================================================================
echo ""
echo "============================================================"
TOTAL=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))
echo "SUMMARY: ${TOTAL} checks — ${PASS_COUNT} PASS, ${WARN_COUNT} WARN, ${FAIL_COUNT} FAIL"
echo "============================================================"

# Determine exit code
if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 2
elif [[ $WARN_COUNT -gt 0 ]]; then
    exit 1
else
    exit 0
fi
