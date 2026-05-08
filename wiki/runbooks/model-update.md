# Runbook: AI Model Update

## Purpose

Safely update or swap Ollama models on a Debian 13 host, ensuring stability, performance benchmarks, and rollback capability.

## When to Use

- New model version available with improvements
- Switching to a different model (e.g., gemma3:1b → phi4-mini)
- Quantization experiments (Q4_K_M → Q5_K_M)
- Evaluating larger families such as `gemma4`, but only after benchmark and rollback planning

## Prerequisites

- Ollama service running and healthy
- Sufficient disk space (check: `df -h /srv/ollama/models /mnt/data`)
- No active inference requests

## Procedure

### Step 1 — Pre-Update Checks

```bash
# Current model inventory
ollama list

# Current disk usage
du -sh /srv/ollama/models/

# Available disk space
df -h /

# Verify service health
curl -s http://localhost:11434/api/tags | jq '.models[].name'

# Verify the current OpenClaw baseline session model
grep -n '"model": "' /srv/openclaw/.openclaw/agents/main/sessions/sessions.json | head -4
```

### Step 2 — Benchmark Current Model (Baseline)

```bash
# Capture current performance for comparison
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BENCH_DIR="/home/<SSH_USER>/<PROJECT_ROOT>/logs/model-bench-${TIMESTAMP}"
mkdir -p "$BENCH_DIR"

# Latency test
time curl -s http://localhost:11434/api/generate -d '{
  "model": "CURRENT_MODEL",
  "prompt": "Explain HTTPS in one sentence.",
  "stream": false
}' | jq '.total_duration' > "$BENCH_DIR/before-latency.txt"

# RAM usage
free -m > "$BENCH_DIR/before-ram.txt"

# Temperature
cat /sys/class/thermal/thermal_zone0/temp > "$BENCH_DIR/before-temp.txt"
```

### Step 3 — Pull New Model

```bash
# Pull with progress tracking
ollama pull NEW_MODEL_NAME 2>&1 | tee "$BENCH_DIR/pull-log.txt"
```

### Step 4 — Test New Model

```bash
# Quick validation
curl -s http://localhost:11434/api/generate -d '{
  "model": "NEW_MODEL_NAME",
  "prompt": "Say hello. Respond in exactly one sentence.",
  "stream": false
}' | jq '.response'
```

If a previously healthy model suddenly times out instead of answering:

```bash
# Confirm it is not only the HTTP path
ollama run CURRENT_MODEL "Reply OK."

# If the process hangs, test direct blob readability before changing OpenClaw config
sudo dd if=/srv/ollama/models/blobs/<MODEL_BLOB_SHA256> of=/dev/null bs=1M skip=8 count=4 status=none
sudo dd if=/srv/ollama/models/blobs/<MODEL_BLOB_SHA256> of=/dev/null bs=1M skip=12 count=4 status=none
```

- If low-offset reads succeed but later reads hang, treat it as model-store corruption on the backing blob path.
- Recovery order: remove the broken model artifact, `ollama pull` the same model again, warm it locally, then return OpenClaw traffic.

### Step 5 — Benchmark New Model

```bash
# Same benchmark as Step 2
time curl -s http://localhost:11434/api/generate -d '{
  "model": "NEW_MODEL_NAME",
  "prompt": "Explain HTTPS in one sentence.",
  "stream": false
}' | jq '.total_duration' > "$BENCH_DIR/after-latency.txt"

free -m > "$BENCH_DIR/after-ram.txt"
cat /sys/class/thermal/thermal_zone0/temp > "$BENCH_DIR/after-temp.txt"
```

### Step 6 — Compare and Decide

```bash
echo "=== Before ==="
cat "$BENCH_DIR/before-latency.txt"
cat "$BENCH_DIR/before-ram.txt" | head -3
echo "=== After ==="
cat "$BENCH_DIR/after-latency.txt"
cat "$BENCH_DIR/after-ram.txt" | head -3
```

Decision criteria:
- Latency increase > 50% → **reject**
- RAM usage > 12GB → **reject**
- Temperature > 75°C sustained → **reject**
- Cold-start response > 45s for the OpenClaw baseline path → **reject**
- Any model intended for the default OpenClaw session must pass two consecutive non-streamed `generate` calls without timeout

## Template Baseline Policy

- OpenClaw conversational traffic is API-first: `google/gemini-2.5-flash` primary with `openai/gpt-4o-mini` fallback
- `ollama/phi4-mini` is the only intentional local/offline OpenClaw chat model in the active template
- Benchmark-only local models must not remain registered in OpenClaw after evaluation ends; retire them from the template first, then prune their Ollama blobs if they are no longer needed
- Any local replacement for `phi4-mini` must pass the full benchmark + rollback cycle before becoming the active local agent model
- If a previously healthy local model suddenly stalls, treat storage corruption as a first-class hypothesis before changing the OpenClaw routing or baseline policy

### Step 7 — Finalize

If **accepted**:
```bash
# Remove old model to free space
ollama rm OLD_MODEL_NAME
echo "$(date -Iseconds) | Model updated: OLD → NEW" >> /home/<SSH_USER>/<PROJECT_ROOT>/logs/model-updates.log
```

If **rejected**:
```bash
# Remove new model, keep old
ollama rm NEW_MODEL_NAME
echo "$(date -Iseconds) | Model update rejected: NEW (reason: ...)" >> /home/<SSH_USER>/<PROJECT_ROOT>/logs/model-updates.log
```
