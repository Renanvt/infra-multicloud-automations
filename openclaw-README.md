
## Método 2: Docker Swarm com Traefik (Recomendado para Produção)

Este método usa Docker Swarm para orquestração e Traefik para SSL automático e roteamento.

### Pré-requisitos para o Método Docker

Certifique-se de ter:

| Requisito | Versão Mínima |
|-------------|-----------------|
| Docker Engine | 24.x |
| Docker Compose / Swarm | v2.x |
| Traefik (reverse proxy) | v2.x ou v3.x |
| Portainer (opcional) | Mais recente |

**Antes de começar:**

```bash
# Initialize Docker Swarm (if not already done)
docker swarm init

# Create external network
docker network create --driver overlay --attachable network_swarm_public

# Verify Traefik is running
docker service ls | grep traefik
```

### Passo 1: Preparar Diretório de Dados

```bash
# Create directory for OpenClaw data
mkdir -p /opt/infra/alobexpress/openclaw

# Set correct permissions (uid 1000 = node user in container)
chown -R 1000:1000 /opt/infra/alobexpress/openclaw
```

**Por que uid 1000?** A imagem Docker oficial do OpenClaw executa como usuário `node` (uid 1000). Sem as permissões corretas, o contêiner não pode escrever arquivos de configuração.

### Passo 2: Criar docker-compose.yml

Crie `/opt/infra/alobexpress/openclaw/docker-compose.yml`:
Está na pasta infra/21.openclaw.yaml

**Important Configuration Notes:**

| Setting | Value | Why |
|---------|-------|-----|
| `image` | `ghcr.io/openclaw/openclaw:2026.5.7` | Official pre-built image (don't use `node:22-bookworm`) |
| `OPENCLAW_GATEWAY_BIND` | `lan` | Allows Traefik to connect |
| `OPENCLAW_DISABLE_BONJOUR` | `1` | Disables mDNS (not needed in containers) |
| `volumes` | `/opt/infra/alobexpress/openclaw` | Persistent data storage |
| `tmpfs` | `/tmp:size=1g` | Temporary files in memory |
| `healthcheck` | `/healthz` endpoint | Docker monitors service health |

### Step 3: Configure Environment Variables

**Option B: Using .env File**

Create `/opt/infra/alobexpress/.env`:

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENCLAW_GATEWAY_TOKEN` | Yes | Gateway authentication token |
| `OPENCLAW_HOOKS_TOKEN` | Yes | Webhook authentication token |
| `OPENAI_API_KEY` | Yes | OpenAI API key |
| `TELEGRAM_DEFAULT_BOT_TOKEN` | If using Telegram | Main bot token |
| `NOTION_API_KEY` | Optional | Notion integration |
| `FIRECRAWL_API_KEY` | Optional | Web scraping |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | Optional | GitHub integration |

```bash
OPENCLAW_GATEWAY_TOKEN=your-secure-token-here
OPENCLAW_HOOKS_TOKEN=your-hooks-token-here
OPENAI_API_KEY=sk-...
TELEGRAM_DEFAULT_BOT_TOKEN=123456:ABC...


### Step 4: Deploy the Stack


**Via CLI:**

```bash
cd /opt/infra/alobexpress/openclaw
docker stack deploy -c docker-compose.yml openclaw



### Step 5: Verify Deployment

```bash
# Check service status
docker service ls | grep openclaw

# View logs
docker service logs -f openclaw_openclaw_gateway

# Check container health
docker ps --filter name=openclaw
```

**Healthy logs should show:**

```text
[gateway] ready
[heartbeat] started
[http] server listening on 0.0.0.0:18789
```

### Step 6: Configure OpenClaw CLI Alias

The `openclaw` CLI only exists inside the container. Create an alias for easy access:

```bash
# Add to ~/.bashrc
echo 'alias openclaw="docker exec -it \$(docker ps --filter name=openclaw -q) node dist/index.js"' >> ~/.bashrc

# Reload shell
source ~/.bashrc

# Test
openclaw --version
```

### Step 7: Configure CORS and Trusted Proxies

Allow dashboard access from your domain:

```bash
# Get Traefik internal IP from logs
docker service logs openclaw_openclaw_gateway | grep "peer="
# Example output: peer=10.0.1.3:54321

# Configure allowed origins and trusted proxies
openclaw config set \
  --batch-json '[
    {"path":"gateway.controlUi.allowedOrigins","value":["http://localhost:18789","http://127.0.0.1:18789","https://openclaw.seudominio.com.br"]},
    {"path":"gateway.trustedProxies","value":["10.0.1.3"]}
  ]'
