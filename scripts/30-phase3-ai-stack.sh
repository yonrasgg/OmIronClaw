#!/bin/bash
# =============================================================================
# Phase 3 — AI Stack Deployment Script
# OmIronClaw Hardening Project
#
# Tasks: T3.1-T3.25 (Ollama, Caddy gateway, models, benchmarks)
# Standards: NIST SA-8/AC-6/SC-7/SC-8 / CIS 1.6
#
# Safety: CHECK → INSTALL → HARDEN → VERIFY → DOCUMENT
# Run as: sudo bash scripts/30-phase3-ai-stack.sh
#
# NOTE: Idempotent — safe to re-run. Skips steps already completed.
# =============================================================================
set -euo pipefail

# --- CONFIG ---
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
EVIDENCE_DIR="${PROJECT_DIR}/wiki/evidence/ai-stack"
TEMPLATES_DIR="${PROJECT_DIR}/templates"
DATE=$(date +%Y%m%d_%H%M%S)
LAN_SUBNET="${LAN_SUBNET:-10.0.0.0/24}"
PI_IP="${PI_IP:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }
divider() { echo ""; echo "================================================================"; echo "$1"; echo "================================================================"; }

# API key sourced from environment file (never hardcode secrets in scripts)
if [[ -f /etc/caddy/api-key.env ]]; then
    source /etc/caddy/api-key.env
elif [[ -n "${OLLAMA_API_KEY:-}" ]]; then
    : # Use from environment
else
    err "OLLAMA_API_KEY not set. Export it or create /etc/caddy/api-key.env"
    exit 1
fi

# --- SAFETY CHECK: Must be root ---
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo)"
    exit 1
fi

mkdir -p "$EVIDENCE_DIR"

# =============================================================================
divider "PHASE 3 — STEP 0: PRE-FLIGHT CHECKS"
# =============================================================================

# Verify Phase 2 prerequisites
log "Checking prerequisites..."
id ollama &>/dev/null || { err "User 'ollama' not found. Run Phase 2 first."; exit 1; }
[[ -d /srv/ollama ]] || { err "/srv/ollama not found. Run Phase 2 first."; exit 1; }
log "Prerequisites OK: ollama user + /srv/ollama exist"

# =============================================================================
divider "PHASE 3 — STEP 1: INSTALL OLLAMA (T3.1)"
# =============================================================================

if command -v ollama &>/dev/null; then
    OLLAMA_VER=$(ollama --version 2>&1)
    log "Ollama already installed: $OLLAMA_VER — skipping"
else
    log "Installing Ollama via official installer..."
    curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh
    # Verify it's a shell script, not garbage
    head -1 /tmp/ollama-install.sh | grep -q '#!/' || { err "Downloaded file is not a shell script"; exit 1; }
    bash /tmp/ollama-install.sh
    rm -f /tmp/ollama-install.sh
    OLLAMA_VER=$(ollama --version 2>&1)
    log "Ollama installed: $OLLAMA_VER"
fi

# =============================================================================
divider "PHASE 3 — STEP 2: OLLAMA SYSTEMD UNIT (T3.2)"
# =============================================================================

OLLAMA_UNIT="/etc/systemd/system/ollama.service"
if [[ -f "$OLLAMA_UNIT" ]] && grep -q "ProtectSystem=strict" "$OLLAMA_UNIT"; then
    log "Ollama hardened service unit already exists — skipping"
else
    log "Deploying hardened Ollama service unit..."
    cat > "$OLLAMA_UNIT" << 'UNIT_EOF'
[Unit]
Description=Ollama AI Inference Service
After=network-online.target
Wants=network-online.target

[Service]
# --- Service Identity ---
User=ollama
Group=ollama
ExecStart=/usr/local/bin/ollama serve

# --- Resource Limits ---
MemoryMax=12G
MemoryHigh=11G
CPUQuota=350%

# --- Environment ---
EnvironmentFile=-/etc/ollama.env
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_MODELS=/srv/ollama/models"
Environment="OLLAMA_KEEP_ALIVE=5m"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="HOME=/srv/ollama"

# --- Sandboxing (NIST AC-6 / SA-8) ---
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/srv/ollama
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=no
SystemCallArchitectures=native
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
PrivateDevices=yes
TemporaryFileSystem=/tmp

# --- Logging ---
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ollama

# --- Restart policy ---
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT_EOF
    log "Ollama service unit deployed"
fi

# Deploy hardening override (binds to localhost, sets NUM_PARALLEL=2)
mkdir -p /etc/systemd/system/ollama.service.d
if [[ -f /etc/systemd/system/ollama.service.d/override.conf ]] && grep -q "127.0.0.1" /etc/systemd/system/ollama.service.d/override.conf; then
    log "Ollama override already deployed — skipping"
