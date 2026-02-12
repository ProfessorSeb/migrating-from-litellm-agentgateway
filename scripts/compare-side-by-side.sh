#!/usr/bin/env bash
# =============================================================================
# Side-by-Side Comparison: LiteLLM vs AgentGateway
# =============================================================================
# Runs the same prompt through both gateways and compares response times.
# Usage: ./scripts/compare-side-by-side.sh
# =============================================================================

set -euo pipefail

LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
LITELLM_KEY="${LITELLM_MASTER_KEY:-sk-litellm-master-key-1234}"
AGW_URL="${AGW_URL:-http://localhost:3000}"

PROMPT="Explain what an API gateway is in exactly one sentence."

echo "============================================="
echo " Side-by-Side: LiteLLM vs AgentGateway"
echo "============================================="
echo ""
echo "Prompt: \"$PROMPT\""
echo ""

# ---- LiteLLM → OpenAI ----
echo "--- LiteLLM → OpenAI (gpt-4o-mini) ---"
time curl -s "${LITELLM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_KEY}" \
  -d "{
    \"model\": \"gpt-4o-mini\",
    \"messages\": [{\"role\": \"user\", \"content\": \"${PROMPT}\"}],
    \"max_tokens\": 100
  }" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('choices',[{}])[0].get('message',{}).get('content','(no content)'))" 2>/dev/null || echo "(error)"
echo ""

# ---- AgentGateway → OpenAI ----
echo "--- AgentGateway → OpenAI (gpt-4o) ---"
time curl -s "${AGW_URL}/openai/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"gpt-4o\",
    \"messages\": [{\"role\": \"user\", \"content\": \"${PROMPT}\"}],
    \"max_tokens\": 100
  }" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('choices',[{}])[0].get('message',{}).get('content','(no content)'))" 2>/dev/null || echo "(error)"
echo ""

# ---- LiteLLM → Anthropic ----
echo "--- LiteLLM → Anthropic (claude-haiku) ---"
time curl -s "${LITELLM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_KEY}" \
  -d "{
    \"model\": \"claude-haiku\",
    \"messages\": [{\"role\": \"user\", \"content\": \"${PROMPT}\"}],
    \"max_tokens\": 100
  }" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('choices',[{}])[0].get('message',{}).get('content','(no content)'))" 2>/dev/null || echo "(error)"
echo ""

# ---- AgentGateway → Anthropic ----
echo "--- AgentGateway → Anthropic (claude-sonnet) ---"
time curl -s "${AGW_URL}/anthropic/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"claude-sonnet-4-5-20250929\",
    \"messages\": [{\"role\": \"user\", \"content\": \"${PROMPT}\"}],
    \"max_tokens\": 100
  }" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('choices',[{}])[0].get('message',{}).get('content','(no content)'))" 2>/dev/null || echo "(error)"
echo ""

echo "============================================="
echo " Comparison complete"
echo ""
echo " Things to notice:"
echo "   1. AgentGateway: no API key needed in request (injected by gateway)"
echo "   2. AgentGateway: written in Rust — lower proxy overhead"
echo "   3. LiteLLM: requires Bearer token on every request"
echo "   4. LiteLLM: Python-based — higher memory footprint"
echo "============================================="
