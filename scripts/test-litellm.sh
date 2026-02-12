#!/usr/bin/env bash
# =============================================================================
# Test LiteLLM Proxy — OpenAI + Anthropic routing
# =============================================================================
# Usage: ./scripts/test-litellm.sh
# Requires: LITELLM_MASTER_KEY set in .env (default: sk-litellm-master-key-1234)
# =============================================================================

set -euo pipefail

LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
LITELLM_KEY="${LITELLM_MASTER_KEY:-sk-litellm-master-key-1234}"

echo "============================================="
echo " Testing LiteLLM Proxy"
echo " URL: $LITELLM_URL"
echo "============================================="
echo ""

# ---- Test 1: Health check ----
echo "--- [1/4] Health Check ---"
curl -s "${LITELLM_URL}/health" | python3 -m json.tool 2>/dev/null || echo "(health endpoint returned non-JSON)"
echo ""

# ---- Test 2: List models ----
echo "--- [2/4] List Models ---"
curl -s "${LITELLM_URL}/v1/models" \
  -H "Authorization: Bearer ${LITELLM_KEY}" | python3 -m json.tool 2>/dev/null || echo "(models endpoint error)"
echo ""

# ---- Test 3: Chat completion via OpenAI model ----
echo "--- [3/4] OpenAI Chat Completion (gpt-4o-mini) ---"
curl -s "${LITELLM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_KEY}" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}],
    "max_tokens": 50
  }' | python3 -m json.tool 2>/dev/null || echo "(OpenAI request error)"
echo ""

# ---- Test 4: Chat completion via Anthropic model ----
echo "--- [4/4] Anthropic Chat Completion (claude-haiku) ---"
curl -s "${LITELLM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_KEY}" \
  -d '{
    "model": "claude-haiku",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}],
    "max_tokens": 50
  }' | python3 -m json.tool 2>/dev/null || echo "(Anthropic request error)"
echo ""

echo "============================================="
echo " LiteLLM tests complete"
echo "============================================="
