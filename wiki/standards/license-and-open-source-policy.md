# License and Open Source Policy

## Selected License

OmIronClaw is released under **Apache License 2.0**.

## Rationale

- Permissive for open-source collaboration
- Explicit patent grant for contributors
- Suitable for infrastructure-as-code and security template repositories
- Compatible with broad commercial and non-commercial reuse

## Maintainer Rules

- Keep repository content original or properly attributed
- Do not include third-party proprietary assets without permission
- Keep sensitive data and environment-specific values out of the public template

## Release Validation

Before release, run:

```bash
bash scripts/01-prepublish-check.sh
```

## Notes on Dependencies

OmIronClaw orchestrates external software (for example Caddy, Ollama, OpenClaw) but does not relicense those projects.
Users must comply with each dependency license when deploying in production.
