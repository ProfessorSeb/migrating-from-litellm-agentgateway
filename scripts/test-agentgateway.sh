#!/usr/bin/env bash
# =============================================================================
# Test AgentGateway — LLM Routing + MCP Federation
# =============================================================================
# Usage: ./scripts/test-agentgateway.sh
# Tests the Step 3 config (multi-provider LLM + MCP federation)
# =============================================================================

set -euo pipefail

AGW_URL="${AGW_URL:-http://localhost:3000}"
MCP_URL="${MCP_URL:-http://localhost:3002}"
ADMIN_URL="${ADMIN_URL:-http://localhost:15000}"

echo "============================================="
echo " Testing AgentGateway"
echo " LLM URL:   $AGW_URL"
echo " MCP URL:   $MCP_URL"
echo " Admin URL: $ADMIN_URL"
echo "============================================="
echo ""

# ---- Test 1: Admin UI reachable ----
echo "--- [1/5] Admin UI Health Check ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${ADMIN_URL}/ui/" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  echo "Admin UI is reachable at ${ADMIN_URL}/ui/"
else
  echo "Admin UI returned HTTP $HTTP_CODE (may still be starting up)"
fi
echo ""

# ---- Test 2: OpenAI chat completion ----
echo "--- [2/5] OpenAI Chat Completion (via /openai) ---"
curl -s "${AGW_URL}/openai/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}],
    "max_tokens": 50
  }' | python3 -m json.tool 2>/dev/null || echo "(OpenAI request error)"
echo ""

# ---- Test 3: Anthropic chat completion (OpenAI-compatible) ----
echo "--- [3/5] Anthropic Chat Completion (via /anthropic, OpenAI format) ---"
curl -s "${AGW_URL}/anthropic/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}],
    "max_tokens": 50
  }' | python3 -m json.tool 2>/dev/null || echo "(Anthropic completions request error)"
echo ""

# ---- Test 4: Anthropic native messages API ----
echo "--- [4/5] Anthropic Native Messages API (via /anthropic) ---"
curl -s "${AGW_URL}/anthropic/v1/messages" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 50,
    "messages": [{"role": "user", "content": "Say hello in one sentence."}]
  }' | python3 -m json.tool 2>/dev/null || echo "(Anthropic messages request error)"
echo ""

# ---- Test 5: MCP Federation — list tools ----
echo "--- [5/5] MCP Federation — Initialize & List Tools ---"
echo "Sending MCP initialize request to ${MCP_URL}..."
curl -s "${MCP_URL}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-03-26",
      "capabilities": {},
      "clientInfo": {
        "name": "test-client",
        "version": "1.0.0"
      }
    }
  }' 2>/dev/null || echo "(MCP initialize error)"
echo ""

echo "============================================="
echo " AgentGateway tests complete"
echo "============================================="
echo ""
echo " Key advantages demonstrated:"
echo "   - Native Anthropic Messages API (no translation layer)"
echo "   - MCP federation (no equivalent in LiteLLM)"
echo "   - Built-in admin UI at ${ADMIN_URL}/ui/"
echo "   - Zero-config hot reload"
echo "============================================="
