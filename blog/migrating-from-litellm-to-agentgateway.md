# Migrating from LiteLLM to AgentGateway: A Practical Guide

**TL;DR:** LiteLLM got you started with multi-provider LLM routing. AgentGateway takes you further with native protocol support, MCP federation, built-in security, and a Rust-powered runtime that's purpose-built for the agentic AI era. This guide walks you through a step-by-step migration with working configs you can run today.

---

## Why Migrate?

LiteLLM is a solid tool for what it was designed to do: give you an OpenAI-compatible API that fans out to multiple LLM providers. If all you need is "send prompt, get response" across providers, it works.

But the AI landscape has moved on. We're building **agents** now — systems that call tools, talk to other agents, and need real security at every layer. That's where LiteLLM starts to show its limits and AgentGateway was purpose-built to handle what comes next.

Here's the honest comparison:

| Capability | LiteLLM | AgentGateway |
|---|---|---|
| Multi-LLM routing | Yes (OpenAI format only) | Yes (native per-provider) |
| Anthropic Messages API | Translated to OpenAI | Native `/v1/messages` support |
| MCP support | None | First-class: federation, auth, RBAC |
| A2A (Agent-to-Agent) | None | Native protocol support |
| Runtime | Python | Rust (lower latency, lower memory) |
| Config hot-reload | Restart required | Automatic (file watch + xDS) |
| Admin UI | `/ui` (requires Postgres) | `/ui` on `:15000` (zero dependencies) |
| Authentication | API key on proxy | JWT, OAuth, MCP Auth spec, RBAC |
| Linux Foundation backed | No | Yes |
| Protocol translation overhead | Yes (everything → OpenAI → provider) | No (native routing per provider) |

The bottom line: LiteLLM is a **translation proxy**. AgentGateway is an **agentic infrastructure layer**.

---

## What We'll Build

This guide walks through four progressive steps, each with working configs you can run with `docker compose`:

1. **Basic Routing** — Route to OpenAI and Anthropic
2. **Multiple Providers** — Unified gateway with path-based routing
3. **MCP Federation** — Aggregate multiple MCP servers behind one endpoint
4. **MCP Authentication** — Secure MCP endpoints with JWT/OAuth

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

Here's the standard LiteLLM setup. If you're migrating, this probably looks familiar:

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

Testing it:

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-litellm-master-key-1234" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50
  }'
```

Notice you need:
- A Bearer token on every request
- A Postgres database just to get the admin UI
- Everything goes through the OpenAI format, even Anthropic calls

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

Key differences from LiteLLM you'll notice immediately:

1. **No database required.** AgentGateway is a single binary. The admin UI works out of the box at `http://localhost:15000/ui`.
2. **Native Anthropic support.** The `/v1/messages` route uses Anthropic's native format — no translation layer. Claude Code works natively.
3. **Auth is injected by the gateway.** Your clients don't need to send API keys. The `backendAuth` policy handles it.
4. **Environment variable references.** `$OPENAI_API_KEY` is resolved from the environment automatically.

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

Consolidate everything to one port with path-based routing:

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

Now you have `http://localhost:3000/openai/...` and `http://localhost:3000/anthropic/...` on the same port, same gateway process. AgentGateway automatically rewrites the request to each provider's native endpoint.

The LiteLLM equivalent requires you to remember model names (`gpt-4o-mini`, `claude-haiku`) and sends everything through the same `/v1/chat/completions` path. AgentGateway gives you explicit routing so your infrastructure is self-documenting.

---

## Step 3: MCP Federation (Where LiteLLM Can't Follow)

This is the step where we leave LiteLLM behind entirely. **LiteLLM has no MCP support.**

AgentGateway can federate multiple MCP servers behind a single endpoint. Your AI agents connect to one URL and get tools from every backend server, automatically namespaced:

```yaml
# Add to the same config alongside LLM routing
  - port: 3002
    listeners:
      - routes:
          - policies:
              cors:
                allowOrigins: ["*"]
                allowHeaders: [mcp-protocol-version, content-type, cache-control]
                exposeHeaders: ["Mcp-Session-Id"]
            backends:
              - mcp:
                  targets:
                    - name: filesystem
                      stdio:
                        cmd: npx
                        args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]

                    - name: memory
                      stdio:
                        cmd: npx
                        args: ["-y", "@modelcontextprotocol/server-memory"]
```

What this gives you:

- **One endpoint** (`http://localhost:3002`) exposes tools from both the filesystem and memory MCP servers
- **Automatic namespacing**: tools are prefixed with their server name (`filesystem_read_file`, `memory_create_entities`)
- **Transport flexibility**: stdio, HTTP/SSE, and Streamable HTTP backends
- **The admin UI** at `http://localhost:15000/ui` lets you browse all federated tools, test them interactively, and update config without restarts

To add another MCP server (say, GitHub), just append a target:

```yaml
                    - name: github
                      stdio:
                        cmd: npx
                        args: ["-y", "@modelcontextprotocol/server-github"]
                      env:
                        GITHUB_PERSONAL_ACCESS_TOKEN: "${GITHUB_TOKEN}"
```

Save the file. AgentGateway hot-reloads. No restart needed.

---

## Step 4: MCP Authentication (Enterprise Security)

