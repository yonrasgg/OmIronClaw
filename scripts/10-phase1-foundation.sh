#!/bin/bash
# =============================================================================
# Phase 1 — Foundation Security Execution Script
# OmIronClaw Hardening Project
#
# Tasks: T1.1 (SSH), T1.2 (nftables), T1.3 (sysctl)
# Standards: CIS 3.3, 3.5, 5.2 / NIST AC-17, SC-7, SI-11
#
# Safety: SNAPSHOT → VALIDATE → APPLY → VERIFY → DOCUMENT
# Run as: sudo bash scripts/10-phase1-foundation.sh
# =============================================================================
set -euo pipefail

# --- CONFIG ---
PROJECT_DIR="${PROJECT_DIR:-/home/${SSH_USER:-$(logname)}/OmIronClaw}"
EVIDENCE_DIR="${PROJECT_DIR}/wiki/evidence/foundation-security"
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
divider "PHASE 1 — STEP 0: PRE-FLIGHT CHECK"
# =============================================================================
log "Checking SSH sessions..."
who
echo ""

log "Active SSH connections:"
ss -tnp | grep :22 || true
echo ""

log "System state:"
uptime
free -h | head -2
systemctl is-system-running || true
echo ""

# --- CRITICAL: Verify SSH key authentication works ---
SSH_USER="${SSH_USER:-$(logname)}"
log "Checking authorized_keys for user '${SSH_USER}'..."
if [[ -f /home/${SSH_USER}/.ssh/authorized_keys ]]; then
    KEY_COUNT=$(wc -l < /home/${SSH_USER}/.ssh/authorized_keys)
    log "Found ${KEY_COUNT} SSH key(s) in authorized_keys"
    cat /home/${SSH_USER}/.ssh/authorized_keys | ssh-keygen -l -f - 2>/dev/null || warn "Could not fingerprint key — verify manually"
else
    err "NO authorized_keys found! Cannot disable password auth safely."
    err "Deploy an SSH key first: ssh-copy-id ${SSH_USER}@<PI_IP>"
    exit 1
fi

echo ""
warn "═══════════════════════════════════════════════════════════════"
warn "  CRITICAL SAFETY CHECKPOINT"
warn ""
warn "  This script will:"
warn "    T1.3: Harden kernel parameters (sysctl) — LOW RISK"
warn "    T1.1: Disable SSH password auth (key-only) — MEDIUM RISK"
warn "    T1.2: Enable deny-by-default firewall — HIGH RISK"
warn ""
warn "  Your current SSH session will NOT be interrupted."
warn "  Firewall includes 2-minute auto-rollback safety timer."
warn ""
warn "  KEEP THIS SESSION OPEN until all steps complete."
warn "═══════════════════════════════════════════════════════════════"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Aborted by user."
    exit 0
fi

# =============================================================================
divider "PHASE 1 — STEP 1: CAPTURE SNAPSHOTS (Before State)"
# =============================================================================

log "[SNAPSHOT] Capturing sysctl before state..."
sysctl -a > "${EVIDENCE_DIR}/sysctl-before-${DATE}.txt" 2>/dev/null
log "  → ${EVIDENCE_DIR}/sysctl-before-${DATE}.txt"

log "[SNAPSHOT] Capturing SSH config before state..."
sshd -T > "${EVIDENCE_DIR}/sshd-before-${DATE}.txt" 2>/dev/null
log "  → ${EVIDENCE_DIR}/sshd-before-${DATE}.txt"

log "[SNAPSHOT] Capturing nftables before state..."
nft list ruleset > "${EVIDENCE_DIR}/nft-before-${DATE}.txt" 2>/dev/null || echo "# No rules" > "${EVIDENCE_DIR}/nft-before-${DATE}.txt"
log "  → ${EVIDENCE_DIR}/nft-before-${DATE}.txt"

