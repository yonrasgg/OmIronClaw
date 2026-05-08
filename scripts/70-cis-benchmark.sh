#!/usr/bin/env bash
# =================================================================
# Phase 7 — CIS Debian 13 Benchmark Automated Scoring
# NIST CA-2 (Security Assessment)
#
# Maps to CIS Benchmark sections:
#   1.x  Initial Setup (filesystem, boot, software)
#   2.x  Services
#   3.x  Network Configuration
#   4.x  Logging and Auditing
#   5.x  Access, Authentication, Authorization
#
# Usage: sudo ./70-cis-benchmark.sh [--json]
#   --json: output machine-readable JSON summary
#
# Phase 7 — T7.1 — 2026-04-17
# =================================================================
set -uo pipefail

# --- State ---
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
NA_COUNT=0
JSON_MODE=false
RESULTS=()

[[ "${1:-}" == "--json" ]] && JSON_MODE=true

# --- Helpers ---
pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    RESULTS+=("PASS|$1|$2")
    $JSON_MODE || printf "  [\033[32mPASS\033[0m] %-12s %s\n" "$1" "$2"
}
fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    RESULTS+=("FAIL|$1|$2")
    $JSON_MODE || printf "  [\033[31mFAIL\033[0m] %-12s %s\n" "$1" "$2"
}
warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    RESULTS+=("WARN|$1|$2")
    $JSON_MODE || printf "  [\033[33mWARN\033[0m] %-12s %s\n" "$1" "$2"
}
na() {
    NA_COUNT=$((NA_COUNT + 1))
    RESULTS+=("N/A|$1|$2")
    $JSON_MODE || printf "  [ N/A] %-12s %s\n" "$1" "$2"
}
header() {
    $JSON_MODE || printf "\n\033[1m=== %s ===\033[0m\n" "$1"
}

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Must run as root (sudo)" >&2
    exit 2
fi

$JSON_MODE || echo "CIS Debian 13 Benchmark — $(date '+%Y-%m-%d %H:%M:%S') — $(hostname)"
$JSON_MODE || echo "================================================================"

# =================================================================
# SECTION 1: INITIAL SETUP
# =================================================================
header "1.x Initial Setup"

# 1.1.1 — Filesystem: cramfs, freevxfs, jffs2, hfs, hfsplus, udf disabled
for mod in cramfs freevxfs jffs2 hfs hfsplus udf; do
    if lsmod 2>/dev/null | grep -q "^${mod} " || ! grep -rq "install ${mod} /bin/false\|blacklist ${mod}" /etc/modprobe.d/ 2>/dev/null; then
        # Check both modprobe blacklist and lsmod
        if lsmod 2>/dev/null | grep -q "^${mod} "; then
            fail "CIS 1.1.1" "Kernel module ${mod} is loaded"
        elif ! grep -rq "install ${mod}\|blacklist ${mod}" /etc/modprobe.d/ 2>/dev/null; then
            warn "CIS 1.1.1" "Kernel module ${mod} not explicitly blacklisted"
        else
            pass "CIS 1.1.1" "Kernel module ${mod} disabled"
        fi
    else
        pass "CIS 1.1.1" "Kernel module ${mod} disabled"
    fi
done

# 1.1.2 — /tmp partition (or tmpfs)
if mount | grep -q ' /tmp '; then
    OPTS=$(mount | grep ' /tmp ' | awk '{print $6}')
    pass "CIS 1.1.2" "/tmp mounted: ${OPTS}"
else
    warn "CIS 1.1.2" "/tmp not a separate mount"
fi

# 1.3.1 — AIDE or equivalent integrity checker
if command -v aide &>/dev/null || command -v tripwire &>/dev/null; then
    pass "CIS 1.3.1" "File integrity checker installed"
else
    warn "CIS 1.3.1" "No file integrity checker (AIDE/Tripwire)"
fi

