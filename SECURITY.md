# Security Policy

## Scope

OmIronClaw is a public hardening template for Debian 13 hosts with optional AI services.

This repository intentionally avoids machine-specific secrets and infrastructure identifiers.

## Reporting a Vulnerability

If you discover a security issue in this repository:

1. Do not open a public issue with exploit details.
2. Use a private report channel (for example GitHub Security Advisories in the target repository).
3. Include affected files, impact, and a minimal reproducible path.
4. Include a proposed remediation when possible.

## What Is Considered Sensitive

- Real API keys, tokens, private keys, certificates, or secrets
- Personal hostnames, usernames, internal IPs, MAC addresses, LAN inventory
- Real cloud account identifiers tied to a production environment

## Maintainer Baseline Before Publishing Changes

Run:

```bash
bash scripts/01-prepublish-check.sh
```

And confirm:

- Sanitization check passes
- No local secret files are present in the working tree
- No deployment-specific identifiers were introduced

## Disclosure and Fix Expectations

- Acknowledge report quickly
- Prioritize fixes that reduce exposure scope and misuse risk
- Document remediation impact in the relevant wiki runbook or standard when applicable