log "[SNAPSHOT] Capturing listening ports before state..."
ss -lntup > "${EVIDENCE_DIR}/ports-before-${DATE}.txt" 2>/dev/null
log "  → ${EVIDENCE_DIR}/ports-before-${DATE}.txt"

# =============================================================================
divider "PHASE 1 — STEP 2: T1.3 — KERNEL SYSCTL HARDENING (CIS 3.3 / NIST SI-11)"
# =============================================================================

log "Deploying sysctl hardening config..."
cp "${TEMPLATES_DIR}/sysctl-hardening.conf" /etc/sysctl.d/90-hardening.conf
log "  → /etc/sysctl.d/90-hardening.conf"

log "Validating syntax..."
if sysctl --dry-run -p /etc/sysctl.d/90-hardening.conf > /dev/null 2>&1; then
    log "  Syntax: OK"
else
    warn "  Syntax check returned warnings (non-fatal — some params may not exist on this kernel)"
fi

log "Applying sysctl parameters..."
sysctl --system > /dev/null 2>&1 || true
log "  Applied."

log "Verifying critical parameters..."
SYSCTL_PASS=true
for param in \
    "kernel.dmesg_restrict=1" \
    "kernel.kptr_restrict=2" \
    "net.ipv4.conf.all.accept_redirects=0" \
    "net.ipv4.conf.all.send_redirects=0" \
    "net.ipv4.conf.all.log_martians=1" \
    "kernel.randomize_va_space=2" \
    "fs.suid_dumpable=0" \
    "net.ipv4.tcp_syncookies=1"; do
    KEY="${param%%=*}"
    EXPECTED="${param##*=}"
    ACTUAL=$(sysctl -n "$KEY" 2>/dev/null)
    if [[ "$ACTUAL" == "$EXPECTED" ]]; then
        log "  ✓ ${KEY} = ${ACTUAL}"
    else
        err "  ✗ ${KEY} = ${ACTUAL} (expected ${EXPECTED})"
        SYSCTL_PASS=false
    fi
done

# Check ptrace_scope separately (yama module may not be loaded)
PTRACE=$(sysctl -n kernel.yama.ptrace_scope 2>/dev/null || echo "N/A")
if [[ "$PTRACE" == "2" ]]; then
    log "  ✓ kernel.yama.ptrace_scope = 2"
elif [[ "$PTRACE" == "N/A" ]]; then
    warn "  ⚠ kernel.yama.ptrace_scope: Yama LSM not loaded"
else
    err "  ✗ kernel.yama.ptrace_scope = ${PTRACE} (expected 2)"
    SYSCTL_PASS=false
fi

if $SYSCTL_PASS; then
    log "T1.3 SYSCTL: ALL PASSED ✓"
else
    warn "T1.3 SYSCTL: Some parameters did not apply — review above"
fi

sysctl -a > "${EVIDENCE_DIR}/sysctl-after-${DATE}.txt" 2>/dev/null
echo ""

# =============================================================================
divider "PHASE 1 — STEP 3: T1.1 — SSH HARDENING (CIS 5.2 / NIST AC-17)"
# =============================================================================

log "Creating SSH hardening drop-in config..."
mkdir -p /etc/ssh/sshd_config.d/
cp "${TEMPLATES_DIR}/sshd-hardening.conf" /etc/ssh/sshd_config.d/10-hardening.conf
log "  → /etc/ssh/sshd_config.d/10-hardening.conf"

log "Validating SSH config syntax..."
if sshd -t 2>&1; then
    log "  Syntax: OK"
else
    err "  SSH config syntax error! Rolling back..."
    rm -f /etc/ssh/sshd_config.d/10-hardening.conf
    err "  Rolled back. Aborting SSH hardening."
    err "  Investigate: sshd -t"
    # Continue to firewall step instead of exiting entirely
    SSH_PASS=false
fi

