# Runbook: First Deployment (Bare-Metal and VPS)

## Objective

Deploy a hardened Debian 13 AI node from a clean host to a validated operational baseline.

## Deployment Profiles

### Bare-Metal (LAN)

- Typical for homelab or office segments
- Restrict inbound to management subnet
- Keep API endpoints behind Caddy authentication

### VPS (Cloud)

- Apply provider security group first (22 and 443 only)
- Enforce explicit SSH source allowlist
- Avoid exposing upstream AI services directly

## Preconditions

- Debian 13 host is reachable by SSH
- You have sudo privileges
- Network and DNS are functional

## Step 1 — Clone and Initialize

```bash
git clone <REPOSITORY_URL> OmIronClaw
cd OmIronClaw
bash scripts/00-omironclaw-init.sh
```

Outputs:

- `build/.env.generated`
- `build/SETUP_GUIDE.md`
- `build/rendered-<timestamp>/templates`

## Step 2 — SSH Access Hardening Prerequisite

Generate and verify SSH key login before applying sshd restrictions:

```bash
bash scripts/02-ssh-key-bootstrap.sh --host <SERVER_IP> --user <SSH_USER>
```

Success criteria:

- Key exists in `~/.ssh/`
- Key installed in target `authorized_keys`
- Test command returns `SSH key login OK`

## Step 3 — Apply Core Hardening

```bash
bash scripts/00-baseline-audit.sh
sudo bash scripts/10-phase1-foundation.sh
sudo bash scripts/20-phase2-service-optimization.sh
sudo bash scripts/30-phase3-ai-stack.sh
```

## Step 4 — Validate Runtime Security

- Validate firewall exposure from an external host
- Validate Caddy TLS and API authentication
- Validate Ollama/OpenClaw bind strategy
- Validate service health and logging

## Step 5 — Prepare for Public Publication (Template Maintainers)

```bash
bash scripts/01-prepublish-check.sh
```

## Related Documentation

- [SSH Bootstrap](ssh-bootstrap.md)
- [Backup and Restore](backup-restore.md)
- [Emergency Lockdown](emergency-lockdown.md)
- [Public Release Runbook](publish-public-release.md)