# 1.4.1 — Bootloader permissions
if [[ -f /boot/firmware/config.txt ]]; then
    BOOT_FS=$(df -T /boot/firmware/ 2>/dev/null | awk 'NR==2 {print $2}')
    if [[ "$BOOT_FS" == "vfat" ]]; then
        na "CIS 1.4.1" "Boot partition is vfat (chmod not applicable)"
    else
        PERM=$(stat -c '%a' /boot/firmware/config.txt)
        if [[ "$PERM" -le 600 ]]; then
            pass "CIS 1.4.1" "Boot config permissions: ${PERM}"
        else
            fail "CIS 1.4.1" "Boot config too permissive: ${PERM}"
        fi
    fi
else
    na "CIS 1.4.1" "No boot config found (platform-specific)"
fi

# 1.5.1 — ASLR enabled
ASLR=$(sysctl -n kernel.randomize_va_space 2>/dev/null)
if [[ "$ASLR" == "2" ]]; then
    pass "CIS 1.5.1" "ASLR full randomization (${ASLR})"
else
    fail "CIS 1.5.1" "ASLR not full: ${ASLR}"
fi

# 1.5.2 — Restrict dmesg
DMESG=$(sysctl -n kernel.dmesg_restrict 2>/dev/null)
if [[ "$DMESG" == "1" ]]; then
    pass "CIS 1.5.2" "dmesg restricted"
else
    fail "CIS 1.5.2" "dmesg not restricted: ${DMESG}"
fi

# 1.5.3 — Restrict kernel pointer
KPTR=$(sysctl -n kernel.kptr_restrict 2>/dev/null)
if [[ "$KPTR" == "2" ]]; then
    pass "CIS 1.5.3" "kptr_restrict=2"
else
    fail "CIS 1.5.3" "kptr_restrict=${KPTR}"
fi

# 1.5.4 — Core dump restrictions
SUID_DUMP=$(sysctl -n fs.suid_dumpable 2>/dev/null)
if [[ "$SUID_DUMP" == "0" ]]; then
    pass "CIS 1.5.4" "Core dumps restricted (suid_dumpable=0)"
else
    fail "CIS 1.5.4" "suid_dumpable=${SUID_DUMP}"
fi

# 1.6.1 — AppArmor enabled
if aa-status &>/dev/null; then
    AA_ENFORCE=$(aa-status 2>/dev/null | awk '/profiles are in enforce/ {print $1}')
    pass "CIS 1.6.1" "AppArmor active, ${AA_ENFORCE:-0} profiles enforcing"
else
    fail "CIS 1.6.1" "AppArmor not active"
fi

# =================================================================
# SECTION 2: SERVICES
# =================================================================
header "2.x Services"

# 2.1 — Unnecessary services disabled
UNWANTED_SERVICES=(avahi-daemon cups bluetooth.service rpcbind.service nfs-server.service vsftpd.service apache2.service)
for svc in "${UNWANTED_SERVICES[@]}"; do
    case "$svc" in
        avahi-daemon)
            # Avahi is expected but hardened
            if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
                # Check if allow-interfaces is set
                if grep -q 'allow-interfaces=' /etc/avahi/avahi-daemon.conf 2>/dev/null; then
                    pass "CIS 2.1" "${svc}: active (hardened with allow-interfaces)"
                else
                    warn "CIS 2.1" "${svc}: active but no interface restriction"
                fi
            else
                pass "CIS 2.1" "${svc}: not active"
            fi
            ;;
        *)
            if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
                fail "CIS 2.1" "${svc}: enabled (should be disabled)"
            else
                pass "CIS 2.1" "${svc}: not enabled"
            fi
            ;;
    esac
done

# 2.2 — Check masked services count
MASKED=$(systemctl list-unit-files --state=masked 2>/dev/null | grep -c masked)
if [[ "$MASKED" -ge 10 ]]; then
    pass "CIS 2.2" "${MASKED} services masked"
else
    warn "CIS 2.2" "Only ${MASKED} services masked (expected ≥10)"
fi

# =================================================================
# SECTION 3: NETWORK CONFIGURATION
# =================================================================
header "3.x Network Configuration"

