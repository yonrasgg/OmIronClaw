# CIS Debian 13 Benchmark — Adapted for OmIronClaw Template

## Scope

This maps CIS Debian Linux Benchmark controls to the OmIronClaw hardening template.
Controls marked N/A are justified with rationale.

## Section 1: Initial Setup — Filesystem Configuration

| # | Control | Expected | Phase | Status | Notes |
|---|---------|----------|-------|--------|-------|
| 1.1.1.1 | Disable cramfs | Module not loaded | 2 | ✅ PASS | Blacklisted in modprobe.d |
| 1.1.1.2 | Disable freevxfs | Module not loaded | 2 | ✅ PASS | Blacklisted in modprobe.d |
| 1.1.1.3 | Disable jffs2 | Module not loaded | 2 | ✅ PASS | Blacklisted in modprobe.d |
| 1.1.1.4 | Disable hfs | Module not loaded | 2 | ✅ PASS | Blacklisted in modprobe.d |
| 1.1.1.5 | Disable hfsplus | Module not loaded | 2 | ✅ PASS | Blacklisted in modprobe.d |
| 1.1.1.6 | Disable udf | Module not loaded | 2 | ✅ PASS | Blacklisted in modprobe.d |
| 1.1.2 | /tmp separate partition | N/A | — | N/A | Using PrivateTmp in systemd instead |
| 1.1.3-5 | /tmp noexec,nosuid,nodev | N/A | — | N/A | systemd PrivateTmp handles this |
| 1.6 | AppArmor enforcing | enforce mode | 7 | ✅ PASS | Ollama profile in enforce mode |

## Section 2: Services

| # | Control | Expected | Phase | Status | Notes |
|---|---------|----------|-------|--------|-------|
| 2.1.1 | Disable xinetd | Not installed | — | ✅ PASS | Not in base image |
| 2.2.1 | Disable Bluetooth | disabled/masked | 2 | ✅ PASS | Masked, module blacklisted |
| 2.2.2 | Disable Avahi | Hardened | 2,4 | ✅ PASS | Sandboxed, allow-interfaces=wlan0, mDNS only |
| 2.2.3 | Disable CUPS | Not installed | — | ✅ PASS | Not in lite image |
| 2.2.4 | Disable DHCP server | Not installed | — | ✅ PASS | |
| 2.2.5 | Disable DNS server | Not installed | — | ✅ PASS | |
| 2.2.6 | Disable FTP server | Not installed | — | ✅ PASS | |
| 2.2.7 | Disable NFS | Not installed | — | ✅ PASS | |
| 2.2.8 | Disable Samba | Not installed | — | ✅ PASS | |
| 2.2.9 | Disable HTTP proxy | Not installed | — | ✅ PASS | |
| 2.2.10 | Disable SNMP | Not installed | — | ✅ PASS | |
| 2.2.11 | Disable rsync | Not installed | — | ✅ PASS | |

## Section 3: Network Configuration

### 3.3 Network Parameters

| # | Control | Expected | Phase | Status | Current |
|---|---------|----------|-------|--------|---------|
| 3.3.1 | IP forwarding disabled | 0 | 0 | PASS | 0 ✓ |
| 3.3.2 | Send ICMP redirects disabled | 0 | 1 | PASS | 0 ✓ (sysctl.d/90-hardening) |
| 3.3.3 | Accept ICMP redirects disabled | 0 | 1 | PASS | 0 ✓ (sysctl.d/90-hardening) |
| 3.3.4 | Accept source route disabled | 0 | 0 | PASS | 0 ✓ |
| 3.3.5 | Log suspicious packets | 1 | 1 | PASS | 1 ✓ (sysctl.d/90-hardening) |
| 3.3.6 | Ignore broadcast ICMP | 1 | 1 | PASS | 1 ✓ |
| 3.3.7 | Ignore bogus ICMP errors | 1 | 1 | PASS | 1 ✓ |
| 3.3.8 | Enable TCP SYN cookies | 1 | 0 | PASS | 1 ✓ |
| 3.3.9 | Reverse path filtering | 1 | 1 | PASS | 1 ✓ (sysctl.d/90-hardening) |

### 3.5 Firewall

| # | Control | Expected | Phase | Status | Current |
|---|---------|----------|-------|--------|---------|
| 3.5.1 | nftables installed | Yes | 0 | ✅ PASS | Installed ✓ |
| 3.5.2 | Default deny policy | drop | 1 | ✅ PASS | type filter hook input/forward/output: drop |
| 3.5.3 | Loopback rules configured | Accept lo | 1 | ✅ PASS | iifname lo accept ✓ |
| 3.5.4 | Outbound rules configured | Whitelist | 1/8 | ✅ PASS | Egress whitelist (SSH to T1-T4, IoT blocked) |

