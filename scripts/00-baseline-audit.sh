#!/usr/bin/env bash
# 00-baseline-audit.sh — Captura el estado actual del host antes de hardening
# Ejecutar como: sudo bash scripts/00-baseline-audit.sh
# Output: logs/baseline-<timestamp>.log

set -euo pipefail

LOGDIR="${PROJECT_DIR:-/home/${SSH_USER:-$(logname)}/OmIronClaw}/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOGFILE="${LOGDIR}/baseline-${TIMESTAMP}.log"

mkdir -p "$LOGDIR"

log() {
    echo ""
    echo "================================================================="
    echo "=== $1"
    echo "================================================================="
}

{
log "SYSTEM IDENTIFICATION"
echo "--- hostname ---"
hostname
echo "--- uname -a ---"
uname -a
echo "--- os-release ---"
cat /etc/os-release
echo "--- machine-id ---"
cat /etc/machine-id 2>/dev/null || echo "N/A"
echo "--- RPi model ---"
cat /proc/device-tree/model 2>/dev/null || echo "N/A"
echo "--- RPi serial ---"
cat /proc/device-tree/serial-number 2>/dev/null || echo "N/A"
echo "--- vcgencmd bootloader_version ---"
vcgencmd bootloader_version 2>/dev/null || echo "vcgencmd not available"

log "HARDWARE & RESOURCES"
echo "--- CPU info ---"
lscpu
echo "--- Memory ---"
free -h
echo "--- Swap ---"
swapon --show 2>/dev/null || echo "No swap"
echo "--- Temperature ---"
cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "N/A"
echo "--- Block devices ---"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID
echo "--- Disk usage ---"
df -hT
echo "--- Root filesystem ---"
findmnt -no SOURCE,FSTYPE,OPTIONS /

log "NETWORK CONFIGURATION"
echo "--- Interfaces ---"
ip -4 addr show
echo "--- IPv6 ---"
ip -6 addr show 2>/dev/null || echo "N/A"
echo "--- Routes ---"
ip route show
echo "--- DNS ---"
cat /etc/resolv.conf
echo "--- Hostname resolution ---"
hostname -I 2>/dev/null || echo "N/A"
echo "--- NetworkManager connections ---"
nmcli con show 2>/dev/null || echo "NetworkManager not active"
echo "--- WiFi details ---"
nmcli dev wifi list 2>/dev/null | head -5 || echo "N/A"
echo "--- Listening ports ---"
ss -lntup 2>/dev/null || netstat -lntup 2>/dev/null

log "USERS & AUTHENTICATION"
echo "--- /etc/passwd (non-system users) ---"
awk -F: '$3 >= 1000 {print}' /etc/passwd
echo "--- /etc/passwd (system users with shells) ---"
awk -F: '$7 !~ /nologin|false/ {print}' /etc/passwd
echo "--- /etc/group (non-system) ---"
awk -F: '$3 >= 1000 {print}' /etc/group
echo "--- sudo group members ---"
getent group sudo 2>/dev/null || echo "N/A"
echo "--- sudoers files ---"
ls -la /etc/sudoers /etc/sudoers.d/ 2>/dev/null
cat /etc/sudoers.d/* 2>/dev/null || echo "No sudoers.d files"
echo "--- SSH authorized_keys ---"
for home in /home/*; do
    user=$(basename "$home")
    echo "  User: $user"
    cat "$home/.ssh/authorized_keys" 2>/dev/null || echo "    No authorized_keys"
done
echo "--- Root authorized_keys ---"
cat /root/.ssh/authorized_keys 2>/dev/null || echo "No root authorized_keys"
echo "--- SSH host keys ---"
ls -la /etc/ssh/ssh_host_*

log "SSH CONFIGURATION"
echo "--- sshd_config ---"
cat /etc/ssh/sshd_config
echo "--- sshd_config.d/ ---"
ls -la /etc/ssh/sshd_config.d/ 2>/dev/null
for f in /etc/ssh/sshd_config.d/*.conf; do
    [ -f "$f" ] && echo "--- $f ---" && cat "$f"
done
echo "--- SSH service status ---"
systemctl status ssh --no-pager 2>/dev/null || systemctl status sshd --no-pager 2>/dev/null

log "FIREWALL STATUS"
echo "--- nftables ---"
nft list ruleset 2>/dev/null || echo "nftables: no rules or not installed"
echo "--- iptables legacy ---"
iptables -L -n -v 2>/dev/null || echo "iptables not available"
echo "--- ip6tables legacy ---"
ip6tables -L -n -v 2>/dev/null || echo "ip6tables not available"
echo "--- ufw status ---"
ufw status verbose 2>/dev/null || echo "ufw not installed"

log "SERVICES & SYSTEMD"
echo "--- Enabled services ---"
systemctl list-unit-files --state=enabled --type=service --no-pager
echo "--- Running services ---"
systemctl list-units --type=service --state=running --no-pager
echo "--- Listening sockets ---"
systemctl list-sockets --no-pager
echo "--- Failed units ---"
systemctl list-units --failed --no-pager

log "INSTALLED PACKAGES (security relevant)"
echo "--- Package count ---"
dpkg -l | grep -c '^ii'
echo "--- Security-relevant packages ---"
dpkg -l | grep -E 'openssh|openssl|nftables|iptables|fail2ban|apparmor|sudo|curl|wget|netcat|nmap|avahi|samba|nginx|apache|docker|podman|snap' 2>/dev/null || echo "N/A"
echo "--- Pending security updates ---"
apt list --upgradable 2>/dev/null | head -50

log "KERNEL & SYSCTL"
echo "--- Kernel version ---"
uname -r
echo "--- Kernel modules loaded ---"
lsmod | sort
echo "--- sysctl security-relevant ---"
sysctl net.ipv4.ip_forward 2>/dev/null
sysctl net.ipv4.conf.all.accept_redirects 2>/dev/null
sysctl net.ipv4.conf.all.send_redirects 2>/dev/null
sysctl net.ipv4.conf.all.accept_source_route 2>/dev/null
sysctl net.ipv4.conf.all.log_martians 2>/dev/null
sysctl net.ipv4.tcp_syncookies 2>/dev/null
sysctl net.ipv6.conf.all.accept_redirects 2>/dev/null
sysctl net.ipv6.conf.all.accept_source_route 2>/dev/null
sysctl kernel.randomize_va_space 2>/dev/null
sysctl kernel.dmesg_restrict 2>/dev/null
sysctl kernel.kptr_restrict 2>/dev/null
sysctl kernel.yama.ptrace_scope 2>/dev/null
sysctl fs.protected_hardlinks 2>/dev/null
sysctl fs.protected_symlinks 2>/dev/null
sysctl fs.suid_dumpable 2>/dev/null

log "FILE PERMISSIONS (sensitive)"
echo "--- /etc/shadow ---"
ls -la /etc/shadow
echo "--- /etc/passwd ---"
ls -la /etc/passwd
echo "--- /etc/sudoers ---"
ls -la /etc/sudoers
echo "--- SUID binaries ---"
find / -perm -4000 -type f 2>/dev/null | sort
echo "--- SGID binaries ---"
find / -perm -2000 -type f 2>/dev/null | sort
echo "--- World-writable directories ---"
find / -xdev -type d -perm -0002 ! -path "/proc/*" ! -path "/sys/*" 2>/dev/null | head -30

log "CRON & SCHEDULED TASKS"
echo "--- System crontab ---"
cat /etc/crontab
echo "--- cron.d ---"
ls -la /etc/cron.d/ 2>/dev/null
echo "--- User crontabs ---"
for user in $(cut -f1 -d: /etc/passwd); do
    crontab -l -u "$user" 2>/dev/null && echo "  ^ crontab for $user"
done
echo "--- systemd timers ---"
systemctl list-timers --all --no-pager

log "APPARMOR / SECURITY MODULES"
echo "--- AppArmor status ---"
aa-status 2>/dev/null || echo "AppArmor not available"
echo "--- SELinux ---"
getenforce 2>/dev/null || echo "SELinux not available"
echo "--- seccomp available ---"
grep -i seccomp /proc/self/status 2>/dev/null || echo "N/A"

log "RASPBERRY PI SPECIFICS"
echo "--- EEPROM update status ---"
rpi-eeprom-update 2>/dev/null || echo "rpi-eeprom-update not available"
echo "--- Boot config ---"
cat /boot/firmware/config.txt 2>/dev/null || cat /boot/config.txt 2>/dev/null || echo "N/A"
echo "--- cmdline ---"
cat /boot/firmware/cmdline.txt 2>/dev/null || cat /boot/cmdline.txt 2>/dev/null || echo "N/A"
echo "--- GPU memory ---"
vcgencmd get_mem gpu 2>/dev/null || echo "N/A"
echo "--- Throttled status ---"
vcgencmd get_throttled 2>/dev/null || echo "N/A"

log "AUDIT COMPLETE"
echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Hostname: $(hostname)"
echo "IP: $(hostname -I 2>/dev/null)"

} 2>&1 | tee "$LOGFILE"

echo ""
echo "Baseline audit saved to: $LOGFILE"
