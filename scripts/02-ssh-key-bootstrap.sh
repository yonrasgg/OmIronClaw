#!/usr/bin/env bash
# OmIronClaw SSH bootstrap helper
# Generates a dedicated SSH key, installs it on target host, and validates login.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/02-ssh-key-bootstrap.sh --host <host_or_ip> --user <ssh_user> [options]

Options:
  --host <value>           Target host or IP (required)
  --user <value>           Target SSH user (required)
  --port <value>           SSH port (default: 22)
  --key-name <value>       Key file basename under ~/.ssh (default auto-generated)
  --no-install             Skip ssh-copy-id installation step
  --no-test                Skip SSH connectivity test step
  -h, --help               Show this help

Examples:
  bash scripts/02-ssh-key-bootstrap.sh --host 10.0.0.10 --user admin
  bash scripts/02-ssh-key-bootstrap.sh --host server.example.com --user ops --port 2222
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    return 1
  fi
}

HOST=""
SSH_USER=""
PORT="22"
KEY_NAME=""
INSTALL_KEY=1
TEST_CONN=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --user)
      SSH_USER="${2:-}"
      shift 2
      ;;
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    --key-name)
      KEY_NAME="${2:-}"
      shift 2
      ;;
    --no-install)
      INSTALL_KEY=0
      shift
      ;;
    --no-test)
      TEST_CONN=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${HOST}" || -z "${SSH_USER}" ]]; then
  echo "Both --host and --user are required."
  usage
  exit 1
fi

require_cmd ssh-keygen
require_cmd ssh
if [[ "${INSTALL_KEY}" -eq 1 ]]; then
  require_cmd ssh-copy-id
fi

if [[ -z "${KEY_NAME}" ]]; then
  KEY_NAME="omironclaw-${SSH_USER}@${HOST}-$(date +%Y%m%d)"
fi

KEY_PATH="${HOME}/.ssh/${KEY_NAME}"

mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"

echo "Target: ${SSH_USER}@${HOST}:${PORT}"
echo "Key path: ${KEY_PATH}"

if [[ -f "${KEY_PATH}" ]]; then
  echo "SSH key already exists: ${KEY_PATH}"
  read -r -p "Reuse existing key? [Y/n]: " reuse
  if [[ "${reuse:-Y}" =~ ^[Nn]$ ]]; then
    echo "Aborted. Use --key-name to create a new key file."
    exit 1
  fi
else
  ssh-keygen -t ed25519 -a 100 -C "${SSH_USER}@${HOST}-omironclaw" -f "${KEY_PATH}" -N ""
  chmod 600 "${KEY_PATH}"
  chmod 644 "${KEY_PATH}.pub"
  echo "Generated key: ${KEY_PATH}"
fi

if [[ "${INSTALL_KEY}" -eq 1 ]]; then
  echo
  echo "Installing public key on target with ssh-copy-id..."
  ssh-copy-id -p "${PORT}" -i "${KEY_PATH}.pub" "${SSH_USER}@${HOST}"
fi

if [[ "${TEST_CONN}" -eq 1 ]]; then
  echo
  echo "Testing SSH connectivity using generated key..."
  ssh -p "${PORT}" \
      -i "${KEY_PATH}" \
      -o BatchMode=yes \
      -o ConnectTimeout=8 \
      -o StrictHostKeyChecking=accept-new \
      "${SSH_USER}@${HOST}" "echo 'SSH key login OK'"
  echo "SSH key verification passed."
fi

echo
cat <<EOF
Next steps:
1. Keep this key in your SSH config for this host.
2. Validate you can reconnect in a new terminal.
3. Only then apply strict sshd hardening templates.

Suggested ~/.ssh/config entry:

Host ${HOST}
  HostName ${HOST}
  User ${SSH_USER}
  Port ${PORT}
  IdentityFile ${KEY_PATH}
  IdentitiesOnly yes
EOF
