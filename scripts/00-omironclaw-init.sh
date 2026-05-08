#!/usr/bin/env bash
# OmIronClaw bootstrap wizard
# Generates a sanitized, user-specific deployment bundle from template files.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
STAMP="$(date +%Y%m%d_%H%M%S)"
RENDER_DIR="${BUILD_DIR}/rendered-${STAMP}"
GENERATED_ENV="${BUILD_DIR}/.env.generated"
SECRETS_ENV="${BUILD_DIR}/.secrets.local"
SETUP_GUIDE="${BUILD_DIR}/SETUP_GUIDE.md"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    return 1
  fi
  return 0
}

check_dependencies() {
  local missing=0
  require_cmd envsubst || {
    echo "Install package: gettext-base"
    missing=1
  }
  require_cmd sed || missing=1
  require_cmd find || missing=1
  if [[ "$missing" -ne 0 ]]; then
    echo "Dependency check failed. Resolve missing commands and rerun."
    exit 1
  fi
}

print_banner() {
cat <<'BANNER'

▄██████▄    ▄▄▄▄███▄▄▄▄    ▄█     ▄████████  ▄██████▄  ███▄▄▄▄    ▄████████  ▄█          ▄████████  ▄█     █▄ 
███    ███ ▄██▀▀▀███▀▀▀██▄ ███    ███    ███ ███    ███ ███▀▀▀██▄ ███    ███ ███         ███    ███ ███     ███
███    ███ ███   ███   ███ ███▌   ███    ███ ███    ███ ███   ███ ███    █▀  ███         ███    ███ ███     ███
███    ███ ███   ███   ███ ███▌  ▄███▄▄▄▄██▀ ███    ███ ███   ███ ███        ███         ███    ███ ███     ███
███    ███ ███   ███   ███ ███▌ ▀▀███▀▀▀▀▀   ███    ███ ███   ███ ███        ███       ▀███████████ ███     ███
███    ███ ███   ███   ███ ███  ▀███████████ ███    ███ ███   ███ ███    █▄  ███         ███    ███ ███     ███
███    ███ ███   ███   ███ ███    ███    ███ ███    ███ ███   ███ ███    ███ ███▌    ▄   ███    ███ ███ ▄█▄ ███
 ▀██████▀   ▀█   ███   █▀  █▀     ███    ███  ▀██████▀   ▀█   █▀  ████████▀  █████▄▄██   ███    █▀   ▀███▀███▀ 
                                  ███    ███                                 ▀

                                                    OLLAMA + OPENCLAW
                                                    ZERO-TRUST TEMPLATE



                       ==              .=-                                      ::              :-               
                     ++-++-           ++:++.                                      --------------                 
                     +-  ++          -+   ++                                   --------------------              
                    =+    += :+++++  ++   ++.                                ----------------------==            
                    ++    *+++    :++++   ++-                               ------=+=--------=+=----==.          
                    :+-=+++:         ++++:++                               ------=+  +------=+  +--====:         
                    +++= :            : :++++                             --------+++-------=+++=-======.        
                  =+-                       ++                        .------------------------========--:=.     
                 -+:                         ++            .+       .-----===----------------========------==-   
                 ++                           ++         :-+++-:    :---====--------------============----====   
                 ++    +++  +++  .+++  ++-    ++         =+++==-     ======-------------=====================    
                 -+.      :+         +       ++            .+            ---------------=================        
                  =+-     +     -    =:     ++.                           ------------==================.        
                  ++      .+        :+       ++                           :----------==================-         
                 -+         -+++++++         ++                            --------===================-          
                 ++                          ++-                             ==--====================.           
                 =+                          ++                               ---===================             
                  ++                         ++                                 .================-               
                  :++                       ++                                      ===.--.===:                  
                  ++                         ++                                     ===    ===.                  
                  =:

enhanced by @yonrasgg Geovanny Alpizar.

BANNER
}

prompt_default() {
  local __var="$1"
  local __prompt="$2"
  local __default="$3"
  local __value
  read -r -p "${__prompt} [${__default}]: " __value
  printf -v "${__var}" '%s' "${__value:-${__default}}"
}