```

**Replace `10.0.1.3` with your actual Traefik IP.**

### Step 8: Configure Gateway Mode and API Keys

```bash
# Set gateway mode
openclaw config set gateway.mode local

# Configure OpenAI API key (if not using env var)
openclaw config set agents.main.auth.openai.apiKey sk-...

# Set command owner (your Telegram ID)
openclaw config set commands.ownerAllowFrom '["telegram:123456789"]'
```

### Step 9: Clean Up Inapplicable Skills

Remove skills that require binaries not available in containers:

```bash
openclaw doctor --fix
```

### Step 10: First Dashboard Access

1. Navigate to `https://openclaw.seudominio.com.br`
2. Confirm WebSocket URL: `wss://openclaw.seudominio.com.br`
3. Enter gateway token:

```bash
# View token
docker exec -it $(docker ps --filter name=openclaw -q) printenv OPENCLAW_GATEWAY_TOKEN

# Or from config
openclaw config get gateway.auth.token
```

4. Click **Connect**
5. If device pairing is required:

```bash
# Approve device
openclaw devices approve YOUR_REQUEST_ID
```

### Docker-Specific Commands

```bash
# View logs
docker service logs -f openclaw_openclaw_gateway

# Enter container shell
docker exec -it $(docker ps --filter name=openclaw -q) bash

# Force redeploy (after config changes)
docker service update --force openclaw_openclaw_gateway

# Scale service
docker service scale openclaw_openclaw_gateway=2

# View service details
docker service inspect openclaw_openclaw_gateway

# Remove stack
docker stack rm openclaw
```

### Docker File Structure

```text
/opt/infra/alobexpress/openclaw/
├── openclaw.json              # Main config (auto-managed)
├── openclaw.json.bak          # Backup before each change
├── openclaw.json.last-good    # Last known good config
├── agents/
│   └── main/
│       └── agent/
│           └── auth-profiles.json
├── canvas/
├── credentials/               # OAuth tokens
└── logs/
    └── stability/
```

### Docker Troubleshooting

#### ❌ `bash: openclaw: command not found` (exit 127)

**Cause:** Using wrong base image or missing CLI alias.

**Solution:**
```bash
# Ensure using official image
image: ghcr.io/openclaw/openclaw:2026.5.7

# Create alias
echo 'alias openclaw="docker exec -it \$(docker ps --filter name=openclaw -q) node dist/index.js"' >> ~/.bashrc
source ~/.bashrc
```

#### ❌ `Proxy headers detected from untrusted address`

**Cause:** Traefik IP not in trusted proxies list.

**Solution:**
```bash
# Find Traefik IP in logs
docker service logs openclaw_openclaw_gateway | grep "peer="

# Add to trusted proxies
openclaw config set --batch-json '[{"path":"gateway.trustedProxies","value":["TRAEFIK_IP"]}]'
```

#### ❌ `JSON5: invalid character` — gateway won't start

**Cause:** Manual edit introduced invalid JSON (typographic quotes).

**Solution:**
```bash
# Restore backup
cp /opt/infra/alobexpress/openclaw/openclaw.json.last-good \
   /opt/infra/alobexpress/openclaw/openclaw.json

# Or run doctor
openclaw doctor --fix

# Restart service
docker service update --force openclaw_openclaw_gateway
```

