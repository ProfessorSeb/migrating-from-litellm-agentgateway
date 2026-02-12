# Migrating from LiteLLM to AgentGateway: A Practical Guide

**TL;DR:** LiteLLM is a capable LLM gateway with 100+ provider support and native passthrough endpoints. AgentGateway is a next-generation agentic proxy — with native multi-provider support, A2A protocol handling, spec-compliant security, and a Rust runtime built for the agentic era. This guide walks you through a side-by-side migration with working configs.

---

## Why Migrate?

LiteLLM is a solid LLM gateway. It gives you an OpenAI-compatible API that fans out to 100+ providers, offers a native passthrough at `/anthropic/v1/messages` for zero-translation Anthropic access, and includes cost tracking, guardrails, and load balancing. As a pure LLM proxy, it does the job.

But if you're building agentic infrastructure — agents that talk to other agents via A2A, need enterprise-grade security at every layer, and want a high-performance runtime — you need more than an LLM proxy. AgentGateway was designed from day one as an **agentic data plane**, not just an LLM router.

Here's the comparison, focused on LLM gateway capabilities:

| Capability | LiteLLM | AgentGateway |
|---|---|---|
| Multi-LLM routing | Yes — 100+ providers via OpenAI format | Yes — native per-provider routing |
| OpenAI API | Via `model_list` translation | Native passthrough |
| Anthropic Messages API | Native passthrough at `/anthropic/v1/messages` | Native at `/anthropic/v1/messages` |
| Anthropic via `/v1/chat/completions` | Yes — efficient translation layer | Yes — automatic rewrite to native |
| Client authentication | Bearer token (master key / virtual keys) | JWT, OAuth, API key, or none needed |
| Backend auth injection | Via `litellm_params.api_key` | Via `policies.backendAuth.key` |
| Config format | YAML (`model_list` + `litellm_params`) | YAML (`binds` → `listeners` → `routes` → `backends`) |
| Runtime | Python + Postgres | Rust (single binary, no dependencies) |
| Config hot-reload | Restart required for YAML; DB changes are live | Automatic file watch + xDS |
| Admin UI | `/ui` (requires Postgres) | `:15000/ui` (zero dependencies) |
| Cost tracking | Built-in | Via observability (OpenTelemetry, Prometheus) |
| Load balancing | Built-in (RPM/TPM-based) | Weighted backends, health-aware (pick-2 random) |
| Guardrails / prompt guard | Built-in | Regex + webhook-based via policies |
| A2A (Agent-to-Agent) | Not supported | Native protocol support |
| Linux Foundation backed | No | Yes |

Both gateways handle LLM routing well. LiteLLM has more provider breadth (100+) and built-in cost tracking. AgentGateway has architectural advantages: Rust performance, zero-dependency deployment, protocol-native routing, and A2A as a first-class capability.

---

## What We'll Build

This guide walks through two progressive steps:

1. **Basic Routing** — Route to OpenAI and Anthropic
2. **Multiple Providers** — Unified gateway with path-based routing

By the end, you'll have both LiteLLM and AgentGateway running side by side in Docker so you can compare them directly.

---

## Prerequisites

- Docker and Docker Compose
- API keys for OpenAI and Anthropic
- 5 minutes

```bash
git clone <this-repo>
cd migrating-from-litellm-agentgateway
cp .env.example .env
# Edit .env with your real API keys
```

---

## The LiteLLM Baseline

Here's the standard LiteLLM setup as an LLM gateway:

```yaml
# litellm/litellm-config.yaml
model_list:
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY

  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY

  - model_name: claude-sonnet
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY

  - model_name: claude-haiku
    litellm_params:
      model: anthropic/claude-haiku-4-5-20251001
      api_key: os.environ/ANTHROPIC_API_KEY

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
  store_model_in_db: true
```

To run it, you need the LiteLLM container **plus** a Postgres database (required for the admin UI):

```yaml
# docker-compose.yaml (LiteLLM portion)
services:
  litellm-db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: litellm
      POSTGRES_USER: litellm
      POSTGRES_PASSWORD: litellm

  litellm:
    image: ghcr.io/berriai/litellm:main-stable
    ports:
      - "4000:4000"
    environment:
      DATABASE_URL: postgresql://litellm:litellm@litellm-db:5432/litellm
      STORE_MODEL_IN_DB: "True"
    volumes:
      - ./litellm/litellm-config.yaml:/app/config.yaml
    command: --config /app/config.yaml --port 4000
    depends_on:
      litellm-db:
        condition: service_healthy
```

### Testing LiteLLM

**OpenAI-compatible endpoint (all providers):**

```bash
# Anthropic via OpenAI-compatible translation
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-litellm-master-key-1234" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-haiku",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50
  }'
```

