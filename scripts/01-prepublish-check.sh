#!/usr/bin/env bash
# OmIronClaw prepublish validation
# Runs a strict local check set before public release.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_DIR}"

FAIL=0

echo "[1/4] Sanitization validator"
PATTERNS=(
  '192\.168\.0\.(131|209|250|124|57)\b'
  '\b(userone|be-noone|n11v0)\b'
  '\b(jarvis|crlab01|lat3400|red-ghost-111|jarvisraspi|pwny-key)\b'
  '\bpi-hardening\b'
  '/home/(userone|be-noone|n11v0)\b'
  '50686994719'
  '560e8b0f'
  '[0-9a-f]{2}(:[0-9a-f]{2}){5}'
)

EXTENSIONS='*.md *.sh *.yml *.conf *.json *.cfg *.txt *.env'
EXCLUDES='--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=build --exclude=.env --exclude=.api-key --exclude=01-prepublish-check.sh'

FOUND=0
for pattern in "${PATTERNS[@]}"; do
  # shellcheck disable=SC2086
  MATCHES=$(grep -rniE ${EXCLUDES} "$pattern" . 2>/dev/null || true)
  if [[ -n "$MATCHES" ]]; then
    echo "[LEAK] pattern '$pattern'"
    echo "$MATCHES" | head -5
    echo ""
    FOUND=1
  fi
done

if [[ $FOUND -ne 0 ]]; then
  FAIL=1
else
  echo "Sanitization checks passed."
fi

echo
echo "[2/4] Secret-like file sweep"
SECRET_MATCHES="$(find . -type f \( -name '*.pem' -o -name '*.p12' -o -name '*.pfx' -o -name '*.key' -o -name '*.secret' -o -name '.env' -o -name '.api-key' \) \
  -not -path './.git/*' \
  -not -path './build/*' \
  -not -path './node_modules/*' || true)"
if [[ -n "${SECRET_MATCHES}" ]]; then
  echo "Potential secret files detected:"
  echo "${SECRET_MATCHES}"
  FAIL=1
else
  echo "No secret-like files detected."
fi

echo
echo "[3/4] Required release files"
REQUIRED=(
  "README.md"
  "LICENSE"
  "SECURITY.md"
  "CONTRIBUTING.md"
  "scripts/00-omironclaw-init.sh"
  "scripts/01-prepublish-check.sh"
  "scripts/02-ssh-key-bootstrap.sh"
  "wiki/index.md"
  "wiki/start-here.md"
  "wiki/runbooks/first-deployment.md"
  "wiki/runbooks/ssh-bootstrap.md"
  "wiki/runbooks/publish-public-release.md"
)
for f in "${REQUIRED[@]}"; do
  if [[ -f "${f}" ]]; then
    echo "OK: ${f}"
  else
    echo "MISSING: ${f}"
    FAIL=1
  fi
done

echo
echo "[4/4] Optional cleanliness hints"
if [[ -d wiki/phases ]]; then
  echo "ERROR: Legacy wiki/phases directory still exists."
  FAIL=1
else
  echo "Legacy phase/task wiki directories are removed."
fi

if [[ -d build ]]; then
  echo "INFO: build/ exists (generated artifacts)."
  echo "INFO: This directory is ignored by .gitignore, but you can remove it for a clean tree."
else
  echo "No build/ directory present."
fi

if [[ "${FAIL}" -eq 0 ]]; then
  echo
  echo "PASS: OmIronClaw prepublish checks completed successfully."
  exit 0
fi

echo
echo "FAIL: Fix issues above before publishing."
exit 1
