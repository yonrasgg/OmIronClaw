# Runbook: SSH Bootstrap and Connectivity Validation

## Objective

Provision secure SSH key-based access for the target device before strict sshd hardening is applied.

## Why This Matters

Applying hardening before validating key-based access can lock out administrators.

## Automated Method (Recommended)

Use the OmIronClaw helper script:

```bash
bash scripts/02-ssh-key-bootstrap.sh --host <SERVER_IP> --user <SSH_USER>
```

Optional flags:

```bash
bash scripts/02-ssh-key-bootstrap.sh \
  --host <SERVER_IP> \
  --user <SSH_USER> \
  --port 22 \
  --key-name omironclaw-admin
```

What it does:

1. Generates an Ed25519 key if it does not exist
2. Installs public key via `ssh-copy-id`
3. Verifies SSH key login with non-interactive test
4. Prints a ready-to-paste SSH config stanza

## Manual Fallback

If helper script cannot be used:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/omironclaw-admin -C "admin@server"
ssh-copy-id -i ~/.ssh/omironclaw-admin.pub <SSH_USER>@<SERVER_IP>
ssh -i ~/.ssh/omironclaw-admin <SSH_USER>@<SERVER_IP> "echo SSH key login OK"
```

## Validation Checklist

- [ ] Key file exists with secure permissions
- [ ] Public key deployed to target user
- [ ] SSH login works in a new terminal session
- [ ] Only after success, apply strict SSH hardening templates

## Security Notes

- Do not share private keys
- Prefer per-host dedicated keys
- Rotate keys periodically with [Key Rotation](key-rotation.md)
