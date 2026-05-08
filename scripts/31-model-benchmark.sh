#!/usr/bin/env bash
# Debian 13 AI Server Template — Model Benchmark Script
# Phase 3: Evaluate models on target host profile (CPU-only baseline)
# NIST SA-8 / CIS Benchmark evidence collection
#
# Usage: ./30-model-benchmark.sh <model_name> [prompt]
# Example: ./30-model-benchmark.sh gemma3:1b
#          ./30-model-benchmark.sh phi4-mini "Explain TLS in 3 sentences"

set -euo pipefail

# --- Config ---
OLLAMA_API="http://127.0.0.1:11434"
EVIDENCE_DIR="$(dirname "$0")/../wiki/evidence/ai-stack"
THERMAL="/sys/class/thermal/thermal_zone0/temp"
DEFAULT_PROMPT="Explain what a reverse proxy does in exactly 3 sentences. Be concise."
SHORT_PROMPT="What is 2+2?"
LONG_PROMPT="Write a detailed 200-word explanation of how TLS 1.3 handshake works, including the key exchange mechanism, cipher negotiation, and how it differs from TLS 1.2. Include specific technical details about ECDHE, AEAD ciphers, and 0-RTT resumption."

# --- Args ---
MODEL="${1:?Usage: $0 <model_name> [prompt]}"
CUSTOM_PROMPT="${2:-}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTFILE="${EVIDENCE_DIR}/benchmark-${MODEL//[:\/]/_}-${TIMESTAMP}.txt"

# --- Functions ---
get_temp() {
    if [[ -f "$THERMAL" ]]; then
        echo "scale=1; $(cat "$THERMAL") / 1000" | bc
    else
        echo "N/A"
    fi
}

get_ram() {
    free -m | awk '/^Mem:/{printf "%.0f/%dMB (%.0f%%)", $3, $2, $3/$2*100}'
}

get_ollama_ram() {
    ps -C ollama -o rss= 2>/dev/null | awk '{sum+=$1} END {printf "%.0fMB", sum/1024}' || echo "N/A"
}

benchmark_prompt() {
    local label="$1"
    local prompt="$2"
    local prompt_len=${#prompt}

    echo "  [$label] Prompt: ${prompt:0:60}... (${prompt_len} chars)"

    local temp_before
    temp_before=$(get_temp)

    local start_ns
    start_ns=$(date +%s%N)

    # Run inference and capture full response + timing
    local response
    response=$(curl -s --max-time 120 "${OLLAMA_API}/api/generate" \
        -d "{\"model\":\"${MODEL}\",\"prompt\":\"${prompt}\",\"stream\":false}" 2>&1)

    local end_ns
    end_ns=$(date +%s%N)
    local elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))

    local temp_after
    temp_after=$(get_temp)

    # Parse Ollama metrics from response
    local total_duration eval_count eval_duration load_duration prompt_eval_duration
    total_duration=$(echo "$response" | grep -o '"total_duration":[0-9]*' | cut -d: -f2)
    eval_count=$(echo "$response" | grep -o '"eval_count":[0-9]*' | cut -d: -f2)
    eval_duration=$(echo "$response" | grep -o '"eval_duration":[0-9]*' | cut -d: -f2)
    load_duration=$(echo "$response" | grep -o '"load_duration":[0-9]*' | cut -d: -f2)
    prompt_eval_duration=$(echo "$response" | grep -o '"prompt_eval_duration":[0-9]*' | cut -d: -f2)

    # Calculate tokens/sec
    local tokens_per_sec="N/A"
    if [[ -n "$eval_count" && -n "$eval_duration" && "$eval_duration" -gt 0 ]]; then
        tokens_per_sec=$(echo "scale=2; $eval_count / ($eval_duration / 1000000000)" | bc)
    fi

    # Calculate first token latency (load + prompt eval)
    local first_token_ms="N/A"
    if [[ -n "$load_duration" && -n "$prompt_eval_duration" ]]; then
        first_token_ms=$(echo "scale=0; ($load_duration + $prompt_eval_duration) / 1000000" | bc)
    fi

    local total_sec="N/A"
    if [[ -n "$total_duration" && "$total_duration" -gt 0 ]]; then
        total_sec=$(echo "scale=2; $total_duration / 1000000000" | bc)
    fi

    local ollama_ram
    ollama_ram=$(get_ollama_ram)

    # Output results
    cat <<RESULT

### $label
| Metric | Value |
|--------|-------|
| Prompt length | ${prompt_len} chars |
| Wall time | ${elapsed_ms}ms |
| Total (Ollama) | ${total_sec}s |
| First token | ${first_token_ms}ms |
| Tokens generated | ${eval_count:-N/A} |
| Tokens/sec | ${tokens_per_sec} |
| Temp before | ${temp_before}°C |
| Temp after | ${temp_after}°C |
| Ollama RSS | ${ollama_ram} |
RESULT
}