choose_mode() {
  echo "Select AI mode:"
  echo "  1) local   (Ollama only)"
  echo "  2) cloud   (API providers only)"
  echo "  3) hybrid  (Ollama + API providers)"
  while true; do
    read -r -p "Choice [1-3]: " choice
    case "$choice" in
      1) AI_MODE="local"; break ;;
      2) AI_MODE="cloud"; break ;;
      3) AI_MODE="hybrid"; break ;;
      *) echo "Invalid choice. Use 1, 2, or 3." ;;
    esac
  done
}

provider_menu() {
  local __var="$1"
  echo "Choose provider for ${__var}:"
  echo "  1) openai"
  echo "  2) google"
  echo "  3) anthropic"
  echo "  4) openrouter"
  echo "  5) custom"
  while true; do
    read -r -p "Choice [1-5]: " p
    case "$p" in
      1) printf -v "${__var}" '%s' "openai"; break ;;
      2) printf -v "${__var}" '%s' "google"; break ;;
      3) printf -v "${__var}" '%s' "anthropic"; break ;;
      4) printf -v "${__var}" '%s' "openrouter"; break ;;
      5) printf -v "${__var}" '%s' "custom"; break ;;
      *) echo "Invalid choice. Use 1-5." ;;
    esac
  done
}

provider_base_url() {
  case "$1" in
    openai) echo "https://api.openai.com/v1" ;;
    google) echo "https://generativelanguage.googleapis.com/v1beta" ;;
    anthropic) echo "https://api.anthropic.com" ;;
    openrouter) echo "https://openrouter.ai/api/v1" ;;
    custom) echo "https://api.example.com/v1" ;;
    *) echo "" ;;
  esac
}

provider_docs_url() {
  case "$1" in
    openai) echo "https://platform.openai.com/docs/overview" ;;
    google) echo "https://ai.google.dev/gemini-api/docs" ;;
    anthropic) echo "https://docs.anthropic.com/en/api/getting-started" ;;
    openrouter) echo "https://openrouter.ai/docs/quickstart" ;;
    custom) echo "https://example.com/docs" ;;
    *) echo "" ;;
  esac
}

provider_keys_url() {
  case "$1" in
    openai) echo "https://platform.openai.com/api-keys" ;;
    google) echo "https://aistudio.google.com/app/apikey" ;;
    anthropic) echo "https://console.anthropic.com/settings/keys" ;;
    openrouter) echo "https://openrouter.ai/keys" ;;
    custom) echo "https://example.com/keys" ;;
    *) echo "" ;;
  esac
}

provider_default_model() {
  case "$1" in
    openai) echo "gpt-4o-mini" ;;
    google) echo "gemini-2.5-flash" ;;
    anthropic) echo "claude-3-5-haiku-latest" ;;
    openrouter) echo "openai/gpt-4o-mini" ;;
    custom) echo "your-model-id" ;;
    *) echo "" ;;
  esac
}

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

replace_token_in_tree() {
  local token="$1"
  local value="$2"
  local root="$3"
  local escaped
  escaped="$(escape_sed "$value")"

  while IFS= read -r -d '' file; do
    sed -i "s|${token}|${escaped}|g" "$file"
  done < <(find "$root" -type f \( -name '*.md' -o -name '*.conf' -o -name '*.rules' -o -name '*.service' -o -name '*.timer' -o -name '*.json' -o -name '*.yml' -o -name '*.yaml' -o -name '*.sh' -o -name '*.txt' \) -print0)
}

