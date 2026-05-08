# Runbook: SSH Key Rotation

## Purpose

Rotate SSH keys on a scheduled basis or after a suspected compromise. Follows NIST SC-12 (Cryptographic Key Management).

## When to Use

- Quarterly scheduled rotation
- After any suspected compromise
- When personnel changes occur (access revocation)
- When upgrading key algorithms

## Prerequisites

- Admin PC (<ADMIN_PC_IP>) has SSH access to the target host
- Current key authentication is working

## Procedure

### Step 1 — Generate New Key Pair (on Admin PC)

```bash
# Generate Ed25519 key with descriptive name
ssh-keygen -t ed25519 -C "<SSH_USER>@admin-pc-$(date +%Y%m%d)" \
  -f ~/.ssh/pi-<PI_HOSTNAME>-$(date +%Y%m%d)

# Set proper permissions
chmod 600 ~/.ssh/pi-<PI_HOSTNAME>-$(date +%Y%m%d)
chmod 644 ~/.ssh/pi-<PI_HOSTNAME>-$(date +%Y%m%d).pub
```

### Step 2 — Deploy New Key (from Admin PC)

```bash
# Copy new public key to target host
ssh-copy-id -i ~/.ssh/pi-<PI_HOSTNAME>-$(date +%Y%m%d).pub <SSH_USER>@<PI_IP>
```

### Step 3 — Verify New Key Works

```bash
# Test SSH with new key (DO NOT close existing session)
ssh -i ~/.ssh/pi-<PI_HOSTNAME>-$(date +%Y%m%d) <SSH_USER>@<PI_IP> "echo 'New key OK'"
```

### Step 4 — Remove Old Key (on target host)

```bash
# On the target host: edit authorized_keys, remove the old key line
nano ~/.ssh/authorized_keys
# Delete the line with the OLD key comment/fingerprint
```

### Step 5 — Update SSH Config (on Admin PC)

```bash
# Update ~/.ssh/config
cat >> ~/.ssh/config << 'EOF'
Host <PI_HOSTNAME>
  HostName <PI_IP>
  User <SSH_USER>
  IdentityFile ~/.ssh/pi-<PI_HOSTNAME>-YYYYMMDD
  IdentitiesOnly yes
EOF
```

### Step 6 — Archive Old Key (on Admin PC)

```bash
# Move old key to archive (do NOT delete yet — keep for 30 days)
mkdir -p ~/.ssh/archive
mv ~/.ssh/pi-<PI_HOSTNAME>-OLD* ~/.ssh/archive/
```

### Step 7 — Document Rotation

```bash
# On target host: log the rotation
echo "$(date -Iseconds) | SSH key rotated | old=<fingerprint> new=<fingerprint>" \
  >> /home/<SSH_USER>/<PROJECT_ROOT>/logs/key-rotation.log
```

## Verification

```bash
# From Admin PC: confirm only new key works
ssh -i ~/.ssh/pi-<PI_HOSTNAME>-$(date +%Y%m%d) <SSH_USER>@<PI_IP> "echo 'SUCCESS'"

# Confirm old key is rejected (should fail)
ssh -i ~/.ssh/archive/pi-<PI_HOSTNAME>-OLD <SSH_USER>@<PI_IP> "echo 'SHOULD FAIL'" 2>&1 | grep -q "Permission denied" && echo "Old key correctly rejected"
```

## Rollback

If new key fails, use the existing SSH session (Step 3 warned not to close it):

```bash
# Re-add old key temporarily
echo "<old-public-key>" >> ~/.ssh/authorized_keys
```