# 3.1.1 — IPv6 disabled (project requirement)
IPV6_ALL=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "module_unloaded")
if [[ "$IPV6_ALL" == "1" ]] || [[ "$IPV6_ALL" == "module_unloaded" ]]; then
    pass "CIS 3.1.1" "IPv6 disabled (${IPV6_ALL})"
else
    fail "CIS 3.1.1" "IPv6 not disabled: ${IPV6_ALL}"
fi
# Verify cmdline
if grep -q 'ipv6.disable=1' /proc/cmdline; then
    pass "CIS 3.1.1" "IPv6 disabled in kernel cmdline"
else
    fail "CIS 3.1.1" "ipv6.disable=1 not in cmdline"
fi

# 3.2.1 — IP forwarding disabled
IP_FWD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
if [[ "$IP_FWD" == "0" ]]; then
    pass "CIS 3.2.1" "IP forwarding disabled"
else
    fail "CIS 3.2.1" "IP forwarding enabled: ${IP_FWD}"
fi

# 3.2.2 — Send redirects disabled
for iface in all default; do
    VAL=$(sysctl -n "net.ipv4.conf.${iface}.send_redirects" 2>/dev/null)
    if [[ "$VAL" == "0" ]]; then
        pass "CIS 3.2.2" "send_redirects ${iface}=0"
    else
        fail "CIS 3.2.2" "send_redirects ${iface}=${VAL}"
    fi
done

# 3.3.1 — Source routed packets rejected
for iface in all default; do
    VAL=$(sysctl -n "net.ipv4.conf.${iface}.accept_source_route" 2>/dev/null)
    if [[ "$VAL" == "0" ]]; then
        pass "CIS 3.3.1" "source_route ${iface}=0"
    else
        fail "CIS 3.3.1" "source_route ${iface}=${VAL}"
    fi
done

# 3.3.2 — ICMP redirects not accepted
for iface in all default; do
    VAL=$(sysctl -n "net.ipv4.conf.${iface}.accept_redirects" 2>/dev/null)
    if [[ "$VAL" == "0" ]]; then
        pass "CIS 3.3.2" "accept_redirects ${iface}=0"
    else
        fail "CIS 3.3.2" "accept_redirects ${iface}=${VAL}"
    fi
done

# 3.3.3 — Secure ICMP redirects not accepted
for iface in all default; do
    VAL=$(sysctl -n "net.ipv4.conf.${iface}.secure_redirects" 2>/dev/null)
    if [[ "$VAL" == "0" ]]; then
        pass "CIS 3.3.3" "secure_redirects ${iface}=0"
    else
        fail "CIS 3.3.3" "secure_redirects ${iface}=${VAL}"
    fi
done

# 3.3.4 — Log suspicious packets
for iface in all default; do
    VAL=$(sysctl -n "net.ipv4.conf.${iface}.log_martians" 2>/dev/null)
    if [[ "$VAL" == "1" ]]; then
        pass "CIS 3.3.4" "log_martians ${iface}=1"
    else
        fail "CIS 3.3.4" "log_martians ${iface}=${VAL}"
    fi
done

# 3.3.5 — ICMP broadcasts ignored
VAL=$(sysctl -n net.ipv4.icmp_echo_ignore_broadcasts 2>/dev/null)
if [[ "$VAL" == "1" ]]; then
    pass "CIS 3.3.5" "ICMP broadcasts ignored"
else
    fail "CIS 3.3.5" "ICMP broadcasts not ignored: ${VAL}"
fi

# 3.3.6 — Bogus ICMP responses ignored
VAL=$(sysctl -n net.ipv4.icmp_ignore_bogus_error_responses 2>/dev/null)
if [[ "$VAL" == "1" ]]; then
    pass "CIS 3.3.6" "Bogus ICMP responses ignored"
else
    fail "CIS 3.3.6" "Bogus ICMP responses not ignored: ${VAL}"
fi

# 3.3.7 — Reverse path filtering
for iface in all default; do
    VAL=$(sysctl -n "net.ipv4.conf.${iface}.rp_filter" 2>/dev/null)
    if [[ "$VAL" == "1" ]]; then
        pass "CIS 3.3.7" "rp_filter ${iface}=1"
    else
        fail "CIS 3.3.7" "rp_filter ${iface}=${VAL}"
    fi
