# CLI Proxy

**简体中文** | [English](README_EN.md)

个人 AI API 代理服务，将 Claude（Vertex AI / OAuth）和 OpenAI Codex（OAuth）统一暴露为多种兼容 API。

## 功能特性

- **OpenAI 兼容 API** — 支持 `/v1/chat/completions`、`/v1/responses`、`/v1/images/generations`、`/v1/models`
- **Anthropic Messages API** — 支持 `/v1/messages`，原生透传至 Vertex AI / Claude OAuth，可直接接入 Claude Code
- **多后端支持** — Claude（Vertex AI）、Claude（OAuth）、Codex（OAuth）
- **多账号池** — 请求在多个账号间轮转，独立追踪每个账号的配额
- **动态模型发现** — 启动时自动从 Codex 后端拉取可用模型列表
- **管理仪表板** — 状态概览、配额展示、测试对话、请求日志、用量统计
- **持久化日志** — SQLite 存储请求记录，支持聚合查询
- **HTTPS** — 内置 TLS 支持
- **登录认证** — 仪表板使用用户名密码登录，API 调用支持 Bearer Token 和 `x-api-key`

## 支持的模型

| 后端 | 模型 | 认证方式 |
|------|------|---------|
| Vertex AI | claude-sonnet-4-6, claude-opus-4-6, claude-haiku-4-5 | GCP 应用默认凭证 |
| Claude OAuth | claude-sonnet-4-6, claude-opus-4-6 | 浏览器 OAuth 登录 |
| Codex OAuth | gpt-5.5, gpt-5.4, gpt-5.4-mini, gpt-image-2 | 浏览器 OAuth 登录 |

## 快速开始

```bash
# 编译
go build -o cli-proxy .

# 配置
cp config.example.yaml config.yaml
# 编辑 config.yaml

# 启动
./cli-proxy -config config.yaml
```

## 配置说明

```yaml
server:
  port: 443
  api_key: "sk-your-api-key"          # API 调用的 Bearer Token
  cert_file: "/path/to/cert.pem"      # 可选：启用 HTTPS
  key_file: "/path/to/key.pem"
  admin_user: "admin"                  # 仪表板登录用户名
  admin_password: "password"           # 仪表板登录密码

vertex:
  project_id: "your-gcp-project-id"
  region: "us-east5"
  models:
    - name: "claude-sonnet-4-6"        # 客户端请求的模型名
      model: "claude-sonnet-4-6"       # Vertex AI 实际模型名
    - name: "claude-opus-4-6"
      model: "claude-opus-4-6"

claude_oauth:
  enabled: true
  models:
    - "claude-sonnet-4-6-oauth"
    - "claude-opus-4-6-oauth"

codex:
  enabled: true
  models:                              # 回退列表；登录后自动从后端拉取
    - "gpt-5.5"
    - "gpt-5.4"
    - "gpt-5.4-mini"
```

## API 使用

### 对话

```bash
curl https://your-domain/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-your-api-key" \
  -d '{"model":"claude-sonnet-4-6","messages":[{"role":"user","content":"你好"}]}'
```

### 流式输出

```bash
curl https://your-domain/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-your-api-key" \
  -d '{"model":"gpt-5.5","messages":[{"role":"user","content":"你好"}],"stream":true}'
```

### 图片生成

```bash
curl https://your-domain/v1/images/generations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-your-api-key" \
  -d '{"model":"gpt-image-2","prompt":"一只戴墨镜的猫","size":"1024x1024"}'
```

### 接入 Claude Code

```bash
export ANTHROPIC_BASE_URL="https://your-domain"
export ANTHROPIC_API_KEY="sk-your-api-key"
claude
```

请求直接透传至 Vertex AI / Claude OAuth 后端，thinking blocks、prompt caching、tool use 等 Claude Code 特性完整保留。

### 接入 Codex CLI

在 `~/.codex/config.toml` 中配置：

```toml
model_provider = "cli-proxy"
model = "gpt-5.5"

[model_providers.cli-proxy]
name = "CLI Proxy"
base_url = "https://your-domain/v1"
env_key = "CLI_PROXY_API_KEY"
wire_api = "responses"
supports_websockets = false
```

或直接使用环境变量：

```bash
export OPENAI_BASE_URL="https://your-domain/v1"
export OPENAI_API_KEY="sk-your-api-key"
codex
```

### Python SDK

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://your-domain/v1",
    api_key="sk-your-api-key"
)

resp = client.chat.completions.create(
    model="claude-sonnet-4-6",
    messages=[{"role": "user", "content": "你好"}]
)
print(resp.choices[0].message.content)
```

## 管理仪表板

访问 `https://your-domain/` 并使用管理员账号登录。

功能：
- 各后端状态指示（已连接 / 未认证 / 已过期）
- 每个账号独立的配额展示（套餐类型、5 小时限额、周限额、重置时间）
- 按后端分组的模型选择器
- 测试对话（支持流式输出）
- 请求日志（分页浏览）
- 用量统计（按模型 / 按天聚合）

## 账号管理

### 添加账号

1. 在仪表板点击对应后端卡片的 `+ Add Account`
2. 在浏览器中完成 OAuth 授权
3. Token 自动保存到 `~/.cli-proxy/` 并在启动时自动刷新

### 多账号轮转

请求通过 round-robin 在多个账号间分配。过期的 token 自动跳过。启动时自动刷新所有 token。

## 部署

### 交叉编译 Linux 版本

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o cli-proxy-linux .
```

纯 Go 实现的 SQLite，无 CGO 依赖，直接交叉编译。

### 服务器部署

```bash
# 上传文件
scp cli-proxy-linux root@server:~/cli-proxy/cli-proxy
scp config.yaml root@server:~/cli-proxy/
scp ~/.cli-proxy/*.json root@server:~/.cli-proxy/

# 启动
ssh root@server
cd ~/cli-proxy && nohup ./cli-proxy -config config.yaml > /var/log/cli-proxy.log 2>&1 &
```

### 服务器使用 Vertex AI

上传 GCP 凭证：
```bash
scp ~/.config/gcloud/application_default_credentials.json root@server:~/.config/gcloud/
```

## 架构

```
客户端请求
  │
  ├─ /v1/messages          ─→ Router ─→ 原生透传 ─→ Vertex AI / api.anthropic.com
  ├─ /v1/chat/completions  ─→ Router ─→ Executor ─→ 后端 API
  ├─ /v1/responses         ─→ Codex 直通 ─────────→ chatgpt.com
  ├─ /v1/images/generations ─→ Codex Tool Call ────→ chatgpt.com
  └─ /v1/models            ─→ 返回所有已注册模型

Executor（执行器）：
  VertexExecutor      → OpenAI 格式 ↔ Anthropic Messages API ↔ GCP Vertex AI
  ClaudeOAuthExecutor → OpenAI 格式 ↔ Anthropic Messages API ↔ api.anthropic.com
  CodexExecutor       → OpenAI 格式 ↔ Codex Responses API   ↔ chatgpt.com

Anthropic 透传（/v1/messages）：
  VertexExecutor      → 请求体原样转发（移除 model 字段）    → GCP Vertex AI
  ClaudeOAuthExecutor → 请求体原样转发                      → api.anthropic.com
```

## 技术栈

- Go + Gin
- SQLite（纯 Go 实现，modernc.org/sqlite）
- uTLS（Chrome TLS 指纹，用于 Claude/Codex 请求）
- 单二进制文件，零外部依赖

## 许可证

MIT
