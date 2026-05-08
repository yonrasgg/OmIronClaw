# Runbook: Emergency Lockdown

## Purpose

Immediately secure the target host when a compromise is suspected or an active attack is detected.

## When to Use

- Active SSH brute-force detected (fail2ban alerts saturated)
- Unauthorized process found running
- Unexpected outbound connections detected
- Unknown user account discovered
- File integrity violation detected

## Procedure

### Step 1 — Isolate Network (30 seconds)

```bash
# Drop ALL traffic except your active SSH session
sudo nft flush ruleset
sudo nft add table inet emergency
sudo nft add chain inet emergency input '{ type filter hook input priority 0; policy drop; }'
sudo nft add chain inet emergency output '{ type filter hook output priority 0; policy drop; }'
sudo nft add rule inet emergency input ct state established,related accept
sudo nft add rule inet emergency output ct state established,related accept
sudo nft add rule inet emergency input tcp dport 22 ip saddr <ADMIN_PC_IP> accept
sudo nft add rule inet emergency output tcp sport 22 ip daddr <ADMIN_PC_IP> accept
```

### Step 2 — Capture State (2 minutes)

```bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EVIDENCE_DIR="/home/<SSH_USER>/<PROJECT_ROOT>/loot/incident-${TIMESTAMP}"
mkdir -p "$EVIDENCE_DIR"

# Running processes
ps auxf > "$EVIDENCE_DIR/processes.txt"

# Network connections
ss -tulpn > "$EVIDENCE_DIR/sockets.txt"
ss -anp > "$EVIDENCE_DIR/connections.txt"

# Active users
w > "$EVIDENCE_DIR/active-users.txt"
last -20 > "$EVIDENCE_DIR/recent-logins.txt"

# Recent auth logs
journalctl -u sshd --since "1 hour ago" > "$EVIDENCE_DIR/ssh-recent.txt"

# File modification in last hour
find / -mmin -60 -type f 2>/dev/null > "$EVIDENCE_DIR/modified-files.txt"

# Cron analysis
for user in $(cut -f1 -d: /etc/passwd); do
  crontab -u "$user" -l 2>/dev/null >> "$EVIDENCE_DIR/crontabs.txt"
done
```

### Step 3 — Kill Suspicious Processes

```bash
# Review and kill unknown processes
# NEVER kill blindly — review processes.txt first
kill -9 <PID>
```

### Step 4 — Lock User Accounts

```bash
# Lock all non-root accounts except yours
for user in $(awk -F: '$3 >= 1000 && $1 != "<SSH_USER>" {print $1}' /etc/passwd); do
  sudo usermod -L "$user"
  echo "Locked: $user" >> "$EVIDENCE_DIR/actions.txt"
done
```

### Step 5 — Preserve Logs

```bash
# Copy critical logs before they rotate
sudo cp /var/log/auth.log "$EVIDENCE_DIR/"
sudo cp /var/log/syslog "$EVIDENCE_DIR/"
sudo journalctl --since "24 hours ago" > "$EVIDENCE_DIR/journal-24h.txt"
```

### Step 6 — Assess and Decide

1. Review evidence in `$EVIDENCE_DIR/`
2. Determine scope of compromise
3. Decide: remediate in-place or rebuild from scratch
4. Document decision and rationale

## Recovery

After investigation is complete:

```bash
# Restore normal firewall rules
sudo nft flush ruleset
sudo nft -f /home/<SSH_USER>/<PROJECT_ROOT>/templates/nftables.conf
```

## Post-Incident

- [ ] Document full timeline
- [ ] Root cause analysis
- [ ] Update hardening to prevent recurrence
- [ ] Rotate ALL credentials (SSH keys, service passwords)
