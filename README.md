# Migrating from LiteLLM to AgentGateway

A hands-on, side-by-side comparison and migration guide from [LiteLLM](https://docs.litellm.ai/) to [AgentGateway](https://agentgateway.dev/) — with working Docker configs, test scripts, and a full blog post.

## What's Inside

```
.
├── blog/                                    # Blog post (migration guide)
│   └── migrating-from-litellm-to-agentgateway.md
├── litellm/                                 # LiteLLM configuration
│   └── litellm-config.yaml                 #   Multi-provider proxy config
├── agentgateway/                            # AgentGateway configurations
│   └── configs/
│       ├── step1-basic-routing/             #   OpenAI + Anthropic on separate ports
│       ├── step2-multi-provider/            #   Unified gateway, path-based routing
│       ├── step3-mcp-federation/            #   LLM routing + federated MCP servers
│       └── step4-mcp-auth/                  #   Full setup with JWT/OAuth on MCP
├── scripts/                                 # Test and comparison scripts
│   ├── test-litellm.sh                     #   Test LiteLLM proxy
│   ├── test-agentgateway.sh                #   Test AgentGateway
│   └── compare-side-by-side.sh             #   Run same prompt through both
├── docker-compose.yaml                      # Spins up BOTH gateways
├── .env.example                             # Template for API keys
└── README.md                                # You are here
```

## Quick Start

```bash
# 1. Clone and configure
git clone https://github.com/ProfessorSeb/migrating-from-litellm-agentgateway.git
cd migrating-from-litellm-agentgateway
cp .env.example .env
# Edit .env with your OpenAI and Anthropic API keys

# 2. Start both gateways
docker compose up -d

# 3. Test
./scripts/test-litellm.sh
./scripts/test-agentgateway.sh
./scripts/compare-side-by-side.sh
```

## Services

| Service | URL | Description |
|---|---|---|
| LiteLLM Proxy | http://localhost:4000 | OpenAI-compatible LLM proxy |
| LiteLLM Admin UI | http://localhost:4000/ui | Dashboard (login with `LITELLM_MASTER_KEY`) |
| AgentGateway LLM | http://localhost:3000 | Native multi-provider LLM routing |
| AgentGateway MCP | http://localhost:3002 | Federated MCP endpoint |
| AgentGateway Admin UI | http://localhost:15000/ui | Self-service dashboard (no database) |

## Progressive Demo Steps

The AgentGateway configs are organized as a progression. Switch between them by editing the volume mount in `docker-compose.yaml`:

1. **Step 1 - Basic Routing**: OpenAI and Anthropic on separate ports
2. **Step 2 - Multi-Provider**: Both providers on a single port with path-based routing
3. **Step 3 - MCP Federation** (default): LLM routing + federated MCP servers
4. **Step 4 - MCP Auth**: JWT authentication and authorization on MCP endpoints

## Key Differences

| | LiteLLM | AgentGateway |
|---|---|---|
| Runtime | Python + Postgres | Rust (single binary) |
| Anthropic API | Native passthrough + translation | Native per-provider routing |
| MCP / A2A | LLM gateway focus | First-class MCP federation + A2A |
| Admin UI | Requires database | Zero dependencies |
| Config reload | Restart for YAML changes | Hot-reload on save |
| Client auth | Bearer token required | JWT, OAuth, or none needed |
| Provider breadth | 100+ providers | Major providers (OpenAI, Anthropic, Azure, etc.) |

## Blog Post

The full migration guide is in [`blog/migrating-from-litellm-to-agentgateway.md`](blog/migrating-from-litellm-to-agentgateway.md).

## Resources

- [AgentGateway Docs](https://agentgateway.dev/docs/)
- [AgentGateway GitHub](https://github.com/agentgateway/agentgateway)
- [LiteLLM Docs](https://docs.litellm.ai/)
- [MCP Federation Tutorial](https://agentgateway.dev/docs/local/latest/tutorials/mcp-federation/)
- [MCP Authentication](https://agentgateway.dev/docs/standalone/latest/configuration/security/mcp-authn/)