render_bundle() {
  mkdir -p "${RENDER_DIR}/templates"
  mkdir -p "${RENDER_DIR}/wiki"
  cp -a "${PROJECT_DIR}/templates/." "${RENDER_DIR}/templates/"
  cp -a "${PROJECT_DIR}/wiki/." "${RENDER_DIR}/wiki/"

  local vars='${PROJECT_ROOT} ${PI_HOSTNAME} ${SSH_USER} ${LAN_SUBNET} ${USB_TETHER_SUBNET} ${KALI_IP} ${LAB_IP} ${COMPUTE_IP} ${ADMIN_PC_IP} ${IOT_BLOCK_IP} ${PI_IP} ${OLLAMA_API_KEY}'

  while IFS= read -r -d '' file; do
    envsubst "$vars" < "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
  done < <(find "${RENDER_DIR}/templates" -type f \( -name '*.conf' -o -name '*.rules' -o -name '*.service' -o -name '*.timer' -o -name '*.json' -o -name '*.yml' -o -name '*.yaml' \) -print0)

  replace_token_in_tree "<PROJECT_ROOT>" "${PROJECT_ROOT}" "${RENDER_DIR}"
  replace_token_in_tree "<PI_HOSTNAME>" "${PI_HOSTNAME}" "${RENDER_DIR}"
  replace_token_in_tree "<SERVER_HOSTNAME>" "${PI_HOSTNAME}" "${RENDER_DIR}"
  replace_token_in_tree "<PI_IP>" "${PI_IP}" "${RENDER_DIR}"
  replace_token_in_tree "<SERVER_IP>" "${PI_IP}" "${RENDER_DIR}"
  replace_token_in_tree "<SSH_USER>" "${SSH_USER}" "${RENDER_DIR}"
  replace_token_in_tree "<ADMIN_PC_IP>" "${ADMIN_PC_IP}" "${RENDER_DIR}"
  replace_token_in_tree "<ADMIN_IP>" "${ADMIN_PC_IP}" "${RENDER_DIR}"
  replace_token_in_tree "<LAN_SUBNET>" "${LAN_SUBNET}" "${RENDER_DIR}"
  replace_token_in_tree "<ADMIN_ALLOWED_SUBNET>" "${ADMIN_ALLOWED_SUBNET}" "${RENDER_DIR}"
  replace_token_in_tree "<MGMT_SUBNET>" "${LAN_SUBNET}" "${RENDER_DIR}"
  replace_token_in_tree "<AUDIT_HOSTNAME>" "${AUDIT_HOSTNAME}" "${RENDER_DIR}"
  replace_token_in_tree "<AUDIT_IP>" "${KALI_IP}" "${RENDER_DIR}"
}

write_generated_env() {
  mkdir -p "${BUILD_DIR}"
  cat > "${GENERATED_ENV}" <<EOF
# OmIronClaw generated environment
# Generated at: ${STAMP}
PROJECT_ROOT="${PROJECT_ROOT}"
PI_HOSTNAME="${PI_HOSTNAME}"
PI_IP="${PI_IP}"
LAN_SUBNET="${LAN_SUBNET}"
ADMIN_ALLOWED_SUBNET="${ADMIN_ALLOWED_SUBNET}"
USB_TETHER_SUBNET="${USB_TETHER_SUBNET}"
GATEWAY_IP="${GATEWAY_IP}"
SSH_USER="${SSH_USER}"
AUDIT_HOSTNAME="${AUDIT_HOSTNAME}"
KALI_IP="${KALI_IP}"
LAB_IP="${LAB_IP}"
COMPUTE_IP="${COMPUTE_IP}"
ADMIN_PC_IP="${ADMIN_PC_IP}"
IOT_BLOCK_IP="${IOT_BLOCK_IP}"
AI_MODE="${AI_MODE}"
LOCAL_MODELS="${LOCAL_MODELS}"
OPENCLAW_LOCAL_MODEL="${OPENCLAW_LOCAL_MODEL}"
PRIMARY_PROVIDER="${PRIMARY_PROVIDER}"
PRIMARY_MODEL="${PRIMARY_MODEL}"
PRIMARY_PROVIDER_URL="${PRIMARY_PROVIDER_URL}"
PRIMARY_PROVIDER_DOCS="${PRIMARY_PROVIDER_DOCS}"
PRIMARY_PROVIDER_KEYS_URL="${PRIMARY_PROVIDER_KEYS_URL}"
FALLBACK_PROVIDER="${FALLBACK_PROVIDER}"
FALLBACK_MODEL="${FALLBACK_MODEL}"
FALLBACK_PROVIDER_URL="${FALLBACK_PROVIDER_URL}"
FALLBACK_PROVIDER_DOCS="${FALLBACK_PROVIDER_DOCS}"
FALLBACK_PROVIDER_KEYS_URL="${FALLBACK_PROVIDER_KEYS_URL}"
OLLAMA_API_KEY="${OLLAMA_API_KEY}"
EOF
}

