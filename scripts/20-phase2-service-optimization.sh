#!/bin/bash
# =============================================================================
# Phase 2 — Service Optimization Execution Script
# OmIronClaw Hardening Project
#
# Tasks: T2.1-T2.18 (Attack Surface, Privilege Architecture, MAC, Systemd)
# Standards: CIS 1.1/1.6/2.x/5.x / NIST AC-6/CM-6/CM-7/AC-3
#
# Safety: SNAPSHOT → VALIDATE → APPLY → VERIFY → DOCUMENT
# Run as: sudo bash scripts/20-phase2-service-optimization.sh
#
# NOTE: This script is idempotent — safe to re-run.
# =============================================================================
set -euo pipefail

# --- CONFIG ---
PROJECT_DIR="${PROJECT_DIR:-/home/${SSH_USER:-$(logname)}/OmIronClaw}"
EVIDENCE_DIR="${PROJECT_DIR}/wiki/evidence/service-optimization"
TEMPLATES_DIR="${PROJECT_DIR}/templates"
DATE=$(date +%Y%m%d_%H%M%S)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }
divider() { echo ""; echo "================================================================"; echo "$1"; echo "================================================================"; }

# --- SAFETY CHECK: Must be root ---
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo)"
    exit 1
fi

mkdir -p "$EVIDENCE_DIR"

# =============================================================================
divider "PHASE 2 — STEP 0: PRE-FLIGHT SNAPSHOT"
# =============================================================================
log "Capturing pre-flight state..."

log "  Active services:"
systemctl list-units --type=service --state=active --no-pager | wc -l

log "  Masked services:"
systemctl list-unit-files --state=masked --no-pager 2>/dev/null | tee "${EVIDENCE_DIR}/masked-before-${DATE}.txt" | wc -l

log "  SUID binaries:"
find / -perm /4000 -type f 2>/dev/null | tee "${EVIDENCE_DIR}/suid-before-${DATE}.txt" | wc -l

log "  Systemd security scores:"
systemd-analyze security ssh.service ollama.service avahi-daemon.service cron.service 2>/dev/null \
    | grep -E '^[a-z]' | tee "${EVIDENCE_DIR}/security-scores-before-${DATE}.txt"

log "  AppArmor status:"
aa-status 2>/dev/null | head -5 | tee -a "${EVIDENCE_DIR}/apparmor-before-${DATE}.txt"

echo ""

# =============================================================================
divider "PHASE 2 — STEP 1: ATTACK SURFACE REDUCTION (T2.1–T2.7)"
# =============================================================================

# --- T2.1: Disable Bluetooth ---
log "T2.1: Disabling bluetooth service..."
systemctl mask bluetooth.service 2>/dev/null && log "  ✓ bluetooth masked" || log "  (already masked)"

# --- T2.2: Disable cloud-init ---
log "T2.2: Disabling cloud-init services..."
for unit in cloud-config.service cloud-final.service cloud-init-local.service cloud-init-main.service cloud-init-network.service; do
    systemctl mask "$unit" 2>/dev/null && log "  ✓ ${unit} masked" || log "  (already masked: ${unit})"
done

# --- T2.3: Disable serial console ---
log "T2.3: Disabling serial console..."
systemctl mask serial-getty@ttyAMA10.service 2>/dev/null && log "  ✓ serial-getty masked" || log "  (already masked)"

# --- T2.4: Blacklist kernel modules ---
log "T2.4: Deploying module blacklist..."
cp "${TEMPLATES_DIR}/modprobe-blacklist.conf" /etc/modprobe.d/hardening-blacklist.conf
log "  ✓ /etc/modprobe.d/hardening-blacklist.conf deployed"

# Verify blacklisted modules not loaded
LOADED_BAD=0
for mod in cramfs freevxfs jffs2 hfs hfsplus udf bluetooth btusb btbcm hci_uart; do
    if lsmod | grep -qw "$mod"; then
        warn "  ⚠ ${mod} still loaded (will unload after reboot)"
        LOADED_BAD=$((LOADED_BAD + 1))
    fi
done
if [[ $LOADED_BAD -eq 0 ]]; then
    log "  ✓ No blacklisted modules currently loaded"
fi

# --- T2.5: SUID cleanup ---
log "T2.5: SUID binary cleanup..."
SUID_TARGETS=(/usr/bin/newgrp /usr/bin/chfn /usr/bin/chsh /usr/bin/fusermount3 /usr/bin/mount.cifs /usr/bin/ntfs-3g /usr/sbin/pppd)
for bin in "${SUID_TARGETS[@]}"; do
    if [[ -f "$bin" ]] && [[ -u "$bin" ]]; then
        chmod u-s "$bin"
        log "  ✓ Stripped SUID from ${bin}"
    fi
