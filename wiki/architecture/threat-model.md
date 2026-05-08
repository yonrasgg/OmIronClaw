# Threat Model - Debian 13 AI Server Template

## Objective

Define a reusable threat model for a hardened Debian 13 host running Ollama and optional OpenClaw services in LAN or VPS contexts.

## Asset Inventory

| Asset | Confidentiality | Integrity | Availability |
|---|---|---|---|
| SSH access and keys | High | High | High |
| Firewall and system configuration | Medium | High | High |
| AI inference API and orchestration API | Medium | High | Medium |
| Prompt/response data | High | High | Medium |
| Logs and audit trails | Medium | High | Medium |

## Threat Actors

| Actor | Access Level | Typical Goal | Likelihood |
|---|---|---|---|
| Internet scanner | Remote unauthenticated | Enumerate and exploit exposed services | Medium |
| Compromised LAN endpoint | Adjacent network | Lateral movement and credential theft | Medium |
| Authenticated malicious user | Valid credentials | Privilege escalation and persistence | Low |
| Prompt-injection adversary | API consumer | Data exfiltration and unsafe tool actions | Medium |

## Attack Surface

### Internet to Host

| Vector | Mitigation |
|---|---|
| SSH brute force | Key-only auth, allowlist, rate limits, fail2ban, faillock |
| TLS/API abuse | Caddy TLS, API auth, request limits, loopback upstreams |

### LAN to Host

| Vector | Mitigation |
|---|---|
| Port scanning and service probing | nftables default deny inbound |
| Neighbor interception risks | TLS for API paths and strict SSH crypto |

### Local Service Boundary

| Vector | Mitigation |
|---|---|
| Direct Ollama/OpenClaw exposure | Bind to 127.0.0.1 and route through reverse proxy |
| Privilege escalation from service context | Dedicated service users, systemd hardening, AppArmor |

### Physical and Storage

| Vector | Mitigation |
|---|---|
| Disk theft or offline analysis | Encryption-at-rest policy and key management runbook |
| Storage-induced corruption | Backups, checksum validation, restore runbook |

## STRIDE Mapping

| Category | Example | Primary Controls |
|---|---|---|
| Spoofing | Unauthorized SSH login attempt | IA-2, AC-17 |
| Tampering | Firewall/config manipulation | CM-6, AC-6 |
| Repudiation | Untracked privileged action | AU-2, AU-12 |
| Information Disclosure | Prompt or log leakage | SC-8, data-minimization policy |
| Denial of Service | Inference flood | SC-7, rate limiting, process limits |
| Elevation of Privilege | Service escape or sudo abuse | AC-6, AppArmor, systemd sandboxing |

## Residual Risks

- Prompt injection remains an inherent LLM risk and requires continuous guardrail updates.
- Availability can still degrade under sustained resource pressure if model sizing exceeds host capacity.
- Physical compromise remains impactful unless encryption at rest is enabled.

## Review Cadence

- Reassess this model after each major phase milestone.
- Re-run external validation after firewall, proxy, or authentication changes.
- Update control mapping in `wiki/standards` when mitigations change.
