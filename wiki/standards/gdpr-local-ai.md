# GDPR Considerations for Local AI Processing

## Applicability

GDPR applies when this AI server processes **personal data** of EU/EEA individuals.
Even local processing on a home server can trigger GDPR obligations if:

- Users send personal data in prompts (names, addresses, health info)
- The AI generates outputs containing personal data
- Logs capture metadata that identifies individuals (IP addresses, usernames)
- Models are fine-tuned on personal data

## Relevant Articles

### Art. 5 — Principles of Data Processing

| Principle | Application to Local AI | Implementation |
|-----------|------------------------|----------------|
| Purpose limitation | Define what data the AI processes and why | Document in system overview |
| Data minimization | Don't collect more than needed | Conservative system prompt, no logging PII |
| Storage limitation | Don't keep data longer than needed | Log rotation, no persistent chat history |
| Integrity & confidentiality | Protect data from unauthorized access | Encryption, access control, firewall |

### Art. 25 — Data Protection by Design and Default

| Requirement | Implementation |
|-------------|----------------|
| Privacy by design | Ollama on loopback where possible, minimal data collection |
| Privacy by default | No persistent chat storage unless explicitly configured |
| Pseudonymization | Don't log user-identifiable prompts |

### Art. 32 — Security of Processing

| Measure | Implementation | Phase |
|---------|----------------|-------|
| Encryption of data in transit | SSH, TLS for Ollama API in LAN | 1, 5 |
| Encryption of data at rest | Evaluate LUKS for SD card | 5 |
| Confidentiality | nftables, SSH key-only, AllowUsers | 1 |
| Integrity | sysctl hardening, file permissions, AppArmor | 1, 2, 7 |
| Availability | Systemd restart policies, monitoring | 3, 6 |
| Regular testing | Periodic audits from Kali, compliance checks | 7 |

### Art. 35 — Data Protection Impact Assessment (DPIA)

A DPIA should be conducted if:
- Processing involves systematic monitoring of individuals
- Processing involves large-scale special category data
- New technologies are used in processing (AI qualifies)

**Recommendation**: Create a lightweight DPIA document if personal data will be processed through the AI. Include in Phase 7 compliance validation.

## Practical Measures for Debian Hosts

### Low-Risk Configuration (Recommended Start)
- Use **public models only** (no fine-tuning on personal data)
- Set **conservative system prompt** discouraging PII in responses
- Enable **log rotation** with short retention (7 days)
- **No persistent chat storage** — inference is stateless via API
- **LAN-only access** — no Internet exposure of AI services

### If Processing Personal Data
- Document the processing activity (Art. 30 records)
- Conduct a DPIA (Art. 35)
- Implement encryption at rest (LUKS) and in transit (TLS)
- Set up audit logging for all data access events
- Establish a data retention policy
- Consider a consent mechanism for users sending personal data

## Compliance Checklist

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1 | Data processing purpose documented | ✅ DONE | System overview + threat model (wiki/architecture/) |
| 2 | Data minimization in AI prompts | ✅ DONE | Stateless inference, no persistent chat storage |
| 3 | Encryption in transit | ✅ DONE | Caddy TLS 1.3, SSH AEAD ciphers, DNS-over-TLS |
| 4 | Encryption at rest | ⚠️ PARTIAL | LUKS deferred (microSD I/O penalty), NVMe pending |
| 5 | Access controls | ✅ DONE | SSH key-only, nftables deny-default, Caddy API auth, PAM faillock |
| 6 | Logging with privacy | ✅ DONE | journald 500M/90d, auditd 24 rules, no PII in logs |
| 7 | Regular security testing | ✅ DONE | CIS 97%, Kali nmap+nuclei+SSH pentest (Phase 7) |
| 8 | DPIA (if personal data) | N/A | Public models only, no PII processing currently |
| 9 | Data retention policy | ✅ DONE | journald 90d/500M, log rotation configured |
