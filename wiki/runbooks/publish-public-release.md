# Runbook: Publish Public Release

## Objective

Publish OmIronClaw as a clean open-source template with no sensitive leakage and complete release metadata.

## Step 1 — Validate Repository Safety

```bash
bash scripts/01-prepublish-check.sh
```

This runs:

- Sanitization pattern checks
- Secret-like file sweep
- Required release file checks

## Step 2 — Confirm Documentation Entry Points

- [README](../../README.md) explains quick start and wiki routing
- [Wiki Index](../index.md) points to narrative operational docs
- [SECURITY](../../SECURITY.md) defines vulnerability reporting
- [CONTRIBUTING](../../CONTRIBUTING.md) defines contribution workflow

## Step 3 — Confirm Licensing

- Verify [LICENSE](../../LICENSE) exists and matches repository policy
- Ensure headers and docs do not conflict with selected license

## Step 4 — Final Human Review

- Verify no personal usernames/IPs/hostnames remain
- Verify no local build artifacts are intended for commit
- Verify scripts are executable where required

## Step 5 — Publish

```bash
git init
git add .
git commit -m "OmIronClaw public template baseline"
```

Then push to your chosen GitHub repository and enable Security Advisories.