# --- Pre-flight ---
echo "╔══════════════════════════════════════════════════════╗"
echo "║  MODEL BENCHMARK — ${MODEL}"
echo "║  $(date '+%Y-%m-%d %H:%M:%S') — target host profile"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Check Ollama is running
if ! curl -s --connect-timeout 2 "${OLLAMA_API}/api/version" >/dev/null 2>&1; then
    echo "ERROR: Ollama not responding at ${OLLAMA_API}"
    exit 1
fi

# Check model exists, pull if needed
echo "--- Checking model availability ---"
if ! curl -s "${OLLAMA_API}/api/show" -d "{\"name\":\"${MODEL}\"}" | grep -q '"modelfile"'; then
    echo "Model ${MODEL} not found locally. Pulling..."
    curl -s "${OLLAMA_API}/api/pull" -d "{\"name\":\"${MODEL}\",\"stream\":false}"
    echo "Pull complete."
fi

# System baseline
mkdir -p "$EVIDENCE_DIR"
echo ""
echo "--- System Baseline ---"
echo "RAM: $(get_ram)"
echo "Temp: $(get_temp)°C"
echo "CPU governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A)"
echo "Ollama version: $(curl -s ${OLLAMA_API}/api/version | grep -o '"version":"[^"]*"')"
echo ""

# Model info
echo "--- Model Info ---"
MODEL_SIZE=$(curl -s "${OLLAMA_API}/api/tags" | python3 -c "import sys,json;[print(m['size']) for m in json.load(sys.stdin)['models'] if m['name']=='${MODEL}']" 2>/dev/null || true)
MODEL_PARAMS=$(curl -s "${OLLAMA_API}/api/show" -d "{\"name\":\"${MODEL}\"}" | python3 -c "import sys,json;print(json.load(sys.stdin).get('details',{}).get('parameter_size','N/A'))" 2>/dev/null || true)
MODEL_QUANT=$(curl -s "${OLLAMA_API}/api/show" -d "{\"name\":\"${MODEL}\"}" | python3 -c "import sys,json;print(json.load(sys.stdin).get('details',{}).get('quantization_level','N/A'))" 2>/dev/null || true)
if [[ -n "${MODEL_SIZE:-}" && "$MODEL_SIZE" -gt 0 ]] 2>/dev/null; then
    echo "Model disk size: $(echo "scale=0; $MODEL_SIZE / 1048576" | bc)MB"
else
    MODEL_SIZE=""
    echo "Model disk size: (unable to determine)"
fi
echo "Parameters: ${MODEL_PARAMS:-N/A}"
echo "Quantization: ${MODEL_QUANT:-N/A}"
echo ""

# --- Run benchmarks ---
echo "=== Running 3 benchmark passes ==="

# Warmup (load model into memory)
echo "--- Warmup pass (loading model) ---"
curl -s --max-time 120 "${OLLAMA_API}/api/generate" \
    -d "{\"model\":\"${MODEL}\",\"prompt\":\"hello\",\"stream\":false}" >/dev/null 2>&1
echo "Model loaded."
echo ""

{
    echo "# Benchmark: ${MODEL}"
    echo "# Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# Host: $(hostname) | hardware profile: template baseline"
    echo "# Ollama: $(curl -s ${OLLAMA_API}/api/version | grep -o '"version":"[^"]*"')"
    echo ""

    echo "## System Baseline"
    echo "- RAM: $(get_ram)"
    echo "- Temp: $(get_temp)°C"
    echo "- Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A)"
    if [[ -n "${MODEL_SIZE:-}" ]]; then
        echo "- Model disk: $(echo "scale=0; $MODEL_SIZE / 1048576" | bc)MB"
    fi
    echo "- Parameters: ${MODEL_PARAMS:-N/A}"
    echo "- Quantization: ${MODEL_QUANT:-N/A}"
    echo ""

    echo "## Benchmark Results"
    benchmark_prompt "Short (math)" "$SHORT_PROMPT"
    benchmark_prompt "Medium (default)" "$DEFAULT_PROMPT"
    benchmark_prompt "Long (technical)" "$LONG_PROMPT"

    if [[ -n "$CUSTOM_PROMPT" ]]; then
        benchmark_prompt "Custom" "$CUSTOM_PROMPT"
    fi

    echo ""
    echo "## Post-Benchmark"
    echo "- RAM: $(get_ram)"
    echo "- Temp: $(get_temp)°C"
    echo "- Ollama RSS: $(get_ollama_ram)"
} | tee "$OUTFILE"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  BENCHMARK COMPLETE — ${MODEL}"
echo "║  Results: ${OUTFILE}"
echo "╚══════════════════════════════════════════════════════╝"