**Native Anthropic passthrough (zero translation):**

```bash
# Native Anthropic Messages API — no translation, full feature support
curl http://localhost:4000/anthropic/v1/messages \
  -H "Authorization: Bearer sk-litellm-master-key-1234" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-haiku-4-5-20251001",
    "max_tokens": 50,
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

The passthrough endpoint is great — zero translation, lowest possible latency, 100% feature compatibility (streaming, tool use, thinking tokens, prompt caching). Credit to LiteLLM for adding this.

But notice:
- A Bearer token is still required on every request
- A Postgres database is needed for the admin UI
- You have two different API styles: `/v1/chat/completions` (translated) and `/anthropic/v1/messages` (native)
- Clients must know which endpoint to use for which provider

---

## Step 1: Basic LLM Routing with AgentGateway

The equivalent AgentGateway config for routing to OpenAI and Anthropic:

```yaml
# agentgateway/configs/step1-basic-routing/agentgateway.yaml
binds:
  - port: 3000
    listeners:
      - routes:
          - match:
              path: /openai
            backends:
              - ai:
                  name: openai
                  provider:
                    openAI:
                      model: gpt-4o-mini
                  routes:
                    /v1/chat/completions: completions
                    /v1/models: passthrough
                    "*": passthrough
            policies:
              backendAuth:
                key: "$OPENAI_API_KEY"

  - port: 3001
    listeners:
      - routes:
          - backends:
              - ai:
                  name: anthropic
                  provider:
                    anthropic:
                      model: claude-haiku-4-5-20251001
                  routes:
                    /v1/messages: messages
                    /v1/chat/completions: completions
                    "*": passthrough
            policies:
              backendAuth:
                key: "$ANTHROPIC_API_KEY"
```

### What's Different

Both LiteLLM and AgentGateway can route to multiple providers. The architectural differences:

1. **No database required.** AgentGateway is a single Rust binary. The admin UI works out of the box at `http://localhost:15000/ui` with zero dependencies — no Postgres, no migrations.

2. **Native protocol routing.** Both `/v1/messages` (Anthropic) and `/v1/chat/completions` (OpenAI) are defined in the same route config. AgentGateway handles the protocol differences per-provider, not per-endpoint.

3. **Backend auth injection.** The `backendAuth` policy injects API keys upstream. Clients don't send any auth credentials at all — the gateway handles it. LiteLLM requires a Bearer token on every request.

4. **Environment variable references.** `$OPENAI_API_KEY` is resolved from the environment. LiteLLM uses `os.environ/OPENAI_API_KEY`.

Testing:

```bash
# No API key needed in the request — gateway injects it
curl http://localhost:3000/openai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50
  }'
```

---

## Step 2: Multiple Providers on a Single Port

Consolidate both providers to one port with path-based routing:

```yaml
# agentgateway/configs/step2-multi-provider/agentgateway.yaml
binds:
  - port: 3000
    listeners:
      - routes:
          - match:
              path: /openai
            backends:
              - ai:
                  name: openai
                  provider:
                    openAI:
                      model: gpt-4o
                  routes:
                    /v1/chat/completions: completions
                    /v1/models: passthrough
                    "*": passthrough
            policies:
              backendAuth:
                key: "$OPENAI_API_KEY"

          - match:
              path: /anthropic
            backends:
              - ai:
                  name: anthropic
                  provider:
                    anthropic:
                      model: claude-sonnet-4-5-20250929
                  routes:
                    /v1/messages: messages
                    /v1/chat/completions: completions
                    "*": passthrough
            policies:
              backendAuth:
                key: "$ANTHROPIC_API_KEY"
```

Now you have `http://localhost:3000/openai/...` and `http://localhost:3000/anthropic/...` on the same port. AgentGateway automatically rewrites the request to each provider's native endpoint and injects the right auth headers.

### LiteLLM vs AgentGateway: LLM Routing Comparison

| | LiteLLM | AgentGateway |
|---|---|---|
| **OpenAI via `/v1/chat/completions`** | `model: "gpt-4o-mini"` | `/openai/v1/chat/completions` |
| **Anthropic via OpenAI format** | `model: "claude-haiku"` | `/anthropic/v1/chat/completions` |
| **Anthropic native** | `/anthropic/v1/messages` (passthrough) | `/anthropic/v1/messages` (native route) |
| **Client auth** | Bearer token required | None needed (backend-injected) |
| **Routing model** | Model name → provider mapping | URL path → provider routing |
| **Config style** | Flat model list | Hierarchical bind → route → backend |

LiteLLM's flat `model_list` is simpler for quick setups. AgentGateway's hierarchical config gives you more control at scale — different policies, auth, rate limits per route.

