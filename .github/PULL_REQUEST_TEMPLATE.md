## Summary
Describe what changed in one concise paragraph.

## Why This Change
Explain the operational or security rationale.

## Scope
List the main files or areas touched.

## Validation
Provide deterministic verification commands and the key output lines.

## Security and OPSEC Review
- [ ] No secrets, private keys, internal hostnames, or private IPs are introduced.
- [ ] Prepublish checks pass locally: bash scripts/01-prepublish-check.sh
- [ ] SSH key bootstrap flow remains valid when SSH-related files are modified.

## Documentation Impact
- [ ] README updated if user-facing behavior changed.
- [ ] Relevant wiki runbooks or standards updated.

## Rollback Plan
Describe exactly how to revert safely if this change causes regressions.

## Post-Merge Follow-up
List any deferred tasks required after merge (if any).