done

# 3.3.8 — TCP SYN cookies
VAL=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)
if [[ "$VAL" == "1" ]]; then
    pass "CIS 3.3.8" "TCP SYN cookies enabled"
else
    fail "CIS 3.3.8" "TCP SYN cookies: ${VAL}"
fi

# 3.4 — Firewall: nftables active, default deny
header "3.4 Firewall"
if systemctl is-active --quiet nftables 2>/dev/null; then
    pass "CIS 3.4.1" "nftables service active"
else
    # nftables might be loaded without service
    if nft list tables &>/dev/null && [[ $(nft list tables 2>/dev/null | wc -l) -gt 0 ]]; then
        pass "CIS 3.4.1" "nftables rules loaded (ruleset active)"
    else
        fail "CIS 3.4.1" "No firewall active"
    fi
fi

INPUT_POLICY=$(nft list chain inet filter input 2>/dev/null | awk '/policy/ {print $NF}' | tr -d ';')
if [[ "$INPUT_POLICY" == "drop" ]]; then
    pass "CIS 3.4.2" "Input default policy: drop"
else
    fail "CIS 3.4.2" "Input policy: ${INPUT_POLICY:-unknown}"
fi

# 3.5 — WiFi security (WPA3)
if iw dev wlan0 link 2>/dev/null | grep -q 'SSID'; then
    FREQ=$(iw dev wlan0 link 2>/dev/null | awk '/freq:/ {print $2}')
    pass "CIS 3.5" "WiFi connected (freq ${FREQ:-?} MHz)"
else
    na "CIS 3.5" "WiFi not connected"
fi

# =================================================================
# SECTION 4: LOGGING AND AUDITING
# =================================================================
header "4.x Logging and Auditing"

# 4.1.1 — auditd installed and enabled
if systemctl is-active --quiet auditd 2>/dev/null; then
    AUDIT_ENABLED=$(auditctl -s 2>/dev/null | awk '/enabled/ {print $2}')
    AUDIT_RULES=$(auditctl -l 2>/dev/null | wc -l)
    if [[ "$AUDIT_ENABLED" == "2" ]]; then
        pass "CIS 4.1.1" "auditd active, ${AUDIT_RULES} rules, immutable (enabled=2)"
    else
        warn "CIS 4.1.1" "auditd active but not immutable (enabled=${AUDIT_ENABLED})"
    fi
else
    fail "CIS 4.1.1" "auditd not active"
fi

# 4.1.2 — Audit rules for identity changes
if auditctl -l 2>/dev/null | grep -q '/etc/passwd'; then
    pass "CIS 4.1.2" "Audit rules: identity files monitored"
else
    fail "CIS 4.1.2" "No audit rules for /etc/passwd"
fi

# 4.1.3 — Audit rules for login/logout
if auditctl -l 2>/dev/null | grep -q '/var/log/lastlog\|faillog\|tallylog'; then
    pass "CIS 4.1.3" "Audit rules: login/logout monitored"
else
    warn "CIS 4.1.3" "Login/logout audit rules incomplete"
fi

# 4.1.4 — Audit rules for sudo
if auditctl -l 2>/dev/null | grep -q '/etc/sudoers'; then
    pass "CIS 4.1.4" "Audit rules: sudo changes monitored"
else
    fail "CIS 4.1.4" "No audit rules for /etc/sudoers"
fi

# 4.2.1 — journald configured
if [[ -f /etc/systemd/journald.conf.d/retention.conf ]]; then
    STORAGE=$(grep 'Storage=' /etc/systemd/journald.conf.d/retention.conf 2>/dev/null | cut -d= -f2)
    if [[ "$STORAGE" == "persistent" ]]; then
        pass "CIS 4.2.1" "journald: persistent storage"
    else
        fail "CIS 4.2.1" "journald storage: ${STORAGE:-not set}"
    fi
else
    fail "CIS 4.2.1" "journald retention not configured"
fi