maybe_capture_api_keys() {
  local store
  read -r -p "Store API keys in ${SECRETS_ENV} (chmod 600)? [y/N]: " store
  if [[ "${store}" =~ ^[Yy]$ ]]; then
    local primary_key=""
    local fallback_key=""
    if [[ -n "${PRIMARY_PROVIDER}" ]]; then
      read -rs -p "Enter PRIMARY API key for ${PRIMARY_PROVIDER} (optional): " primary_key
      echo
    fi
    if [[ -n "${FALLBACK_PROVIDER}" ]]; then
      read -rs -p "Enter FALLBACK API key for ${FALLBACK_PROVIDER} (optional): " fallback_key
      echo
    fi

    cat > "${SECRETS_ENV}" <<EOF
# Local secret file (do not commit)
PRIMARY_PROVIDER_API_KEY="${primary_key}"
FALLBACK_PROVIDER_API_KEY="${fallback_key}"
EOF
    chmod 600 "${SECRETS_ENV}"
  fi
}

write_setup_guide() {
  {
    cat <<EOF
# OmIronClaw Setup Guide

## Deployment Profile
- AI mode: ${AI_MODE}
- Project root: /home/${SSH_USER}/${PROJECT_ROOT}
- Hostname: ${PI_HOSTNAME}
- Host IP: ${PI_IP}
- Admin user: ${SSH_USER}
- Admin allowed subnet: ${ADMIN_ALLOWED_SUBNET}

## Provider Selection
- Primary provider: ${PRIMARY_PROVIDER:-none}
- Primary model: ${PRIMARY_MODEL:-n/a}
- Primary API URL: ${PRIMARY_PROVIDER_URL:-n/a}
- Primary docs: ${PRIMARY_PROVIDER_DOCS:-n/a}
- Primary API key guide: ${PRIMARY_PROVIDER_KEYS_URL:-n/a}
- Fallback provider: ${FALLBACK_PROVIDER:-none}
- Fallback model: ${FALLBACK_MODEL:-n/a}
- Fallback API URL: ${FALLBACK_PROVIDER_URL:-n/a}
- Fallback docs: ${FALLBACK_PROVIDER_DOCS:-n/a}
- Fallback API key guide: ${FALLBACK_PROVIDER_KEYS_URL:-n/a}

## Local Ollama Mode
- Selected models: ${LOCAL_MODELS:-none}
- OpenClaw local model target: ${OPENCLAW_LOCAL_MODEL:-none}
- Local REST API endpoint: http://127.0.0.1:11434
- Through Caddy (recommended): https://${PI_IP}/api/* and https://${PI_IP}/v1/*

Example local REST call:
\`\`\`bash
curl -s http://127.0.0.1:11434/api/generate -d '{
  "model": "${OPENCLAW_LOCAL_MODEL:-${LOCAL_MODELS%%,*}}",
  "prompt": "Reply with OK.",
  "stream": false
}'
\`\`\`

## Manual Steps (Required)
1. Review and deploy rendered templates from: ${RENDER_DIR}/templates
2. Review rendered wiki from: ${RENDER_DIR}/wiki
3. Generate and validate SSH key access before hardening:
  \`bash scripts/02-ssh-key-bootstrap.sh --host ${PI_IP} --user ${SSH_USER}\`
4. Configure /etc/caddy/api-key.env with a strong API key.
5. Configure /etc/openclaw.env with gateway token and optional channel tokens.
6. If using Telegram/WhatsApp, complete pairing/login flows manually.

## OpenClaw Guidance by Mode
- local: set default routing to \`ollama/${OPENCLAW_LOCAL_MODEL:-${LOCAL_MODELS%%,*}}\` and keep cloud providers disabled.
- cloud: set primary to \`${PRIMARY_PROVIDER:-provider}/${PRIMARY_MODEL:-model}\` and optionally fallback to \`${FALLBACK_PROVIDER:-none}/${FALLBACK_MODEL:-none}\`.
- hybrid: keep cloud primary/fallback and reserve \`ollama/${OPENCLAW_LOCAL_MODEL:-${LOCAL_MODELS%%,*}}\` for offline agent path.

## Suggested Execution Order
1. scripts/00-baseline-audit.sh
2. scripts/10-phase1-foundation.sh
3. scripts/20-phase2-service-optimization.sh
4. scripts/30-phase3-ai-stack.sh

## Validation
- Run scripts/01-prepublish-check.sh before publishing.
- Validate exposed ports from an external host.
- Confirm OpenClaw and Ollama are not directly LAN-exposed except via Caddy.
EOF
  } > "${SETUP_GUIDE}"
}

run_phase_script() {
  local script_path="$1"
  if [[ ! -f "$script_path" ]]; then
    echo "Skipping missing script: $script_path"
    return
  fi
  echo "Running $script_path"
  if [[ $EUID -eq 0 ]]; then
    bash "$script_path"
  else
    sudo bash "$script_path"
  fi
}

maybe_bootstrap_ssh_key() {
  local answer
  echo
  read -r -p "Run SSH key bootstrap helper now? [y/N]: " answer
  if [[ "${answer}" =~ ^[Yy]$ ]]; then
    if [[ -x "${PROJECT_DIR}/scripts/02-ssh-key-bootstrap.sh" ]]; then
      if ! bash "${PROJECT_DIR}/scripts/02-ssh-key-bootstrap.sh" --host "${PI_IP}" --user "${SSH_USER}" --port 22; then
        echo "SSH bootstrap helper did not complete. Continue with manual SSH provisioning."
      fi
    else
      echo "SSH bootstrap helper not found. Use manual key provisioning before hardening."
    fi
  fi
}

maybe_run_phases() {
  local plan
  echo
  echo "Phase execution options:"
  echo "  none        = only generate files and guide"
  echo "  baseline    = run phase 0"
  echo "  foundation  = run phase 0-2"
  echo "  full-core   = run phase 0-3"
  read -r -p "Execution plan [none/baseline/foundation/full-core] (default: none): " plan
  plan="${plan:-none}"

  case "$plan" in
    none)
      echo "Skipping automatic phase execution."
      ;;
    baseline)
      run_phase_script "${PROJECT_DIR}/scripts/00-baseline-audit.sh"
      ;;
    foundation)
      run_phase_script "${PROJECT_DIR}/scripts/00-baseline-audit.sh"
      run_phase_script "${PROJECT_DIR}/scripts/10-phase1-foundation.sh"
      run_phase_script "${PROJECT_DIR}/scripts/20-phase2-service-optimization.sh"
      ;;
    full-core)
      run_phase_script "${PROJECT_DIR}/scripts/00-baseline-audit.sh"
      run_phase_script "${PROJECT_DIR}/scripts/10-phase1-foundation.sh"
      run_phase_script "${PROJECT_DIR}/scripts/20-phase2-service-optimization.sh"
      run_phase_script "${PROJECT_DIR}/scripts/30-phase3-ai-stack.sh"
      ;;
    *)
      echo "Unknown option '$plan'. Skipping execution."
      ;;
  esac
}

main() {
  check_dependencies
  print_banner
  echo "OmIronClaw bootstrap wizard"
  echo

  prompt_default PROJECT_ROOT "Project folder name" "OmIronClaw"
  prompt_default PI_HOSTNAME "Server hostname" "omironclaw-node"
  prompt_default PI_IP "Server IP" "10.0.0.10"
  prompt_default GATEWAY_IP "Gateway IP" "10.0.0.1"
  prompt_default LAN_SUBNET "LAN subnet CIDR" "10.0.0.0/24"
  prompt_default ADMIN_ALLOWED_SUBNET "Admin allowed subnet CIDR" "${LAN_SUBNET}"
  prompt_default USB_TETHER_SUBNET "USB tether subnet CIDR" "10.42.0.0/24"
  prompt_default SSH_USER "Primary SSH user" "admin"
  prompt_default AUDIT_HOSTNAME "Optional auditor hostname" "auditor-node"
  prompt_default KALI_IP "Optional auditor IP" "10.0.0.20"
  prompt_default LAB_IP "Optional managed host A IP" "10.0.0.30"
  prompt_default COMPUTE_IP "Optional managed host B IP" "10.0.0.31"
  prompt_default ADMIN_PC_IP "Optional admin workstation IP" "10.0.0.40"
  prompt_default IOT_BLOCK_IP "Optional IoT block target IP" "10.0.0.250"
  prompt_default OLLAMA_API_KEY "Gateway API key placeholder" "CHANGE_ME_API_KEY"

  choose_mode

  LOCAL_MODELS=""
  OPENCLAW_LOCAL_MODEL=""
  PRIMARY_PROVIDER=""
  PRIMARY_MODEL=""
  PRIMARY_PROVIDER_URL=""
  PRIMARY_PROVIDER_DOCS=""
  PRIMARY_PROVIDER_KEYS_URL=""
  FALLBACK_PROVIDER=""
  FALLBACK_MODEL=""
  FALLBACK_PROVIDER_URL=""
  FALLBACK_PROVIDER_DOCS=""
  FALLBACK_PROVIDER_KEYS_URL=""

  if [[ "${AI_MODE}" == "local" || "${AI_MODE}" == "hybrid" ]]; then
    prompt_default LOCAL_MODELS "Local Ollama models (comma-separated)" "qwen2.5:7b,phi4-mini"
    prompt_default OPENCLAW_LOCAL_MODEL "OpenClaw local model" "${LOCAL_MODELS%%,*}"
  fi

  if [[ "${AI_MODE}" == "cloud" || "${AI_MODE}" == "hybrid" ]]; then
    provider_menu PRIMARY_PROVIDER
    PRIMARY_PROVIDER_URL="$(provider_base_url "${PRIMARY_PROVIDER}")"
    PRIMARY_PROVIDER_DOCS="$(provider_docs_url "${PRIMARY_PROVIDER}")"
    PRIMARY_PROVIDER_KEYS_URL="$(provider_keys_url "${PRIMARY_PROVIDER}")"

    if [[ "${PRIMARY_PROVIDER}" == "custom" ]]; then
      prompt_default PRIMARY_PROVIDER_URL "Primary custom provider URL" "https://api.example.com/v1"
      prompt_default PRIMARY_PROVIDER_DOCS "Primary custom provider docs URL" "https://example.com/docs"
      prompt_default PRIMARY_PROVIDER_KEYS_URL "Primary custom API key docs URL" "https://example.com/keys"
    fi

    prompt_default PRIMARY_MODEL "Primary model ID" "$(provider_default_model "${PRIMARY_PROVIDER}")"

    read -r -p "Configure fallback cloud provider? [y/N]: " use_fallback
    if [[ "${use_fallback}" =~ ^[Yy]$ ]]; then
      provider_menu FALLBACK_PROVIDER
      FALLBACK_PROVIDER_URL="$(provider_base_url "${FALLBACK_PROVIDER}")"
      FALLBACK_PROVIDER_DOCS="$(provider_docs_url "${FALLBACK_PROVIDER}")"
      FALLBACK_PROVIDER_KEYS_URL="$(provider_keys_url "${FALLBACK_PROVIDER}")"

      if [[ "${FALLBACK_PROVIDER}" == "custom" ]]; then
        prompt_default FALLBACK_PROVIDER_URL "Fallback custom provider URL" "https://api.example.com/v1"
        prompt_default FALLBACK_PROVIDER_DOCS "Fallback custom provider docs URL" "https://example.com/docs"
        prompt_default FALLBACK_PROVIDER_KEYS_URL "Fallback custom API key docs URL" "https://example.com/keys"
      fi

      prompt_default FALLBACK_MODEL "Fallback model ID" "$(provider_default_model "${FALLBACK_PROVIDER}")"
    fi

    maybe_capture_api_keys
  fi

  render_bundle
  write_generated_env
  write_setup_guide

  echo
  echo "Generated files:"
  echo "  - ${GENERATED_ENV}"
  echo "  - ${SETUP_GUIDE}"
  echo "  - ${RENDER_DIR}/templates"

  maybe_bootstrap_ssh_key
  maybe_run_phases

  echo
  echo "Done. Review ${SETUP_GUIDE} for manual OpenClaw/Ollama steps and provider docs."
}

main "$@"
