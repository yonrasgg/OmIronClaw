---
title: "Obsidian Frontmatter and Tag Taxonomy"
type: "documentation-standard"
domain: "knowledge-management"
sensitivity: "internal"
agent_access: "true"
tags:
  - standards
  - obsidian
  - frontmatter
  - taxonomy
  - documentation
created: 2026-05-07
updated: 2026-05-07
related:
  - ../index.md
---

# Obsidian Frontmatter and Tag Taxonomy

## Minimum Frontmatter

```yaml
---
title: "..."
type: "..."
domain: "..."
sensitivity: "internal"
agent_access: "true"
tags:
  - ...
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

## Recommended Extended Fields

```yaml
status: "todo|in-progress|done|blocked|skipped"
related:
  - relative/path.md
```

## Controlled Tags

- Domain tags: hardening, network, monitoring, openclaw, ollama, compliance, documentation
- Artifact tags: evidence, runbook, standard, architecture, policy, guide
- Control tags: nist, cis, gdpr, plus control IDs as needed (ac-3, sc-7, cm-6)

## Rules

1. Keep tags focused and reusable.
2. Use lowercase kebab-case.
3. Link evidence back to the relevant runbook or guide.
4. Prefer deterministic filenames and ISO dates.