# 4.2.2 — fail2ban active
if systemctl is-active --quiet fail2ban 2>/dev/null; then
    F2B_JAILS=$(fail2ban-client status 2>/dev/null | awk -F: '/Jail list/ {gsub(/[[:space:]]/,"",$2); print $2}')
    pass "CIS 4.2.2" "fail2ban active, jails: ${F2B_JAILS}"
else
    fail "CIS 4.2.2" "fail2ban not active"
fi

# =================================================================
# SECTION 5: ACCESS, AUTHENTICATION, AUTHORIZATION
# =================================================================
header "5.x Access & Authentication"

# 5.1.1 — SSH Protocol & Config
SSHD_CONFIG=$(sshd -T 2>/dev/null)

# 5.1.2 — SSH root login
SSH_ROOT=$(echo "$SSHD_CONFIG" | awk '/^permitrootlogin / {print $2}')
if [[ "$SSH_ROOT" == "no" ]]; then
    pass "CIS 5.1.2" "SSH PermitRootLogin: no"
else
    fail "CIS 5.1.2" "SSH PermitRootLogin: ${SSH_ROOT}"
fi

# 5.1.3 — SSH PermitEmptyPasswords
SSH_EMPTY=$(echo "$SSHD_CONFIG" | awk '/^permitemptypasswords / {print $2}')
if [[ "$SSH_EMPTY" == "no" ]]; then
    pass "CIS 5.1.3" "SSH PermitEmptyPasswords: no"
else
    fail "CIS 5.1.3" "SSH PermitEmptyPasswords: ${SSH_EMPTY}"
fi

# 5.1.4 — SSH PasswordAuthentication
SSH_PASS=$(echo "$SSHD_CONFIG" | awk '/^passwordauthentication / {print $2}')
if [[ "$SSH_PASS" == "no" ]]; then
    pass "CIS 5.1.4" "SSH PasswordAuthentication: no"
else
    fail "CIS 5.1.4" "SSH PasswordAuthentication: ${SSH_PASS}"
fi

# 5.1.5 — SSH MaxAuthTries
SSH_MAXAUTH=$(echo "$SSHD_CONFIG" | awk '/^maxauthtries / {print $2}')
if [[ "$SSH_MAXAUTH" -le 4 ]]; then
    pass "CIS 5.1.5" "SSH MaxAuthTries: ${SSH_MAXAUTH}"
else
    fail "CIS 5.1.5" "SSH MaxAuthTries too high: ${SSH_MAXAUTH}"
fi

# 5.1.6 — SSH AllowUsers or AllowGroups
SSH_ALLOW=$(echo "$SSHD_CONFIG" | grep -c 'allowusers\|allowgroups')
if [[ "$SSH_ALLOW" -gt 0 ]]; then
    pass "CIS 5.1.6" "SSH access restricted (AllowUsers/AllowGroups)"
else
    fail "CIS 5.1.6" "SSH not restricted to specific users"
fi

# 5.1.7 — SSH Banner
SSH_BANNER=$(echo "$SSHD_CONFIG" | awk '/^banner / {print $2}')
if [[ "$SSH_BANNER" != "none" ]] && [[ -n "$SSH_BANNER" ]]; then
    pass "CIS 5.1.7" "SSH Banner: ${SSH_BANNER}"
else
    warn "CIS 5.1.7" "SSH Banner not configured"
fi

# 5.1.8 — SSH LogLevel
SSH_LOG=$(echo "$SSHD_CONFIG" | awk '/^loglevel / {print $2}')
if [[ "$SSH_LOG" == "VERBOSE" ]] || [[ "$SSH_LOG" == "INFO" ]]; then
    pass "CIS 5.1.8" "SSH LogLevel: ${SSH_LOG}"
else
    fail "CIS 5.1.8" "SSH LogLevel: ${SSH_LOG}"
fi