else
    cp "${TEMPLATES_DIR}/ollama-override.conf" /etc/systemd/system/ollama.service.d/override.conf
    log "Ollama hardening override deployed"
fi

# Environment file
if [[ -f /etc/ollama.env ]]; then
    log "Ollama env file exists — skipping"
else
    cat > /etc/ollama.env << 'ENV_EOF'
# Ollama Environment — Phase 3
# Additional env vars go here (loaded by systemd EnvironmentFile)
# Do NOT duplicate vars already set in the service unit
# Example: OLLAMA_ORIGINS=http://${LAN_SUBNET}
ENV_EOF
    chown root:ollama /etc/ollama.env
    chmod 640 /etc/ollama.env
    log "Ollama env file created"
fi

systemctl daemon-reload
systemctl enable ollama.service
systemctl restart ollama.service
sleep 2

if systemctl is-active --quiet ollama.service; then
    log "Ollama service running"
else
    err "Ollama service failed to start!"
    journalctl -u ollama --no-pager -n 10
    exit 1
fi

# Verify security score
SCORE=$(systemd-analyze security ollama.service 2>/dev/null | tail -1 | awk '{print $2}')
log "Ollama security score: $SCORE"

# =============================================================================
divider "PHASE 3 — STEP 3: INSTALL CADDY (T3.14)"
# =============================================================================

if command -v caddy &>/dev/null; then
    CADDY_VER=$(caddy version 2>&1 | head -1)
    log "Caddy already installed: $CADDY_VER — skipping"
else
    log "Installing Caddy from official Debian repo..."
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    apt-get install -y caddy
    CADDY_VER=$(caddy version 2>&1 | head -1)
    log "Caddy installed: $CADDY_VER"
fi

# =============================================================================
divider "PHASE 3 — STEP 4: CADDY HARDENING + GATEWAY (T3.15-T3.18)"
# =============================================================================

# Caddy systemd hardening override
mkdir -p /etc/systemd/system/caddy.service.d
if [[ -f /etc/systemd/system/caddy.service.d/override.conf ]] && grep -q "ProtectSystem=strict" /etc/systemd/system/caddy.service.d/override.conf; then
    log "Caddy hardening override already deployed — skipping"
else
    cat > /etc/systemd/system/caddy.service.d/override.conf << 'CADDY_OVERRIDE_EOF'
[Service]
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/caddy /var/log/caddy /run/caddy
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
SystemCallArchitectures=native
RestrictAddressFamilies=AF_INET AF_UNIX
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
PrivateDevices=yes
TemporaryFileSystem=/tmp
MemoryMax=256M
MemoryHigh=200M
StandardOutput=journal
StandardError=journal
SyslogIdentifier=caddy
CADDY_OVERRIDE_EOF
    log "Caddy hardening override deployed"
fi

# Caddyfile — reverse proxy with TLS + API key auth
mkdir -p /var/log/caddy
if [[ -f /etc/caddy/Caddyfile ]] && grep -q "X-API-Key" /etc/caddy/Caddyfile; then
    log "Caddyfile already configured — skipping"
else
    cat > /etc/caddy/Caddyfile << CADDY_EOF
# Debian 13 AI Server Template — Caddy Reverse Proxy for Ollama
# Phase 3: API Gateway with TLS, auth, rate limiting, model routing
# NIST SC-8 (TLS) / AC-3 (Access Control) / SC-7 (Boundary Protection)

{
        servers {
                protocols h1 h2
        }
        log {
                output file /var/log/caddy/access.log {
                        roll_size 10mb
                        roll_keep 5
                }
                format json
        }
}