---

## Running Both Side by Side

The included `docker-compose.yaml` spins up everything:

```bash
cp .env.example .env
# Edit .env with your actual API keys

docker compose up -d
```

What's running:

| Service | URL | What It Does |
|---|---|---|
| LiteLLM Proxy | `http://localhost:4000` | LLM gateway (OpenAI-compatible + native passthrough) |
| LiteLLM Admin UI | `http://localhost:4000/ui` | Dashboard (requires Postgres) |
| LiteLLM Postgres | (internal) | Required for LiteLLM admin UI |
| AgentGateway LLM | `http://localhost:3000` | LLM routing (native per-provider) |
| AgentGateway Admin UI | `http://localhost:15000/ui` | Dashboard (zero dependencies) |

Run the comparison scripts:

```bash
./scripts/test-litellm.sh
./scripts/test-agentgateway.sh
./scripts/compare-side-by-side.sh
```

### Switching AgentGateway Configs

The Docker Compose mounts the Step 2 config by default. To try the basic routing step, edit the volume mount in `docker-compose.yaml`:

```yaml
volumes:
  # Change this line to switch steps:
  - ./agentgateway/configs/step1-basic-routing/agentgateway.yaml:/cfg/agentgateway.yaml:ro
  # - ./agentgateway/configs/step2-multi-provider/agentgateway.yaml:/cfg/agentgateway.yaml:ro
```

Then `docker compose restart agentgateway`.

---

## Migration Cheat Sheet

### LLM Gateway Concepts

| LiteLLM Concept | AgentGateway Equivalent |
|---|---|
| `model_list` | `binds[].listeners[].routes[].backends[].ai` |
| `litellm_params.model` | `ai.provider.openAI.model` or `ai.provider.anthropic.model` |
| `litellm_params.api_key` | `policies.backendAuth.key` |
| `general_settings.master_key` | `policies.jwtAuth` (or no client auth needed) |
| `os.environ/VAR` | `$VAR` (resolved automatically) |
| `/v1/chat/completions` (translated) | `/openai/v1/chat/completions` or `/anthropic/v1/chat/completions` |
| `/anthropic/v1/messages` (passthrough) | `/anthropic/v1/messages` (native route) |
| Admin UI at `/ui` | Admin UI at `:15000/ui` |
| Requires Postgres | No database needed |
| `litellm --config` | `agentgateway -f` or `--file=` |

### Additional AgentGateway Capabilities

| AgentGateway Feature | What It Does |
|---|---|
| `policies.jwtAuth` | JWT authentication on any route |
| `policies.authorization.rules[]` | CEL-based authorization (inspect JWT claims, paths, headers) |
| A2A backends | Native Agent-to-Agent protocol routing |
| Hot-reload | Edit YAML, save — live immediately. No restart. |
| xDS config | Dynamic config updates without any downtime |

---

## Why AgentGateway for What Comes Next

LiteLLM is a good LLM gateway. If all you need is "route prompts to providers," it works well and has excellent provider breadth.

AgentGateway is for what comes next:

1. **Unified agentic infrastructure.** LLM routing, A2A protocol handling, tool security — one binary, one config file. No need to stitch together separate tools.

2. **Rust performance.** Single binary, ~10MB, microsecond proxy overhead. No Python runtime, no Postgres dependency. Deploy it anywhere — from a laptop to a Kubernetes cluster.

3. **Protocol-native routing.** Every provider speaks its native protocol. No translation layers, no edge-case incompatibilities. Anthropic's tool use, streaming, thinking tokens, prompt caching — all work natively through the gateway.

4. **A2A protocol support.** Agent-to-Agent communication is a first-class protocol. As multi-agent systems grow, A2A is how agents discover and coordinate with each other. AgentGateway is ready.

5. **Hot-reload everything.** Edit the YAML, save. Done. No restart, no downtime, no database migration. Also supports xDS for dynamic config updates at scale.

6. **Linux Foundation governance.** Open governance, multi-vendor backing, community-driven roadmap. Not tied to a single company.

7. **Zero-dependency admin UI.** Open `http://localhost:15000/ui` — browse LLM configs, update config live. No database, no setup, no login required.

---

## Next Steps

- Browse the [AgentGateway docs](https://agentgateway.dev/docs/)
- Read the [Multi-LLM provider routing guide](https://www.solo.io/blog/getting-started-with-multi-llm-provider-routing)
- Join the [AgentGateway GitHub](https://github.com/agentgateway/agentgateway)

---

*All configs referenced in this post are available in the [companion repository](https://github.com/ProfessorSeb/migrating-from-litellm-agentgateway). Clone it, add your API keys, and `docker compose up`.*