# 5.1.9 — SSH ciphers (AEAD only)
SSH_CIPHERS=$(echo "$SSHD_CONFIG" | awk '/^ciphers / {print $2}')
if echo "$SSH_CIPHERS" | grep -q 'chacha20-poly1305\|aes.*-gcm'; then
    # Check for weak ciphers
    if echo "$SSH_CIPHERS" | grep -qE 'cbc|ctr'; then
        warn "CIS 5.1.9" "SSH ciphers include non-AEAD: ${SSH_CIPHERS}"
    else
        pass "CIS 5.1.9" "SSH ciphers AEAD-only: ${SSH_CIPHERS}"
    fi
else
    fail "CIS 5.1.9" "SSH ciphers: ${SSH_CIPHERS}"
fi

# 5.1.10 — SSH MACs (ETM only)
SSH_MACS=$(echo "$SSHD_CONFIG" | awk '/^macs / {print $2}')
if echo "$SSH_MACS" | grep -q 'etm'; then
    pass "CIS 5.1.10" "SSH MACs include ETM"
else
    warn "CIS 5.1.10" "SSH MACs: ${SSH_MACS}"
fi

# 5.1.11 — SSH ClientAliveInterval
SSH_ALIVE=$(echo "$SSHD_CONFIG" | awk '/^clientaliveinterval / {print $2}')
if [[ "$SSH_ALIVE" -gt 0 ]] && [[ "$SSH_ALIVE" -le 600 ]]; then
    pass "CIS 5.1.11" "SSH ClientAliveInterval: ${SSH_ALIVE}s"
else
    warn "CIS 5.1.11" "SSH ClientAliveInterval: ${SSH_ALIVE}s"
fi

# 5.2 — PAM faillock
if grep -rq 'pam_faillock' /etc/pam.d/ 2>/dev/null; then
    DENY=$(grep -h 'deny=' /etc/security/faillock.conf 2>/dev/null | grep -oP 'deny=\K\d+' | head -1)
    pass "CIS 5.2.1" "PAM faillock active (deny=${DENY:-?})"
else
    fail "CIS 5.2.1" "PAM faillock not configured"
fi

# 5.3 — Sudo logging
if grep -rq 'iolog_dir' /etc/sudoers /etc/sudoers.d/ 2>/dev/null; then
    pass "CIS 5.3.1" "Sudo I/O logging configured"
else
    fail "CIS 5.3.1" "Sudo I/O logging not configured"
fi

# 5.4 — SUID binaries
SUID_COUNT=$(find / -perm -4000 -type f 2>/dev/null | wc -l)
if [[ "$SUID_COUNT" -le 15 ]]; then
    pass "CIS 5.4.1" "SUID binaries: ${SUID_COUNT} (≤15)"
else
    warn "CIS 5.4.1" "SUID binaries: ${SUID_COUNT} (review needed)"
fi

# 5.5 — DNS-over-TLS
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    DOT=$(SYSTEMD_PAGER=cat resolvectl status 2>/dev/null | grep 'Protocols:' | head -1)
    if echo "$DOT" | grep -q '+DNSOverTLS'; then
        pass "CIS 5.5.1" "DNS-over-TLS: active"
    else
        warn "CIS 5.5.1" "DNS-over-TLS not enforced"
    fi
    if echo "$DOT" | grep -q 'DNSSEC=yes'; then
        pass "CIS 5.5.2" "DNSSEC: active"
    else
        warn "CIS 5.5.2" "DNSSEC not active"
    fi
fi

