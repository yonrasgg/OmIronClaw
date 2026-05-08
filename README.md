# OmIronClaw

Universal Debian 13 AI hardening template for bare-metal and VPS deployments.

![OmIronClaw Mascots](assets/ollama+openclaw.png)

## Why OmIronClaw

OmIronClaw provides a production-minded baseline for:

- Zero-trust network posture
- SSH-first secure access model
- Local AI with Ollama REST
- Optional OpenClaw orchestration for local, cloud, or hybrid routing
- Public-template OPSEC controls before Git publishing

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

## Documentation Hub

The wiki is the primary source of operational documentation.

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
