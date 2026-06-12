# CLI Proxy

[![Go](https://img.shields.io/badge/Go-1.25-00ADD8?logo=go&logoColor=white)](https://go.dev)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?logo=docker&logoColor=white)](#docker)

[简体中文](README.md) | **English**

Lightweight AI API proxy built for **Claude Code** and **Codex CLI**. Unifies Claude (Vertex AI / OAuth) and OpenAI Codex (OAuth) behind compatible API endpoints with multi-account pooling, quota tracking, and a built-in dashboard.

## Features

- **Multi-protocol** — OpenAI `/v1/chat/completions`, `/v1/responses`, `/v1/images/generations` + Anthropic `/v1/messages` native passthrough
- **Drop-in compatible** — Works directly with Claude Code, Codex CLI, and OpenAI SDKs
- **Multi-backend routing** — Vertex AI, Claude OAuth, Codex OAuth — auto-dispatched by model name
- **Account pooling** — Round-robin load balancing with per-account quota tracking; expired tokens auto-skipped
- **Web dashboard** — Backend status, quota details, test chat, request logs, usage stats
- **Single binary** — Pure Go (including SQLite), no CGO, cross-compile and deploy
- **Docker ready** — One command to start

## Quick Start

### Docker

```bash
# 1. Configure
cp config.example.yaml config.yaml
# Edit config.yaml, set token_dir: "/data"

# 2. Start
docker compose up -d

# 3. Open dashboard
open http://localhost:9090
```

### Build from source

```bash
go build -o cli-proxy .
cp config.example.yaml config.yaml
./cli-proxy -config config.yaml
```

## Integration

### Claude Code

```bash
export ANTHROPIC_BASE_URL="https://your-domain"
export ANTHROPIC_API_KEY="sk-your-api-key"
claude
```

Requests pass through natively to Vertex AI / Claude OAuth — thinking blocks, prompt caching, and tool use all work.

### Codex CLI

Add to `~/.codex/config.toml`:

```toml
model_provider = "cli-proxy"
model = "gpt-5.5"

[model_providers.cli-proxy]
name = "CLI Proxy"
base_url = "https://your-domain/v1"
env_key = "CLI_PROXY_API_KEY"
wire_api = "responses"
```

Or use environment variables:

```bash
export OPENAI_BASE_URL="https://your-domain/v1"
export OPENAI_API_KEY="sk-your-api-key"
codex
```

### OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(base_url="https://your-domain/v1", api_key="sk-your-api-key")
resp = client.chat.completions.create(
    model="claude-sonnet-4-6",
    messages=[{"role": "user", "content": "hello"}]
)
```

### API

```bash
# Chat
curl https://your-domain/v1/chat/completions \
  -H "Authorization: Bearer sk-your-api-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4-6","messages":[{"role":"user","content":"hello"}],"stream":true}'

# Image generation
curl https://your-domain/v1/images/generations \
  -H "Authorization: Bearer sk-your-api-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-image-2","prompt":"A cat wearing sunglasses","size":"1024x1024"}'
```

## Supported Models

| Backend | Models | Auth |
|---------|--------|------|
| Vertex AI | claude-sonnet-4-6, claude-opus-4-6, claude-haiku-4-5 | GCP ADC |
| Claude OAuth | claude-sonnet-4-6-oauth, claude-opus-4-6-oauth | Browser OAuth |
| Codex OAuth | gpt-5.5, gpt-5.4, gpt-5.4-mini, gpt-image-2 | Browser OAuth |

## Configuration

```yaml
server:
  port: 9090
  api_key: "sk-your-api-key"          # Bearer token for API access
  admin_user: "admin"                  # Dashboard login
  admin_password: "password"
  cert_file: "/path/to/cert.pem"      # Optional: enable HTTPS
  key_file: "/path/to/key.pem"

vertex:
  project_id: "your-gcp-project-id"
  region: "us-east5"
  models:
    - name: "claude-sonnet-4-6"       # Name exposed to clients
      model: "claude-sonnet-4-6"      # Actual Vertex AI model ID

claude_oauth:
  enabled: true
  token_dir: "/data"                   # Token & DB storage (required for Docker)
  models:
    - "claude-sonnet-4-6-oauth"
    - "claude-opus-4-6-oauth"

codex:
  enabled: true
  models:                              # Fallback list; auto-fetched after login
    - "gpt-5.5"
    - "gpt-5.4"
```

## Dashboard

Visit `http://your-domain:9090/` and login with admin credentials.

Features:
- Backend status with connection indicators
- Per-account quota display (plan type, rate limits, reset times)
- Test chat with streaming
- Request logs with pagination
- Usage stats by model and day

### Account Management

1. Click **+ Add Account** on a backend card in the dashboard
2. Complete OAuth login in the browser
3. Tokens are saved and auto-refreshed on startup

Requests are distributed via round-robin; expired tokens are skipped automatically.

## Deployment

### Docker

```bash
docker compose up -d
```

`docker-compose.yaml` mounts `config.yaml` read-only; data (tokens, SQLite) is persisted in a Docker volume.

For Vertex AI, uncomment the GCP credentials mount in `docker-compose.yaml`:

```yaml
volumes:
  - ./gcp-credentials.json:/data/gcp-credentials.json:ro
environment:
  - GOOGLE_APPLICATION_CREDENTIALS=/data/gcp-credentials.json
```

### Binary

```bash
# Cross-compile
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o cli-proxy-linux .

# Deploy
scp cli-proxy-linux root@server:~/cli-proxy/cli-proxy
scp config.yaml root@server:~/cli-proxy/
nohup ./cli-proxy -config config.yaml > /var/log/cli-proxy.log 2>&1 &
```

## Architecture

```
Client Request
  │
  ├─ /v1/messages           → Router → Raw passthrough → Vertex AI / api.anthropic.com
  ├─ /v1/chat/completions   → Router → Executor ────────→ Backend API
  ├─ /v1/responses          → Codex passthrough ────────→ chatgpt.com
  ├─ /v1/images/generations → Codex tool call ──────────→ chatgpt.com
  └─ /v1/models             → List all registered models

Executors:
  VertexExecutor       → OpenAI ↔ Anthropic Messages API ↔ GCP Vertex AI
  ClaudeOAuthExecutor  → OpenAI ↔ Anthropic Messages API ↔ api.anthropic.com
  CodexExecutor        → OpenAI ↔ Codex Responses API    ↔ chatgpt.com
```

## Tech Stack

- **Go** + Gin
- **SQLite** — pure Go (modernc.org/sqlite)
- **uTLS** — Chrome TLS fingerprint for Claude/Codex requests
- **Docker** — multi-stage build, ~15MB image

## License

[MIT](LICENSE)