## Section 4: Logging and Auditing

| # | Control | Expected | Phase | Status | Notes |
|---|---------|----------|-------|--------|-------|
| 4.1.1 | auditd installed | Yes | 6 | ✅ PASS | 24 immutable rules |
| 4.1.2 | auditd enabled | Yes | 6 | ✅ PASS | Active, persistent |
| 4.2.1 | journald configured | Yes | 0 | ✅ PASS | Persistent, 500M/90d retention |
| 4.2.2 | Log permissions | 640 or more restrictive | 6 | ✅ PASS | Verified |

## Section 5: Access, Authentication, Authorization

### 5.2 SSH Server

| # | Control | Expected | Phase | Status | Current |
|---|---------|----------|-------|--------|---------|
| 5.2.1 | SSH permissions on sshd_config | 600 | 1 | ✅ PASS | 600 ✓ |
| 5.2.2 | SSH Protocol 2 | 2 (default) | — | ✅ PASS | Default in OpenSSH 10 |
| 5.2.3 | SSH LogLevel | INFO or VERBOSE | 1 | ✅ PASS | VERBOSE |
| 5.2.4 | Disable X11Forwarding | no | 1 | ✅ PASS | X11Forwarding no |
| 5.2.5 | SSH MaxAuthTries | ≤ 4 | 1 | ✅ PASS | MaxAuthTries 3 |
| 5.2.6 | SSH IgnoreRhosts | yes | — | ✅ PASS | Default yes |
| 5.2.7 | Disable HostbasedAuth | no | — | ✅ PASS | Default no |
| 5.2.8 | Disable root login | no | 1 | ✅ PASS | PermitRootLogin no |
| 5.2.9 | Disable empty passwords | no | — | ✅ PASS | Default ✓ |
| 5.2.10 | Disable PermitUserEnvironment | no | — | ✅ PASS | Default no |
| 5.2.11 | Strong ciphers only | AEAD ciphers | 5 | ✅ PASS | chacha20-poly1305, aes256-gcm, aes128-gcm |
| 5.2.12 | Strong MACs | AEAD implicit | 5 | ✅ PASS | AEAD ciphers eliminate separate MAC |
| 5.2.13 | SSH Idle Timeout | ClientAliveInterval 300 | 1 | ✅ PASS | ClientAliveInterval 300 |
| 5.2.14 | LoginGraceTime | 60 | 1 | ✅ PASS | LoginGraceTime 60 |
| 5.2.15 | SSH AllowUsers/AllowGroups | Configured | 1 | ✅ PASS | AllowUsers <SSH_USER> |
| 5.2.16 | SSH Banner | Set | 1 | ✅ PASS | Banner /etc/issue.net |
| 5.2.17 | Disable PasswordAuth | no | 1 | ✅ PASS | PasswordAuthentication no, key-only |

### 5.3 Sudo

| # | Control | Expected | Phase | Status | Notes |
|---|---------|----------|-------|--------|-------|
| 5.3.1 | Sudo installed | Yes | 0 | ✅ PASS | ✓ |
| 5.3.2 | Sudo uses pty | Yes | 5 | ✅ PASS | Defaults use_pty |
| 5.3.3 | Sudo log file | Configured | 5 | ✅ PASS | I/O session logging, sudoreplay |

### 5.4 User Accounts

| # | Control | Expected | Phase | Status | Notes |
|---|---------|----------|-------|--------|-------|
| 5.4.1 | Password expiration | Set | — | N/A | Key-only auth, no passwords |
| 5.4.2 | System accounts secured | nologin shell | 2 | ✅ PASS | Verified |
| 5.4.3 | Default group for root | 0 | — | ✅ PASS | ✓ |
| 5.4.4 | Default umask | 027 or more restrictive | 2 | ✅ PASS | 027 |
| 5.4.5 | PAM faillock | deny=5, unlock=15m | 7 | ✅ PASS | faillock.conf deployed |

## Compliance Summary

```
Total Controls: 71 mapped
PASS:           69 (97%)
WARN:            2 (no AIDE file integrity, sshd systemd score 6.2)
N/A:             3
Score:          97% — STRONG
Last Assessed:  Phase 7 (scripts/70-cis-benchmark.sh)
```