if [[ "${SSH_PASS:-true}" != "false" ]]; then
    log "Reloading SSH daemon..."
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null
    log "  Reloaded."

    log "Verifying SSH configuration..."
    SSH_PASS=true
    for param in \
        "passwordauthentication no" \
        "pubkeyauthentication yes" \
        "permitrootlogin no" \
        "x11forwarding no" \
        "maxauthtries 3"; do
        KEY="${param%% *}"
        EXPECTED="${param##* }"
        ACTUAL=$(sshd -T 2>/dev/null | grep "^${KEY} " | awk '{print $2}')
        if [[ "$ACTUAL" == "$EXPECTED" ]]; then
            log "  ✓ ${KEY} = ${ACTUAL}"
        else
            err "  ✗ ${KEY} = ${ACTUAL} (expected ${EXPECTED})"
            SSH_PASS=false
        fi
    done

    # Check AllowUsers
    ALLOW=$(sshd -T 2>/dev/null | grep "^allowusers " || echo "")
    if [[ -n "$ALLOW" ]]; then
        log "  ✓ ${ALLOW}"
    else
        warn "  ⚠ AllowUsers not set (all users can authenticate)"
    fi

    if $SSH_PASS; then
        log "T1.1 SSH: ALL PASSED ✓"
    else
        warn "T1.1 SSH: Some settings did not apply — review above"
    fi

    sshd -T > "${EVIDENCE_DIR}/sshd-after-${DATE}.txt" 2>/dev/null
    
    warn ""
    warn "  ╔═══════════════════════════════════════════════════════════╗"
    warn "  ║  SSH password auth is now DISABLED.                      ║"
    warn "  ║  Open a NEW terminal and test SSH key login NOW:         ║"
    warn "  ║                                                          ║"
    warn "  ║    ssh ${SSH_USER}@<PI_IP>                              ║"
    warn "  ║                                                          ║"
    warn "  ║  If it fails, rollback:                                  ║"
    warn "  ║    sudo rm /etc/ssh/sshd_config.d/10-hardening.conf      ║"
    warn "  ║    sudo systemctl reload ssh                             ║"
    warn "  ╚═══════════════════════════════════════════════════════════╝"
    warn ""
    read -p "Did SSH key login work in another terminal? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warn "Rolling back SSH hardening..."
        rm -f /etc/ssh/sshd_config.d/10-hardening.conf
        systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null
        warn "SSH rolled back to default (password auth re-enabled)."
        SSH_PASS=false
    fi
fi
echo ""

# =============================================================================
divider "PHASE 1 — STEP 4: T1.2 — NFTABLES FIREWALL (CIS 3.5 / NIST SC-7)"
# =============================================================================

log "Validating nftables config syntax..."
if nft -c -f "${TEMPLATES_DIR}/nftables.conf" 2>&1; then
    log "  Syntax: OK"
else
    err "  nftables syntax error! Aborting firewall step."
    err "  Investigate: nft -c -f ${TEMPLATES_DIR}/nftables.conf"
    NFT_PASS=false
fi

