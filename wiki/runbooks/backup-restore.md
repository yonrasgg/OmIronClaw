# Runbook: Backup & Restore

## Purpose

Create and restore backups of a Debian 13 host's critical configuration, hardening state, and AI models. Use this for disaster recovery and host-to-host migration.

## When to Use

- Before major changes (phase execution)
- Scheduled weekly backup
- Before storage migration or disk replacement
- After completing a hardening phase

## What to Back Up

| Category | Paths | Priority |
|----------|-------|----------|
| SSH config | `/etc/ssh/sshd_config.d/` | CRITICAL |
| Firewall | `/etc/nftables.conf`, `/etc/nftables.d/` | CRITICAL |
| Sysctl | `/etc/sysctl.d/` | CRITICAL |
| Users | `/etc/passwd`, `/etc/shadow`, `/etc/group` | CRITICAL |
| SSH keys | `~/.ssh/` | CRITICAL |
| Systemd overrides | `/etc/systemd/system/ollama.service.d/` | HIGH |
| Ollama models | `~/.ollama/models/` | HIGH |
| Project files | `/home/<SSH_USER>/<PROJECT_ROOT>/` | HIGH |
| AppArmor | `/etc/apparmor.d/` | MEDIUM |
| Audit rules | `/etc/audit/rules.d/` | MEDIUM |
| fail2ban | `/etc/fail2ban/` | MEDIUM |

## Backup Procedure

### Full Configuration Backup

```bash
#!/bin/bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/home/<SSH_USER>/backups/config-${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

# Critical configs
sudo tar czf "$BACKUP_DIR/ssh-config.tar.gz" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null
sudo tar czf "$BACKUP_DIR/firewall.tar.gz" /etc/nftables.conf /etc/nftables.d/ 2>/dev/null
sudo tar czf "$BACKUP_DIR/sysctl.tar.gz" /etc/sysctl.d/ 2>/dev/null
sudo tar czf "$BACKUP_DIR/users.tar.gz" /etc/passwd /etc/shadow /etc/group /etc/sudoers /etc/sudoers.d/ 2>/dev/null

# SSH keys (user-level, no sudo)
tar czf "$BACKUP_DIR/ssh-keys.tar.gz" ~/.ssh/

# Systemd overrides
sudo tar czf "$BACKUP_DIR/systemd-overrides.tar.gz" /etc/systemd/system/*.d/ 2>/dev/null

# Project files
tar czf "$BACKUP_DIR/omironclaw.tar.gz" /home/<SSH_USER>/<PROJECT_ROOT>/

# AppArmor + audit + fail2ban
sudo tar czf "$BACKUP_DIR/security-tools.tar.gz" \
  /etc/apparmor.d/ /etc/audit/rules.d/ /etc/fail2ban/ 2>/dev/null

# Manifest
echo "Backup created: $TIMESTAMP" > "$BACKUP_DIR/MANIFEST.txt"
ls -la "$BACKUP_DIR/" >> "$BACKUP_DIR/MANIFEST.txt"
sha256sum "$BACKUP_DIR"/*.tar.gz >> "$BACKUP_DIR/MANIFEST.txt"

echo "Backup complete: $BACKUP_DIR"
```

### AI Model Backup

```bash
# Models are large — back up separately
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MODEL_BACKUP="/home/<SSH_USER>/backups/models-${TIMESTAMP}"
mkdir -p "$MODEL_BACKUP"

# List current models for reference
ollama list > "$MODEL_BACKUP/model-list.txt"

# Copy model blobs
cp -r ~/.ollama/models/ "$MODEL_BACKUP/"

echo "Model backup complete: $MODEL_BACKUP"
```

## Restore Procedure

### Step 1 — Verify Backup Integrity

```bash
# Check checksums
cd /home/<SSH_USER>/backups/config-YYYYMMDD_HHMMSS/
sha256sum -c MANIFEST.txt
```

### Step 2 — Restore Configs

```bash
BACKUP_DIR="/home/<SSH_USER>/backups/config-YYYYMMDD_HHMMSS"

# SSH config
sudo tar xzf "$BACKUP_DIR/ssh-config.tar.gz" -C /

# Firewall
sudo tar xzf "$BACKUP_DIR/firewall.tar.gz" -C /

# Sysctl
sudo tar xzf "$BACKUP_DIR/sysctl.tar.gz" -C /

# Apply restored configs
sudo sshd -t && sudo systemctl reload sshd
sudo nft -f /etc/nftables.conf
sudo sysctl --system
```

### Step 3 — Restore Models

```bash
MODEL_BACKUP="/home/<SSH_USER>/backups/models-YYYYMMDD_HHMMSS"
cp -r "$MODEL_BACKUP/models/" ~/.ollama/
sudo systemctl restart ollama
ollama list  # Verify models are back
```

## Remote Backup (to Admin PC)

```bash
# From Admin PC (<ADMIN_PC_IP>):
rsync -avz --progress <SSH_USER>@<PI_IP>:/home/<SSH_USER>/backups/ \
  ~/omironclaw-backups/
```

## Backup Schedule

| Frequency | What | Retention |
|-----------|------|-----------|
| Before each phase | Full config | Keep all |
| Weekly | Full config | Keep 4 |
| Monthly | Models + config | Keep 3 |
| Before NVMe migration | Everything | Keep until verified |