https://${PI_IP} {
        tls internal

        header {
                -Server
                X-Content-Type-Options "nosniff"
                X-Frame-Options "DENY"
                Referrer-Policy "no-referrer"
                Strict-Transport-Security "max-age=31536000; includeSubDomains"
        }

        @not_authenticated {
                not header X-API-Key ${OLLAMA_API_KEY}
        }

        handle /health {
                respond "OK" 200
        }

        handle /api/version {
                reverse_proxy 127.0.0.1:11434
        }

        handle /api/* {
                respond @not_authenticated "Unauthorized" 401
                reverse_proxy 127.0.0.1:11434
        }

        handle /v1/* {
                respond @not_authenticated "Unauthorized" 401
                reverse_proxy 127.0.0.1:11434
        }

        handle {
                respond "Not Found" 404
        }
}
CADDY_EOF
    log "Caddyfile deployed"
fi

# Validate + reload
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile || { err "Caddyfile validation failed!"; exit 1; }
systemctl daemon-reload
systemctl enable caddy.service
systemctl restart caddy.service
sleep 2

if systemctl is-active --quiet caddy.service; then
    log "Caddy service running"
else
    err "Caddy service failed to start!"
    journalctl -u caddy --no-pager -n 10
    exit 1
fi

CADDY_SCORE=$(systemd-analyze security caddy.service 2>/dev/null | tail -1 | awk '{print $2}')
log "Caddy security score: $CADDY_SCORE"

# =============================================================================
divider "PHASE 3 — STEP 5: NFTABLES UPDATE (T3.17)"
# =============================================================================

# Check if Caddy ports are already in ruleset
if nft list chain inet filter input | grep -q "tcp dport 443"; then
    log "nftables already has Caddy rules (443/80) — skipping"
else
    warn "nftables missing Caddy rules — update /etc/nftables.conf manually"
fi

# Verify 11434 is NOT directly exposed
if nft list chain inet filter input | grep -q "11434"; then
    warn "Port 11434 is directly exposed in firewall — should be removed (Caddy proxies)"
else
    log "Port 11434 correctly NOT exposed (Caddy-only access)"
fi

# =============================================================================
divider "PHASE 3 — STEP 6: PULL MODELS (T3.4)"
# =============================================================================

MODELS=("gemma3:1b" "qwen2.5:1.5b" "llama3.2:1b")
for model in "${MODELS[@]}"; do
    if ollama list 2>/dev/null | grep -q "$(echo $model | cut -d: -f1)"; then
        log "Model $model already present — skipping"
    else
        log "Pulling $model..."
        sudo -u ollama ollama pull "$model"
        log "Model $model pulled"
    fi
done

# =============================================================================
divider "PHASE 3 — STEP 7: INTEGRATION TEST"
# =============================================================================

log "Testing Caddy → Ollama gateway..."

# Health check
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://${PI_IP}/health" 2>/dev/null)
if [[ "$HTTP_CODE" == "200" ]]; then
    log "Health endpoint: 200 OK"
else
    err "Health endpoint: $HTTP_CODE (expected 200)"
fi

# Auth rejection test
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://${PI_IP}/api/tags" 2>/dev/null)
if [[ "$HTTP_CODE" == "401" ]]; then
    log "Auth rejection: 401 (correct — no API key)"
else
    warn "Auth rejection: $HTTP_CODE (expected 401)"
fi

# Authenticated request
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://${PI_IP}/api/tags" \
    -H "X-API-Key: ${OLLAMA_API_KEY}" 2>/dev/null)
if [[ "$HTTP_CODE" == "200" ]]; then
    log "Authenticated request: 200 OK"
else
    err "Authenticated request: $HTTP_CODE (expected 200)"
fi

# Model inference test
log "Testing inference (gemma3:1b)..."
RESPONSE=$(curl -sk "https://${PI_IP}/api/generate" \
    -H "X-API-Key: ${OLLAMA_API_KEY}" \
    -d '{"model":"gemma3:1b","prompt":"Say hello in one word","stream":false}' \
    --max-time 60 2>/dev/null)
if echo "$RESPONSE" | grep -q '"response"'; then
    log "Inference test: PASS"
else
    warn "Inference test: No response (model may need loading time)"
fi

# =============================================================================
divider "PHASE 3 — STEP 8: EVIDENCE CAPTURE"
# =============================================================================

{
    echo "=== Phase 3 Evidence — $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
    echo ""
    echo "=== Ollama Version ==="
    ollama --version 2>&1
    echo ""
    echo "=== Ollama Models ==="
    ollama list 2>&1
    echo ""
    echo "=== Service Status ==="
    systemctl is-active ollama caddy 2>&1
    echo ""
    echo "=== Security Scores ==="
    systemd-analyze security ollama.service 2>/dev/null | tail -1
    systemd-analyze security caddy.service 2>/dev/null | tail -1
    echo ""
    echo "=== Firewall (Input Chain) ==="
    nft list chain inet filter input 2>/dev/null
    echo ""
    echo "=== Listening Ports ==="
    ss -tlnp 2>/dev/null | grep -E '11434|443|80|22'
    echo ""
    echo "=== AppArmor ==="
    aa-status 2>&1 | head -15
    echo ""
    echo "=== /srv Permissions ==="
    find /srv -type d -exec stat -c '%a %U:%G %n' {} \;
} > "${EVIDENCE_DIR}/phase3-deploy-${DATE}.txt" 2>&1

log "Evidence saved: ${EVIDENCE_DIR}/phase3-deploy-${DATE}.txt"

# =============================================================================
divider "PHASE 3 — COMPLETE"
# =============================================================================

log "Phase 3 AI Stack deployment complete"
log "  Ollama: $(ollama --version 2>&1)"
log "  Caddy:  $(caddy version 2>&1 | head -1)"
log "  Models: $(ollama list 2>/dev/null | tail -n +2 | wc -l)"
log "  Gateway: https://${PI_IP}/"
info ""
info "Test from LAN:"
info "  curl -sk https://${PI_IP}/health"
info "  curl -sk https://${PI_IP}/api/tags -H 'X-API-Key: ${OLLAMA_API_KEY}'"