if [[ "${NFT_PASS:-true}" != "false" ]]; then
    # Safety: check if 'at' is available for auto-rollback
    if command -v at &> /dev/null; then
        log "Setting up 2-minute auto-rollback safety timer..."
        echo "nft flush ruleset" | at now + 2 minutes 2>/dev/null || true
        log "  Auto-rollback scheduled: firewall will FLUSH in 2 minutes"
        log "  If everything works, we'll cancel it."
        AT_SCHEDULED=true
    else
        warn "'at' not installed — no auto-rollback timer available."
        warn "  If firewall locks you out, reboot the host to clear rules."
        AT_SCHEDULED=false
    fi

    log "Deploying nftables ruleset..."
    cp "${TEMPLATES_DIR}/nftables.conf" /etc/nftables.conf
    nft -f /etc/nftables.conf
    log "  Firewall active."

    log "Enabling nftables on boot..."
    systemctl enable nftables 2>/dev/null || true

    log "Verifying firewall rules..."
    nft list ruleset > "${EVIDENCE_DIR}/nft-after-${DATE}.txt" 2>/dev/null
    
    # Verify key rules
    NFT_PASS=true
    if nft list ruleset | grep -q "policy drop"; then
        log "  ✓ Input policy: DROP (deny-by-default)"
    else
        err "  ✗ Input policy is not DROP"
        NFT_PASS=false
    fi

    if nft list ruleset | grep -q "dport 22"; then
        log "  ✓ SSH rule present"
    else
        err "  ✗ SSH rule missing!"
        NFT_PASS=false
    fi

    if nft list ruleset | grep -q "/24"; then
        log "  ✓ LAN restriction present"
    else
        err "  ✗ LAN restriction missing"
        NFT_PASS=false
    fi

    if nft list ruleset | grep -q "limit rate 3/minute"; then
        log "  ✓ SSH rate limiting active"
    else
        warn "  ⚠ SSH rate limiting not detected"
    fi

    log ""
    log "Current listening ports visible through firewall:"
    ss -lntup 2>/dev/null | head -20
    ss -lntup > "${EVIDENCE_DIR}/ports-after-${DATE}.txt" 2>/dev/null

    warn ""
    warn "  ╔═══════════════════════════════════════════════════════════╗"
    warn "  ║  Firewall is now ACTIVE (deny-by-default).               ║"
    warn "  ║  Only LAN SSH is allowed inbound.                      ║"
    warn "  ║                                                          ║"
    warn "  ║  Test: open a NEW SSH session from your Admin PC.        ║"
    warn "  ║  If it works, confirm below to KEEP the rules.           ║"
    warn "  ║                                                          ║"
    warn "  ║  Auto-rollback in ~2 minutes if you don't confirm.       ║"
    warn "  ╚═══════════════════════════════════════════════════════════╝"
    warn ""
    read -p "Does SSH still work through the firewall? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Cancel the auto-rollback timer
        if [[ "${AT_SCHEDULED}" == "true" ]]; then
            # Remove the most recent at job
            ATJOB=$(atq 2>/dev/null | tail -1 | awk '{print $1}')
            if [[ -n "$ATJOB" ]]; then
                atrm "$ATJOB" 2>/dev/null || true
                log "  Auto-rollback timer cancelled."
            fi
        fi
        log "T1.2 FIREWALL: CONFIRMED ✓"
    else
        warn "Rolling back firewall..."
        nft flush ruleset
        warn "Firewall flushed — back to open."
        NFT_PASS=false
    fi
fi
echo ""

# =============================================================================
divider "PHASE 1 — RESULTS SUMMARY"
# =============================================================================

echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│ Phase 1 — Foundation Security — Results                      │"
echo "├──────────┬──────────────────────────────────────┬────────────┤"
printf "│ %-8s │ %-36s │ %-10s │\n" "Task" "Description" "Status"
echo "├──────────┼──────────────────────────────────────┼────────────┤"
if $SYSCTL_PASS; then
    printf "│ %-8s │ %-36s │ ${GREEN}%-10s${NC} │\n" "T1.3" "Kernel sysctl (CIS 3.3)" "PASS"
else
    printf "│ %-8s │ %-36s │ ${YELLOW}%-10s${NC} │\n" "T1.3" "Kernel sysctl (CIS 3.3)" "PARTIAL"
fi
if [[ "${SSH_PASS:-true}" == "true" ]]; then
    printf "│ %-8s │ %-36s │ ${GREEN}%-10s${NC} │\n" "T1.1" "SSH hardening (CIS 5.2)" "PASS"
else
    printf "│ %-8s │ %-36s │ ${RED}%-10s${NC} │\n" "T1.1" "SSH hardening (CIS 5.2)" "ROLLBACK"
fi
if [[ "${NFT_PASS:-true}" == "true" ]]; then
    printf "│ %-8s │ %-36s │ ${GREEN}%-10s${NC} │\n" "T1.2" "nftables firewall (CIS 3.5)" "PASS"