AgentGateway implements the [MCP Authorization spec](https://spec.modelcontextprotocol.io/) natively. You can protect your MCP tools with JWT authentication and CEL-based authorization rules — no auth code in your MCP servers.

```yaml
  - port: 3002
    listeners:
      - routes:
          - policies:
              cors:
                allowOrigins: ["*"]
                allowHeaders: [mcp-protocol-version, content-type, cache-control, authorization]
                exposeHeaders: ["Mcp-Session-Id"]
              jwtAuth:
                mode: strict
                issuer: https://your-oauth-provider.com
                audiences: [agentgateway-mcp]
                jwks:
                  url: https://your-oauth-provider.com/.well-known/jwks.json
              authorization:
                rules:
                  - allow: 'jwt.scope.contains("mcp:read")'
            backends:
              - mcp:
                  targets:
                    - name: filesystem
                      stdio:
                        cmd: npx
                        args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
                    - name: memory
                      stdio:
                        cmd: npx
                        args: ["-y", "@modelcontextprotocol/server-memory"]
```

For full OAuth compliance (Keycloak, Auth0), AgentGateway also supports `mcpAuthentication` which implements the server side of the MCP Authorization spec via config:

```yaml
mcpAuthentication:
  issuer: http://localhost:7080/realms/mcp
  jwks:
    url: http://localhost:7080/protocol/openid-connect/certs
  provider:
    keycloak: {}
  resourceMetadata:
    resource: http://localhost:3002/mcp
    scopesSupported: [mcp:read, mcp:write]
    bearerMethodsSupported: [header, body, query]
```

In LiteLLM, you'd need to build all of this yourself. In AgentGateway, it's YAML.

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
| LiteLLM Proxy | `http://localhost:4000` | LLM routing (OpenAI format) |
| LiteLLM Admin UI | `http://localhost:4000/ui` | Dashboard (requires Postgres) |
| LiteLLM Postgres | (internal) | Required for LiteLLM UI |
| AgentGateway | `http://localhost:3000` | LLM routing (native per-provider) |
| AgentGateway MCP | `http://localhost:3002` | Federated MCP endpoint |
| AgentGateway Admin UI | `http://localhost:15000/ui` | Dashboard (zero dependencies) |

Run the comparison scripts:

```bash
./scripts/test-litellm.sh
./scripts/test-agentgateway.sh
./scripts/compare-side-by-side.sh
```

### Switching AgentGateway Configs

The Docker Compose mounts the Step 3 config by default. To try a different step, edit the volume mount in `docker-compose.yaml`:

```yaml
volumes:
  # Change this line to try different steps:
  - ./agentgateway/configs/step1-basic-routing/agentgateway.yaml:/cfg/agentgateway.yaml:ro
  # - ./agentgateway/configs/step2-multi-provider/agentgateway.yaml:/cfg/agentgateway.yaml:ro
  # - ./agentgateway/configs/step3-mcp-federation/agentgateway.yaml:/cfg/agentgateway.yaml:ro
  # - ./agentgateway/configs/step4-mcp-auth/agentgateway.yaml:/cfg/agentgateway.yaml:ro
```

Then `docker compose restart agentgateway`.

---

## Migration Cheat Sheet

| LiteLLM Concept | AgentGateway Equivalent |
|---|---|
| `model_list` | `binds[].listeners[].routes[].backends[].ai` |
| `litellm_params.model` | `ai.provider.openAI.model` or `ai.provider.anthropic.model` |
| `litellm_params.api_key` | `policies.backendAuth.key` |
| `general_settings.master_key` | `policies.jwtAuth` (or no client auth needed) |
| `os.environ/VAR` | `$VAR` (resolved automatically) |
| Admin UI at `/ui` | Admin UI at `:15000/ui` |
| Requires Postgres | No database needed |
| `litellm --config` | `agentgateway -f` or `--file=` |
| No MCP support | `backends[].mcp.targets[]` |
| No A2A support | Native A2A protocol support |

---

## Why AgentGateway Wins for the Agentic Era

1. **Built for agents, not just prompts.** MCP federation, A2A, tool security — these aren't bolted on, they're the foundation.

2. **Native protocol support.** Anthropic's Messages API works natively. No translation layers means lower latency and full feature compatibility (streaming, tool use, etc.).

3. **Rust performance.** Single binary, ~10MB, microsecond proxy overhead. LiteLLM is Python with Postgres — a different weight class.

4. **Zero-dependency admin UI.** No database to manage. Open `http://localhost:15000/ui` and you're in.

5. **Hot-reload config.** Edit the YAML, save. Done. No `docker compose restart`, no downtime.

6. **Linux Foundation governance.** Open governance, multi-vendor backing. Not tied to a single company's roadmap.

7. **Security-first.** JWT, OAuth, MCP Auth spec, CEL-based authorization, RBAC, TLS — all built in. LiteLLM gives you an API key.

---

## Next Steps

- Browse the [AgentGateway docs](https://agentgateway.dev/docs/)
- Try the [MCP federation tutorial](https://agentgateway.dev/docs/local/latest/tutorials/mcp-federation/)
- Explore [MCP authentication](https://agentgateway.dev/docs/standalone/latest/configuration/security/mcp-authn/)
- Join the [AgentGateway GitHub](https://github.com/agentgateway/agentgateway)

---

*All configs referenced in this post are available in the [companion repository](https://github.com/ProfessorSeb/migrating-from-litellm-agentgateway). Clone it, add your API keys, and `docker compose up`.*
