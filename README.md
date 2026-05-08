# OmIronClaw

Open-source self-hosted AI hardening template for Debian 13 on bare-metal and VPS.

OmIronClaw helps you deploy Ollama and OpenClaw with security-first defaults, clear runbooks, and reproducible workflows.
If you are building a local AI server, hardened home lab, or open-source AI infrastructure baseline, this project is designed for you.

![OmIronClaw Mascots](assets/ollama+openclaw.png)

## Why OmIronClaw

OmIronClaw provides a production-minded baseline for:

- Secure-by-default self-hosted AI operations
- SSH-first access to reduce lockout and exposure risk
- Local AI workflows with Ollama REST
- Optional OpenClaw orchestration for local, cloud, or hybrid routing
- Open-source publication safety with built-in OPSEC checks

## Who Is This For

- Engineers who want a faster path to a hardened self-hosted AI stack
- Technical founders who need private AI infrastructure without enterprise complexity
- Home lab operators who value repeatable scripts and practical security controls
- Open-source contributors who want a clean, auditable release workflow

## What You Get

- Interactive initialization for environment-safe outputs
- Security templates and staged hardening scripts for Debian 13
- AI stack setup path for Ollama and OpenClaw
- Wiki-first documentation for deeper implementation details

## Interactive Bootstrap

Use the interactive initializer to generate environment-specific output safely:

```bash
bash scripts/00-omironclaw-init.sh
```

Generated artifacts:

- `build/.env.generated`
- `build/SETUP_GUIDE.md`
- `build/rendered-<timestamp>/templates`
- `build/rendered-<timestamp>/wiki`

## SSH First (Mandatory)

Before applying strict SSH hardening templates, bootstrap key access and validate a real key-based login:

```bash
bash scripts/02-ssh-key-bootstrap.sh --host <SERVER_IP> --user <SSH_USER>
```

If SSH key login is not validated first, you risk administrative lockout.

## Core Execution Path

```bash
bash scripts/00-baseline-audit.sh
sudo bash scripts/10-phase1-foundation.sh
sudo bash scripts/20-phase2-service-optimization.sh
sudo bash scripts/30-phase3-ai-stack.sh
```

This path is intentionally opinionated: audit first, foundation hardening second, service minimization third, AI stack integration last.

## Documentation Hub

The wiki is the primary source of operational and technical documentation.
README stays focused on clarity and onboarding, while wiki pages go deeper into architecture, standards, and runbooks.

Start here:

- [Wiki Home](wiki/index.md)
- [Start Here](wiki/start-here.md)
- [First Deployment](wiki/runbooks/first-deployment.md)
- [SSH Bootstrap](wiki/runbooks/ssh-bootstrap.md)
- [Public Release Runbook](wiki/runbooks/publish-public-release.md)

## Public Release Safety

Run this before opening any public PR or tag:

```bash
bash scripts/01-prepublish-check.sh
```

This wrapper verifies:

- Sanitization leakage patterns
- Secret-like files in the tree
- Required release files for governance and security

This keeps the repository publish-ready for open-source collaboration without leaking private infrastructure details.

## Repository Structure

```text
OmIronClaw/
├── README.md
├── LICENSE
├── SECURITY.md
├── CONTRIBUTING.md
├── scripts/
├── templates/
├── wiki/
└── assets/
```

## License

This project is licensed under Apache License 2.0.
See [LICENSE](LICENSE) and [License and Open Source Policy](wiki/standards/license-and-open-source-policy.md).