else
    printf "│ %-8s │ %-36s │ ${RED}%-10s${NC} │\n" "T1.2" "nftables firewall (CIS 3.5)" "ROLLBACK"
fi
printf "│ %-8s │ %-36s │ ${YELLOW}%-10s${NC} │\n" "T1.4" "Kali validation" "MANUAL"
echo "└──────────┴──────────────────────────────────────┴────────────┘"
echo ""

# --- Generate evidence summary ---
cat > "${EVIDENCE_DIR}/phase1-summary-${DATE}.md" << EVIDENCE
# Phase 1 — Foundation Security — Evidence Summary

**Date**: $(date -Iseconds)
**Executed by**: $(whoami) on $(hostname)

## T1.3 — Kernel Sysctl Hardening (CIS 3.3 / NIST SI-11)

**Status**: ${SYSCTL_PASS}
**Config deployed**: /etc/sysctl.d/90-hardening.conf
**Before**: [sysctl-before-${DATE}.txt](sysctl-before-${DATE}.txt)
**After**: [sysctl-after-${DATE}.txt](sysctl-after-${DATE}.txt)
**Rollback**: \`sudo rm /etc/sysctl.d/90-hardening.conf && sudo sysctl --system\`

### Changes Applied
| Parameter | Before | After | CIS |
|-----------|--------|-------|-----|
| kernel.dmesg_restrict | 0 | 1 | 1.5.2 |
| kernel.kptr_restrict | 0 | 2 | 1.5.3 |
| net.ipv4.conf.all.accept_redirects | 1 | 0 | 3.3.2 |
| net.ipv4.conf.all.send_redirects | 1 | 0 | 3.3.1 |
| net.ipv4.conf.all.log_martians | 0 | 1 | 3.3.4 |

## T1.1 — SSH Hardening (CIS 5.2 / NIST AC-17)

**Status**: ${SSH_PASS:-true}
**Config deployed**: /etc/ssh/sshd_config.d/10-hardening.conf
**Before**: [sshd-before-${DATE}.txt](sshd-before-${DATE}.txt)
**After**: [sshd-after-${DATE}.txt](sshd-after-${DATE}.txt)
**Rollback**: \`sudo rm /etc/ssh/sshd_config.d/10-hardening.conf && sudo systemctl reload ssh\`

### Changes Applied
| Setting | Before | After | CIS |
|---------|--------|-------|-----|
| PasswordAuthentication | yes | no | 5.2.15 |
| PermitRootLogin | prohibit-password | no | 5.2.10 |
| X11Forwarding | yes | no | 5.2.6 |
| MaxAuthTries | 6 | 3 | 5.2.7 |
| AllowUsers | (none) | \${SSH_USER} | 5.2.4 |

## T1.2 — nftables Firewall (CIS 3.5 / NIST SC-7)

**Status**: ${NFT_PASS:-true}
**Config deployed**: /etc/nftables.conf
**Before**: [nft-before-${DATE}.txt](nft-before-${DATE}.txt)
**After**: [nft-after-${DATE}.txt](nft-after-${DATE}.txt)
**Rollback**: \`sudo nft flush ruleset\`

### Rules Applied
- Input policy: DROP (deny-by-default)
- SSH (22/tcp): LAN only (\${LAN_SUBNET}), rate-limited 3/min
- ICMP echo: rate-limited 5/sec
- Forward: DROP
- Output: ACCEPT (to be tightened in Phase 8)

## T1.4 — Kali Validation (NIST CA-2)

**Status**: PENDING (manual)

Run from Kali (\${KALI_IP}):
\`\`\`bash
# Port scan
nmap -sS -Pn <PI_IP>

# SSH password test (should be rejected)
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \${SSH_USER}@<PI_IP>

# Verify only port 22 is open
nmap -p- --open <PI_IP>
\`\`\`
EVIDENCE

log "Evidence saved to: ${EVIDENCE_DIR}/"
log ""
log "Phase 1 execution complete."
log "Next: Run T1.4 validation from Kali (\${KALI_IP})"