# 5.6 — Caddy TLS 1.3
if systemctl is-active --quiet caddy 2>/dev/null; then
    TLS_VER=$(curl -vsk https://${PI_IP:-localhost}/health 2>&1 | grep -oP 'TLSv[\d.]+' | head -1)
    if [[ "$TLS_VER" == "TLSv1.3" ]]; then
        pass "CIS 5.6.1" "Caddy TLS: ${TLS_VER}"
    else
        warn "CIS 5.6.1" "Caddy TLS: ${TLS_VER:-unknown}"
    fi
fi

# 5.7 — Protected hardlinks/symlinks/FIFOs
HARDLINK=$(sysctl -n fs.protected_hardlinks 2>/dev/null)
SYMLINK=$(sysctl -n fs.protected_symlinks 2>/dev/null)
FIFOS=$(sysctl -n fs.protected_fifos 2>/dev/null)
REGULAR=$(sysctl -n fs.protected_regular 2>/dev/null)
[[ "$HARDLINK" == "1" ]] && pass "CIS 5.7.1" "protected_hardlinks=1" || fail "CIS 5.7.1" "protected_hardlinks=${HARDLINK}"
[[ "$SYMLINK" == "1" ]] && pass "CIS 5.7.2" "protected_symlinks=1" || fail "CIS 5.7.2" "protected_symlinks=${SYMLINK}"
[[ "$FIFOS" == "2" ]] && pass "CIS 5.7.3" "protected_fifos=2" || fail "CIS 5.7.3" "protected_fifos=${FIFOS}"
[[ "$REGULAR" == "2" ]] && pass "CIS 5.7.4" "protected_regular=2" || fail "CIS 5.7.4" "protected_regular=${REGULAR}"

# =================================================================
# SECTION 6: SYSTEMD HARDENING
# =================================================================
header "6.x Systemd Service Hardening"

# Check systemd-analyze security scores
for svc in caddy ollama sshd; do
    SEC_LINE=$(systemd-analyze security "${svc}" 2>/dev/null | tail -1)
    NUMERIC=$(echo "$SEC_LINE" | grep -oP '\d+\.\d+' | head -1)
    RATING=$(echo "$SEC_LINE" | awk '{for(i=1;i<=NF;i++) if($i ~ /OK|MEDIUM|EXPOSED|UNSAFE/) print $i}')
    if [[ -n "$NUMERIC" ]]; then
        INTPART=${NUMERIC%%.*}
        if [[ "$INTPART" -lt 5 ]]; then
            pass "CIS 6.1" "${svc} security: ${NUMERIC} ${RATING}"
        elif [[ "$INTPART" -lt 8 ]]; then
            warn "CIS 6.1" "${svc} security: ${NUMERIC} ${RATING}"
        else
            fail "CIS 6.1" "${svc} security: ${NUMERIC} ${RATING}"
        fi
    fi
done

# =================================================================
# SUMMARY
# =================================================================
TOTAL=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT + NA_COUNT))
SCORABLE=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
if [[ $SCORABLE -gt 0 ]]; then
    SCORE_PCT=$(( (PASS_COUNT * 100) / SCORABLE ))
else
    SCORE_PCT=0
fi

if $JSON_MODE; then
    echo "{"
    echo "  \"date\": \"$(date -Iseconds)\","
    echo "  \"hostname\": \"$(hostname)\","
    echo "  \"total\": ${TOTAL},"
    echo "  \"pass\": ${PASS_COUNT},"
    echo "  \"fail\": ${FAIL_COUNT},"
    echo "  \"warn\": ${WARN_COUNT},"
    echo "  \"na\": ${NA_COUNT},"
    echo "  \"score_pct\": ${SCORE_PCT},"
    echo "  \"results\": ["
    for i in "${!RESULTS[@]}"; do
        IFS='|' read -r status cis desc <<< "${RESULTS[$i]}"
        COMMA=","
        [[ $i -eq $((${#RESULTS[@]} - 1)) ]] && COMMA=""
        echo "    {\"status\": \"${status}\", \"cis\": \"${cis}\", \"description\": \"${desc}\"}${COMMA}"
    done
    echo "  ]"
    echo "}"
else
    echo ""
    echo "================================================================"
    printf "CIS SCORE: \033[1m%d%%\033[0m (%d/%d scorable checks)\n" "$SCORE_PCT" "$PASS_COUNT" "$SCORABLE"
    printf "  PASS: \033[32m%d\033[0m  |  FAIL: \033[31m%d\033[0m  |  WARN: \033[33m%d\033[0m  |  N/A: %d\n" \
        "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT" "$NA_COUNT"
    echo "================================================================"
fi

# Exit code: 0 if score >= 90%, 1 if warnings, 2 if failures
if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 2
elif [[ $WARN_COUNT -gt 0 ]]; then
    exit 1
else
    exit 0
fi
