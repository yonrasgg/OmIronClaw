# Start Here

## Purpose

This is the fastest professional path to deploy OmIronClaw on a fresh Debian 13 host with secure defaults and reproducible documentation.

## Who This Is For

- Operators deploying a hardened AI host on bare-metal
- Operators deploying on a cloud VPS
- Teams preparing a public, reusable template with strict OPSEC

## 10-Minute Onboarding Path

1. Read architecture baseline:
   - [System Overview](architecture/system-overview.md)
   - [Network Topology](architecture/network-topology.md)
   - [Threat Model](architecture/threat-model.md)
2. Run interactive bootstrap:

```bash
bash scripts/00-omironclaw-init.sh
```

3. Bootstrap SSH key access and verify login:

```bash
bash scripts/02-ssh-key-bootstrap.sh --host <SERVER_IP> --user <SSH_USER>
```

4. Execute core hardening sequence:

```bash
bash scripts/00-baseline-audit.sh
sudo bash scripts/10-phase1-foundation.sh
sudo bash scripts/20-phase2-service-optimization.sh
sudo bash scripts/30-phase3-ai-stack.sh
```

5. Run publication safety checks:

```bash
bash scripts/01-prepublish-check.sh
```

## Operator Notes

- Always validate SSH key login in a new terminal before applying strict sshd hardening.
- Keep Ollama and OpenClaw loopback-bound where possible.
- Use the [First Deployment](runbooks/first-deployment.md) runbook for complete execution details.
- Use the [Public Release Runbook](runbooks/publish-public-release.md) before publishing.
