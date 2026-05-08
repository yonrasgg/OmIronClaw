# NIST SP 800-53 — Control Mapping for Debian 13 AI Server Template

## Applicable Control Families

| Family | Code | Relevance | Phase |
|--------|------|-----------|-------|
| Access Control | AC | HIGH | 1, 3, 8 |
| Audit & Accountability | AU | HIGH | 6, 7 |
| Configuration Management | CM | HIGH | 1, 2, 3 |
| Identification & Authentication | IA | HIGH | 1, 4 |
| System & Communications Protection | SC | HIGH | 1, 4, 5 |
| System & Information Integrity | SI | MEDIUM | 1, 6 |
| Security Assessment | CA | MEDIUM | 7 |
| Risk Assessment | RA | MEDIUM | 0, 7 |
| System & Services Acquisition | SA | MEDIUM | 3 |

## Control Details

### AC — Access Control

| Control | Title | Implementation | Phase | Status |
|---------|-------|----------------|-------|--------|
| AC-2 | Account Management | Single user (<SSH_USER>), service accounts (ollama, openclawsvc) | 1,3,9 | ✅ DONE |
| AC-3 | Access Enforcement | nftables + SSH AllowUsers + systemd sandboxing + Caddy API auth | 1,3 | ✅ DONE |
| AC-4 | Information Flow Enforcement | nftables ingress/egress, Ollama localhost-only, Caddy gateway | 1,4,8 | ✅ DONE |
| AC-6 | Least Privilege | Service users (no sudo), SUID cleanup, systemd restrictions, sudoers scoped | 2 | ✅ DONE |
| AC-7 | Unsuccessful Login Attempts | MaxAuthTries=3, fail2ban (3 retries/2h ban), PAM faillock (deny=5/15m) | 1,6 | ✅ DONE |
| AC-17 | Remote Access | SSH key-only (ed25519), no root, rate-limited, AllowUsers, Ansible per-host keys | 1,8 | ✅ DONE |

### AU — Audit & Accountability

| Control | Title | Implementation | Phase | Status |
|---------|-------|----------------|-------|--------|
| AU-2 | Audit Events | journald persistent + auditd 24 immutable rules + sudo I/O logging | 6 | ✅ DONE |
| AU-3 | Content of Audit Records | Timestamps, source IP, user, action in journald/auditd/fail2ban | 6 | ✅ DONE |
| AU-6 | Audit Review | Health monitor (22 checks), systemd timer (Sun 06:00), sudoreplay | 6 | ✅ DONE |
| AU-8 | Time Stamps | systemd-timesyncd for NTP | 0 | ✅ DONE |
| AU-12 | Audit Generation | nftables logging, SSH logging, sudo session logging, auditd rules | 1,5,6 | ✅ DONE |

### CM — Configuration Management

| Control | Title | Implementation | Phase | Status |
|---------|-------|----------------|-------|--------|
| CM-2 | Baseline Configuration | Baseline audit captured, CIS 97% benchmark (69/71) | 0,7 | ✅ DONE |
| CM-6 | Configuration Settings | sysctl hardening, sshd_config, systemd overrides, modprobe blacklist | 1,2 | ✅ DONE |
| CM-7 | Least Functionality | Bluetooth/cloud-init/thunderbolt disabled, 15+ modules blacklisted | 2 | ✅ DONE |
| CM-8 | Information System Component Inventory | System audit script, 10-device LAN inventory | 0,8 | ✅ DONE |

### IA — Identification & Authentication

| Control | Title | Implementation | Phase | Status |
|---------|-------|----------------|-------|--------|
| IA-2 | Identification and Authentication | SSH ed25519 key-only, PasswordAuthentication=no | 1 | ✅ DONE |
| IA-5 | Authenticator Management | SSH key rotation runbook, per-host keys (4 hosts), AEAD ciphers only | 5,8 | ✅ DONE |

### SC — System & Communications Protection

| Control | Title | Implementation | Phase | Status |
|---------|-------|----------------|-------|--------|
| SC-7 | Boundary Protection | nftables deny-by-default, ingress/egress filtering, IoT blocked, egress whitelist | 1,8 | ✅ DONE |
| SC-8 | Transmission Confidentiality | SSH AEAD ciphers, Caddy TLS 1.3 pinned, DNS-over-TLS strict | 1,3,5 | ✅ DONE |
| SC-12 | Cryptographic Key Management | SSH ed25519 keys, Caddy internal CA, WireGuard keypair (inactive) | 5 | ✅ DONE |
| SC-20 | Secure Name/Address Resolution | systemd-resolved, DNS-over-TLS strict, DNSSEC strict | 4 | ✅ DONE |
| SC-28 | Protection of Information at Rest | Evaluated — LUKS deferred (microSD I/O penalty), NVMe pending | 5 | ⚠️ PARTIAL |

### SI — System & Information Integrity

| Control | Title | Implementation | Phase | Status |
|---------|-------|----------------|-------|--------|
| SI-2 | Flaw Remediation | APT updates via Ansible playbook, Ollama version pinned | Ongoing | ✅ DONE |
| SI-4 | Information System Monitoring | fail2ban, health monitor (22 checks), thermal monitoring | 6 | ✅ DONE |
| SI-11 | Error Handling | kptr_restrict=2, dmesg_restrict=1, kernel.printk restricted | 1 | ✅ DONE |

### CA — Security Assessment

| Control | Title | Implementation | Phase | Status |
|---------|-------|----------------|-------|--------|
| CA-2 | Security Assessments | Kali nmap + nuclei + SSH pentest, CIS 97% score, multi-agent audit | 7 | ✅ DONE |
| CA-7 | Continuous Monitoring | Health monitor timer, fail2ban, auditd, journald persistent | 6,7 | ✅ DONE |

### SA — System & Services Acquisition

| Control | Title | Implementation | Phase | Status |
|---------|-------|----------------|-------|--------|
| SA-8 | Security Engineering Principles | Least privilege for Ollama/OpenClaw/Caddy, systemd sandboxing | 2,3,9 | ✅ DONE |

## Compliance Score

```
Total applicable controls: 26
Implemented (DONE):        25
Partial (SC-28):            1
Not Applicable (N/A):       0
Compliance:               96%
```