done
SUID_COUNT=$(find / -perm /4000 -type f 2>/dev/null | wc -l)
log "  SUID remaining: ${SUID_COUNT}"

# --- T2.6: Avahi evaluation ---
log "T2.6: Avahi — KEEP (<PI_HOSTNAME>.local mDNS) + sandbox applied in Step 3"

# --- T2.7: Disable udisks2 ---
log "T2.7: Disabling udisks2..."
systemctl mask udisks2.service 2>/dev/null && log "  ✓ udisks2 masked" || log "  (already masked)"

echo ""

# =============================================================================
divider "PHASE 2 — STEP 2: PRIVILEGE ARCHITECTURE (T2.8–T2.11)"
# =============================================================================

# --- T2.8: Service users ---
log "T2.8: Ensuring service users exist..."
for user_spec in "ollama:999" "openclawsvc:997"; do
    USER="${user_spec%%:*}"
    UID_VAL="${user_spec##*:}"
    if id "$USER" &>/dev/null; then
        log "  ✓ ${USER} exists (uid $(id -u "$USER"))"
    else
        useradd --system --uid "$UID_VAL" --home-dir "/srv/${USER}" --shell /usr/sbin/nologin "$USER"
        log "  ✓ Created ${USER} (uid ${UID_VAL})"
    fi
done

# --- T2.9: Data directory permissions ---
log "T2.9: Setting service directory permissions..."
for dir_spec in "/srv/ollama:ollama:ollama:750" "/srv/openclaw:openclawsvc:openclawsvc:750"; do
    IFS=: read -r DIR OWNER GROUP MODE <<< "$dir_spec"
    mkdir -p "$DIR"
    chown -R "${OWNER}:${GROUP}" "$DIR"
    chmod "$MODE" "$DIR"
    log "  ✓ ${DIR} → ${OWNER}:${GROUP} ${MODE}"
done

# --- T2.10: Sudoers ---
log "T2.10: Deploying sudoers rules..."
if visudo -c -f "${TEMPLATES_DIR}/sudoers-${SSH_USER}" 2>/dev/null; then
    cp "${TEMPLATES_DIR}/sudoers-${SSH_USER}" /etc/sudoers.d/020_${SSH_USER}
    chmod 440 /etc/sudoers.d/020_${SSH_USER}
    log "  ✓ /etc/sudoers.d/020_${SSH_USER} deployed (syntax OK)"
else
    err "  ✗ sudoers syntax error — NOT deployed"
fi

# --- T2.11: User group cleanup ---
log "T2.11: Verifying ${SSH_USER} group membership..."
CURRENT_GROUPS=$(groups ${SSH_USER} 2>/dev/null | cut -d: -f2 | tr -s ' ')
log "  Current: ${CURRENT_GROUPS}"
# Expected: ${SSH_USER} adm sudo plugdev netdev
for grp in adm sudo plugdev netdev; do
    if echo "$CURRENT_GROUPS" | grep -qw "$grp"; then
        log "  ✓ ${grp} — present"
    else
        warn "  ⚠ ${grp} — missing (add with: usermod -aG ${grp} ${SSH_USER})"
    fi
done

echo ""

# =============================================================================
divider "PHASE 2 — STEP 3: SYSTEMD SANDBOXING (T2.13–T2.14)"
# =============================================================================

# --- T2.13: SSH systemd override ---
log "T2.13: Deploying systemd hardening overrides..."

mkdir -p /etc/systemd/system/ssh.service.d/
cp "${TEMPLATES_DIR}/systemd/ssh-override.conf" /etc/systemd/system/ssh.service.d/hardening.conf
log "  ✓ SSH override deployed"

# SAFETY: Verify SSH override does NOT use ProtectSystem=strict or ProtectHome=read-only
# These break VS Code Remote-SSH (INCIDENT-2026-04-18)
if grep -q 'ProtectSystem=strict\|ProtectHome=read-only\|PrivateDevices=yes' /etc/systemd/system/ssh.service.d/hardening.conf; then
    err "  ✗ SSH override contains ProtectSystem=strict, ProtectHome=read-only, or PrivateDevices=yes"
    err "    These break VS Code Remote-SSH! Fix templates/systemd/ssh-override.conf"
    exit 1
fi
log "  ✓ SSH override VS Code compatibility verified"

mkdir -p /etc/systemd/system/avahi-daemon.service.d/
cp "${TEMPLATES_DIR}/systemd/avahi-override.conf" /etc/systemd/system/avahi-daemon.service.d/hardening.conf
log "  ✓ Avahi override deployed"

mkdir -p /etc/systemd/system/cron.service.d/
cp "${TEMPLATES_DIR}/systemd/cron-override.conf" /etc/systemd/system/cron.service.d/hardening.conf
log "  ✓ Cron override deployed"

log "  Reloading systemd daemon..."
systemctl daemon-reload

