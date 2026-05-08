#!/usr/bin/env bash
# 80-backup-to-hdd.sh — Weekly SD → HDD backup
# Phase 10 — Storage Optimization
# NIST CP-9: Information System Backup
#
# Backs up critical SD card paths to /mnt/data/backups/
# Designed to run via systemd timer (Sun 05:00)

set -euo pipefail

DATA_MOUNT="${DATA_MOUNT:-/mnt/data}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT_NAME="${PROJECT_NAME:-OmIronClaw}"
BACKUP_DIR="${DATA_MOUNT}/backups"
DATE=$(date +%Y%m%d)
LOG="/var/log/health-monitor/backup-${DATE}.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

# Pre-flight checks
if ! mountpoint -q "$DATA_MOUNT"; then
    log "ERROR: ${DATA_MOUNT} not mounted. Aborting backup."
    exit 1
fi

mkdir -p "$BACKUP_DIR" "${LOG%/*}"

log "=== SD → HDD Backup Started ==="

# Backup critical configs
log "Backing up /etc configs..."
rsync -aH --delete \
    /etc/nftables.conf \
    /etc/ssh/sshd_config \
    /etc/caddy/Caddyfile \
    /etc/systemd/system/ollama.service \
    /etc/systemd/system/openclaw.service \
    /etc/sysctl.d/ \
    "$BACKUP_DIR/etc-configs/" 2>>"$LOG"

# Backup fstab
log "Backing up fstab..."
cp /etc/fstab "$BACKUP_DIR/fstab-${DATE}"

# Backup user home (scripts, templates, wiki)
log "Backing up project repo..."
rsync -aH --delete --exclude='.git' --exclude='node_modules' \
    "${PROJECT_ROOT}/" \
    "$BACKUP_DIR/${PROJECT_NAME}/" 2>>"$LOG"

# Cleanup: keep only last 4 weekly fstab snapshots
log "Cleaning old fstab snapshots (keep 4)..."
ls -t "$BACKUP_DIR"/fstab-* 2>/dev/null | tail -n +5 | xargs -r rm --

# Disk usage report
log "Backup dir usage: $(du -sh "$BACKUP_DIR" | cut -f1)"
log "Storage free: $(df -h "$DATA_MOUNT" | awk 'NR==2{print $4}')"
log "=== Backup Complete ==="
