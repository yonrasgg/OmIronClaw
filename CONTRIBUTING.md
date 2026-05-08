# Contributing to OmIronClaw

## Contribution Principles

- Keep the repository hardware-agnostic and OPSEC-safe.
- Prefer placeholders over environment-specific values.
- Do not include personal network data, hostnames, usernames, or secrets.
- Keep changes auditable and aligned with CIS/NIST/GDPR references used in wiki.
- Keep documentation wiki-first: runbooks, standards, and architecture docs as the source of truth.

## Local Workflow

1. Create a feature branch.
2. Implement focused changes with clear commit messages.
3. Run prepublish checks:

```bash
bash scripts/01-prepublish-check.sh
```

4. Ensure docs and scripts stay consistent.
5. Open a pull request with summary, rationale, and validation output.

## Pull Request Checklist

- Scope is clear and minimal.
- No secrets or private infrastructure identifiers are present.
- Sanitization and prepublish checks pass.
- SSH bootstrap flow remains documented and functional (`scripts/02-ssh-key-bootstrap.sh`).
- README/wiki references are updated if behavior changed.
- New scripts include safe defaults and clear rollback notes.

## Coding and Documentation Notes

- Shell scripts should be idempotent where possible.
- Use explicit paths and defensive checks.
- Keep templates generic and parameterized.
- Add or update relevant wiki runbooks or standards when introducing major workflow changes.