**Never edit `openclaw.json` manually. Always use `openclaw config set`.**

#### ❌ `404 Not Found` at domain

**Cause:** Volume path mismatch or permission issues.

**Solution:**
```bash
# Verify path exists
ls -la /opt/infra/alobexpress/openclaw

# Fix permissions
chown -R 1000:1000 /opt/infra/alobexpress/openclaw

# Restart service
docker service update --force openclaw_openclaw_gateway
```

#### ❌ `gateway.mode is unset`

**Cause:** Gateway mode not configured.

**Solution:**
```bash
openclaw config set gateway.mode local
docker service update --force openclaw_openclaw_gateway
```

---

## 7. Testes e Validação

### Ver se OpenClaw está rodando

```bash
pm2 status
```

### Ver logs

```bash
pm2 logs openclaw-gateway
```

### Ver se a porta local está aberta

```bash
ss -lntp | grep 18789
```

Deve aparecer algo escutando em `127.0.0.1:18789`.

### Testar Caddy

```bash
sudo systemctl status caddy
```

### Testar URL pública

Abra:

```text
https://openclaw.alobexpress.com.br
```

---

## 🔧 Troubleshooting

Esta seção cobre problemas comuns para ambos os métodos de implantação.

### Problemas Comuns (Ambos os Métodos)

#### ❌ `origin not allowed` no WebSocket

**Causa:** Gateway bloqueia conexões de origens desconhecidas.

**Solução para PM2:**
```bash
nano ~/.openclaw/openclaw.json
```

Adicione em `gateway.controlUi`:
```json
"allowedOrigins": ["https://openclaw.seudominio.com.br"]
```

Reinicie:
```bash
pm2 restart openclaw-gateway
```

**Solução para Docker:**
```bash
openclaw config set \
  --batch-json '[{"path":"gateway.controlUi.allowedOrigins","value":["https://openclaw.seudominio.com.br"]}]'

docker service update --force openclaw_openclaw_gateway
```

---

#### ❌ `No API key found for provider "openai"`

**Causa:** Chave API OpenAI não configurada.

**Solução para PM2:**
```bash
openclaw configure
# Ou
export OPENAI_API_KEY="sk-..."
```

**Solução para Docker:**
```bash
# Verificar se variável de ambiente está definida
docker exec -it $(docker ps --filter name=openclaw -q) printenv OPENAI_API_KEY

# Se vazio, definir na configuração
openclaw config set agents.main.auth.openai.apiKey sk-...

# Ou atualizar variáveis de ambiente no Portainer e reimplantar
```

---


### Comandos de Diagnóstico

**Para Método PM2:**
```bash
# Verificação completa do sistema
openclaw doctor

# Ver toda a configuração
openclaw config get

# Verificar status do PM2
pm2 status
pm2 monit

# Ver logs
pm2 logs openclaw-gateway --lines 100

# Verificar porta
ss -lntp | grep 18789

# Testar acesso local
curl http://127.0.0.1:18789/healthz

# Verificar Caddy
sudo systemctl status caddy
sudo journalctl -u caddy -f
```

**Para Método Docker:**
```bash
# Verificação completa do sistema
openclaw doctor

# Ver toda a configuração
openclaw config get

# Verificar status do serviço
docker service ls | grep openclaw
docker service ps openclaw_openclaw_gateway

# Ver logs
docker service logs -f openclaw_openclaw_gateway

# Verificar saúde do contêiner
docker ps --filter name=openclaw

# Entrar no contêiner
docker exec -it $(docker ps --filter name=openclaw -q) bash

# Testar dentro do contêiner
docker exec -it $(docker ps --filter name=openclaw -q) curl http://127.0.0.1:18789/healthz

# Verificar Traefik
docker service logs traefik | grep openclaw

# Ver detalhes do serviço
docker service inspect openclaw_openclaw_gateway
```

---