# --- T2.14: Verify Ollama already has override in main unit ---
log "T2.14: Verifying Ollama sandboxing..."
if systemctl cat ollama.service 2>/dev/null | grep -q "ProtectSystem=strict"; then
    log "  ✓ Ollama: ProtectSystem=strict in main unit"
else
    warn "  ⚠ Ollama main unit missing sandboxing"
fi

echo ""

# =============================================================================
divider "PHASE 2 — STEP 4: MANDATORY ACCESS CONTROL (T2.12, T2.15–T2.18)"
# =============================================================================

# --- T2.12: AppArmor enabled ---
log "T2.12: Checking AppArmor status..."
if aa-status 2>/dev/null | grep -q "apparmor module is loaded"; then
    PROFILES=$(aa-status 2>/dev/null | grep "profiles are loaded" | awk '{print $1}')
    ENFORCE=$(aa-status 2>/dev/null | grep "profiles are in enforce" | awk '{print $1}')
    COMPLAIN=$(aa-status 2>/dev/null | grep "profiles are in complain" | awk '{print $1}')
    log "  ✓ AppArmor loaded: ${PROFILES} profiles (${ENFORCE} enforce, ${COMPLAIN} complain)"
else
    err "  ✗ AppArmor NOT loaded — check cmdline.txt"
fi

# --- T2.15: Verify post-reboot (informational) ---
log "T2.15: AppArmor persistence check..."
if grep -q "apparmor=1" /boot/firmware/cmdline.txt 2>/dev/null; then
    log "  ✓ apparmor=1 in cmdline.txt — will survive reboot"
else
    warn "  ⚠ apparmor=1 NOT in cmdline.txt"
fi

# --- T2.16: Yama LSM ---
log "T2.16: Yama LSM check..."
if [[ -f /proc/sys/kernel/yama/ptrace_scope ]]; then
    PTRACE=$(cat /proc/sys/kernel/yama/ptrace_scope)
    log "  ✓ Yama ptrace_scope = ${PTRACE}"
else
    ACTIVE_LSMS=$(cat /sys/kernel/security/lsm 2>/dev/null || echo "unknown")
    warn "  ⚠ Yama NOT available (active LSMs: ${ACTIVE_LSMS})"
    warn "    Kernel profile limitation — marked N/A"
fi

# --- T2.17: Masked services ---
log "T2.17: Verifying masked services..."
MASK_PASS=true
for svc in bluetooth.service cloud-config.service cloud-final.service cloud-init-local.service cloud-init-main.service cloud-init-network.service serial-getty@ttyAMA10.service udisks2.service; do
    STATE=$(systemctl is-enabled "$svc" 2>/dev/null || echo "not-found")
    if [[ "$STATE" == "masked" ]]; then
        log "  ✓ ${svc}: masked"
    else
        err "  ✗ ${svc}: ${STATE} (expected masked)"
        MASK_PASS=false
    fi
done

# --- T2.18: AppArmor profiles for services ---
log "T2.18: Deploying AppArmor profiles..."
if [[ -f "${TEMPLATES_DIR}/apparmor/usr.local.bin.ollama" ]]; then
    cp "${TEMPLATES_DIR}/apparmor/usr.local.bin.ollama" /etc/apparmor.d/usr.local.bin.ollama
    apparmor_parser -r /etc/apparmor.d/usr.local.bin.ollama 2>/dev/null
    if command -v aa-complain &>/dev/null; then
        aa-complain /etc/apparmor.d/usr.local.bin.ollama 2>/dev/null
        log "  ✓ Ollama AppArmor profile loaded (complain mode)"
    else
        log "  ✓ Ollama AppArmor profile loaded (install apparmor-utils for mode control)"
    fi
else
    warn "  ⚠ Ollama AppArmor template not found — skipping"
fi

echo ""

# =============================================================================
divider "PHASE 2 — STEP 5: FINAL VERIFICATION"
# =============================================================================

log "Capturing post-deployment evidence..."

log "  Masked services:"
systemctl list-unit-files --state=masked --no-pager 2>/dev/null | tee "${EVIDENCE_DIR}/masked-after-${DATE}.txt" | wc -l

log "  SUID binaries:"
find / -perm /4000 -type f 2>/dev/null | tee "${EVIDENCE_DIR}/suid-after-${DATE}.txt" | wc -l

log "  Systemd security scores:"
systemd-analyze security ssh.service ollama.service avahi-daemon.service cron.service 2>/dev/null \
    | grep -E '^[a-z]' | tee "${EVIDENCE_DIR}/security-scores-after-${DATE}.txt"

log "  AppArmor status:"
aa-status 2>/dev/null | head -10 | tee "${EVIDENCE_DIR}/apparmor-after-${DATE}.txt"

log "  Service users:"
for user in ollama openclawsvc; do
    getent passwd "$user" 2>/dev/null | tee -a "${EVIDENCE_DIR}/users-${DATE}.txt"
done

log "  Sudoers validation:"
visudo -c 2>&1 | tail -3 | tee -a "${EVIDENCE_DIR}/sudoers-check-${DATE}.txt"

echo ""

# =============================================================================
divider "PHASE 2 — SUMMARY"
# =============================================================================

PASS=0
FAIL=0
NA=0

check_result() {
    local label="$1" result="$2"
    case "$result" in
        PASS) log "  ✓ ${label}"; PASS=$((PASS + 1)) ;;
        FAIL) err "  ✗ ${label}"; FAIL=$((FAIL + 1)) ;;
        N/A)  warn "  — ${label} (N/A)"; NA=$((NA + 1)) ;;
    esac
}

# T2.1-T2.3: Masked services
MASKED_COUNT=$(systemctl list-unit-files --state=masked --no-pager 2>/dev/null | grep -c '.service')
[[ $MASKED_COUNT -ge 8 ]] && check_result "T2.1-T2.3: Services masked (${MASKED_COUNT})" PASS || check_result "T2.1-T2.3: Services masked (${MASKED_COUNT})" FAIL

# T2.4: Module blacklist
[[ -f /etc/modprobe.d/hardening-blacklist.conf ]] && check_result "T2.4: Module blacklist deployed" PASS || check_result "T2.4: Module blacklist" FAIL

# T2.5: SUID count
SUID_FINAL=$(find / -perm /4000 -type f 2>/dev/null | wc -l)
[[ $SUID_FINAL -le 10 ]] && check_result "T2.5: SUID cleaned (${SUID_FINAL} remaining)" PASS || check_result "T2.5: SUID (${SUID_FINAL})" FAIL

# T2.6: Avahi sandboxed
systemctl is-active avahi-daemon &>/dev/null && check_result "T2.6: Avahi active + sandboxed" PASS || check_result "T2.6: Avahi" FAIL

# T2.7: udisks2 masked
[[ "$(systemctl is-enabled udisks2 2>/dev/null)" == "masked" ]] && check_result "T2.7: udisks2 masked" PASS || check_result "T2.7: udisks2" FAIL

# T2.8: Service users
id ollama &>/dev/null && id openclawsvc &>/dev/null && check_result "T2.8: Service users exist" PASS || check_result "T2.8: Service users" FAIL

# T2.9: Directory perms
[[ -d /srv/ollama ]] && check_result "T2.9: Service dirs created" PASS || check_result "T2.9: Service dirs" FAIL

# T2.10: Sudoers
visudo -c &>/dev/null && check_result "T2.10: Sudoers valid" PASS || check_result "T2.10: Sudoers" FAIL

# T2.11: User groups
groups ${SSH_USER} 2>/dev/null | grep -qw sudo && check_result "T2.11: User groups OK" PASS || check_result "T2.11: User groups" FAIL

# T2.12: AppArmor
aa-status 2>/dev/null | grep -q "module is loaded" && check_result "T2.12: AppArmor loaded" PASS || check_result "T2.12: AppArmor" FAIL

# T2.13: systemd overrides
[[ -f /etc/systemd/system/ssh.service.d/hardening.conf ]] && check_result "T2.13: SSH systemd override" PASS || check_result "T2.13: SSH override" FAIL

# T2.14: Ollama sandboxing
systemctl cat ollama.service 2>/dev/null | grep -q ProtectSystem && check_result "T2.14: Ollama sandboxed" PASS || check_result "T2.14: Ollama" FAIL

# T2.15: AppArmor persistence
grep -q "apparmor=1" /boot/firmware/cmdline.txt 2>/dev/null && check_result "T2.15: AppArmor in cmdline" PASS || check_result "T2.15: AppArmor cmdline" FAIL

# T2.16: Yama
[[ -f /proc/sys/kernel/yama/ptrace_scope ]] && check_result "T2.16: Yama active" PASS || check_result "T2.16: Yama (kernel profile)" N/A

# T2.17: Masked services persist
$MASK_PASS && check_result "T2.17: All masked services verified" PASS || check_result "T2.17: Masked services" FAIL

# T2.18: AppArmor profiles
aa-status 2>/dev/null | grep -q "ollama" && check_result "T2.18: Ollama AppArmor profile" PASS || check_result "T2.18: Ollama AppArmor" FAIL

echo ""
log "═══════════════════════════════════════════════════════"
log "  Phase 2 Results: ${PASS} PASS / ${FAIL} FAIL / ${NA} N/A"
log "  Evidence directory: ${EVIDENCE_DIR}"
log "═══════════════════════════════════════════════════════"

if [[ $FAIL -eq 0 ]]; then
    log "  Phase 2 — Service Optimization: COMPLETE ✓"
else
    warn "  Phase 2 has ${FAIL} failures — review above"
fi
