# Hermes Agent — Instalação via Docker Swarm

Guia prático para instalar o Hermes Agent via Docker Swarm com Traefik, incluindo migração do OpenClaw.

---

## O que é o Hermes Agent

O Hermes Agent é o sucessor do OpenClaw, desenvolvido pela Nous Research. Ele é um agente de IA autônomo que roda no seu servidor, aprende com o uso, cria skills automaticamente, e se conecta a canais de mensagem como Telegram, WhatsApp, Discord e Slack.

Pontos principais em relação ao OpenClaw:

- Mesma base, muito mais recursos
- Migração automática das configurações do OpenClaw (`hermes claw migrate`)
- Dashboard web integrado
- Suporte a múltiplos provedores de IA (OpenRouter, OpenAI, Anthropic, Ollama, etc.)
- Skills que se auto-melhoram durante o uso
- Agendamento com linguagem natural (cron)

---

## Pré-requisitos

| Requisito | Versão mínima |
|---|---|
| Docker Engine | 24.x |
| Docker Swarm | inicializado |
| Traefik | v2.x ou v3.x |

Antes de começar:

- A rede `network_swarm_public` já existe no swarm
- O Traefik está rodando com Let's Encrypt configurado
- Dois subdomínios apontando para o IP do servidor no DNS (Cloudflare):

| Subdomínio | Uso |
|---|---|
| `hermes.seudominio.com.br` | Gateway API + controle do agente |
| `hermes-dashboard.seudominio.com.br` | Dashboard web |

---

## Instalação passo a passo

### 1. Criar o diretório de dados

```bash
mkdir -p /opt/infra/SEU_PROJETO/hermes
chown -R 1000:1000 /opt/infra/SEU_PROJETO/hermes
```

> O Hermes usa uid 1000 internamente. Sem o `chown` o container não consegue gravar configurações.

### 2. Fazer o deploy no Portainer

Cole o conteúdo do `hermes-stack.yaml` em uma nova stack no Portainer e faça o deploy. Aguarde os dois serviços (`hermes_gateway` e `hermes_dashboard`) ficarem com status `Running`.

Verifique os logs:

```bash
docker service logs hermes_hermes_gateway --tail 30
```

### 3. Configuração inicial

> **Importante:** O gateway termina com `Complete` se não houver configuração prévia. Rode o setup **antes** de fazer o deploy da stack no Portainer, usando o container de forma interativa:

```bash
docker run -it --rm \
  -v /opt/infra/SEU_PROJETO/hermes:/opt/data \
  -e HERMES_HOME=/opt/data \
  nousresearch/hermes-agent:latest \
  hermes setup
```

O wizard vai guiar pela configuração de:

- Provedor de IA e modelo (OpenRouter, OpenAI, Anthropic, Ollama, etc.)
- Canais de mensagem (Telegram, WhatsApp, Discord, Slack)
- Ferramentas habilitadas
- Personalidade do agente

Após o setup concluir, faça o deploy da stack no Portainer — agora o gateway vai ficar `Running`.

### 4. Migrar do OpenClaw (opcional)

Se você já tem o OpenClaw instalado e quer importar todas as configurações:

```bash
# Preview do que será migrado (sem alterar nada)
docker exec -it $(docker ps --filter name=hermes_hermes_gateway -q) \
  hermes claw migrate --dry-run

# Executar a migração completa
docker exec -it $(docker ps --filter name=hermes_hermes_gateway -q) \
  hermes claw migrate
```

O que é migrado automaticamente:

- Memórias e perfis de usuário (MEMORY.md, USER.md)
- Skills criadas pelo usuário
- Configurações de canais (Telegram, WhatsApp, etc.)
- API keys (Telegram, OpenRouter, OpenAI, Anthropic, ElevenLabs)
- Allowlist de comandos
- SOUL.md (persona)

> O OpenClaw **não é removido** pelo migrate — os dois podem rodar em paralelo. Você decide quando desativar o OpenClaw.

### 5. Verificar instalação

```bash
docker exec -it $(docker ps --filter name=hermes_hermes_gateway -q) hermes doctor
```

Acesse o dashboard em `https://hermes-dashboard.seudominio.com.br` para ver sessões, skills, jobs agendados e configurações.

---

## Comandos úteis

```bash
# Iniciar conversa via CLI (forma interativa)
docker run -it --rm \
  -v /opt/infra/SEU_PROJETO/hermes:/opt/data \
  -e HERMES_HOME=/opt/data \
  nousresearch/hermes-agent:latest hermes

# Trocar modelo de IA
docker run -it --rm \
  -v /opt/infra/SEU_PROJETO/hermes:/opt/data \
  -e HERMES_HOME=/opt/data \
  nousresearch/hermes-agent:latest hermes model

# Diagnóstico
docker run -it --rm \
  -v /opt/infra/SEU_PROJETO/hermes:/opt/data \
  -e HERMES_HOME=/opt/data \
  nousresearch/hermes-agent:latest hermes doctor

# Logs em tempo real
docker service logs -f hermesagent_hermes_gateway
docker service logs -f hermesagent_hermes_dashboard

# Atualizar para versão mais recente
docker service update --image nousresearch/hermes-agent:latest hermesagent_hermes_gateway
docker service update --image nousresearch/hermes-agent:latest hermesagent_hermes_dashboard

# Criar alias permanente no host (muito mais prático)
echo 'alias hermes="docker run -it --rm -v /opt/infra/SEU_PROJETO/hermes:/opt/data -e HERMES_HOME=/opt/data nousresearch/hermes-agent:latest hermes"' >> ~/.bashrc && source ~/.bashrc

# Após criar o alias, use normalmente:
hermes
hermes model
hermes doctor
hermes setup
```

---

## Escolha do modelo de IA

Ao rodar `hermes model` você verá as opções disponíveis. Guia rápido de custo:

| Modelo | Custo | Recomendado para |
|---|---|---|
| `gpt-5.5` | Alto | Tarefas complexas, raciocínio avançado |
| `gpt-5.4` | Alto | Uso geral com alta qualidade |
| `gpt-5.4-mini` | Baixo | **Uso cotidiano — melhor custo-benefício** |
| OpenRouter/Gemini Flash | Muito baixo | Máxima economia |

Para usar o Gemini Flash via OpenRouter (quase gratuito), selecione **Enter custom model name** e digite:

```
openrouter/google/gemini-flash-1.5
```

Isso requer uma API key do OpenRouter configurada além da OpenAI.

---



Estes comandos funcionam tanto no CLI quanto nos canais de mensagem (Telegram, etc.):

| Comando | O que faz |
|---|---|
| `/new` ou `/reset` | Inicia nova conversa |
| `/model [provider:model]` | Troca o modelo de IA |
| `/personality [nome]` | Define uma personalidade |
| `/retry` | Refaz a última resposta |
| `/undo` | Desfaz o último turno |
| `/compress` | Comprime o contexto |
| `/usage` | Mostra uso de tokens |
| `/skills` | Lista skills disponíveis |
| `/stop` | Interrompe tarefa em andamento |
| `/status` | Status do gateway |

---

## Migração do OpenClaw — opções avançadas

```bash
# Migrar apenas dados do usuário (sem secrets/API keys)
hermes claw migrate --preset user-data

# Migrar e sobrescrever conflitos
hermes claw migrate --overwrite

# Ver todas as opções
hermes claw migrate --help
```

---

## Estrutura de arquivos no host

```
/opt/infra/SEU_PROJETO/hermes/
├── hermes.json           # Config principal
├── agents/
│   └── main/             # Agente principal
├── skills/               # Skills aprendidas
├── sessions/             # Histórico de conversas
├── memory/               # Memórias persistentes
└── logs/                 # Logs do gateway
```

---

## Diferenças entre OpenClaw e Hermes

| Recurso | OpenClaw | Hermes |
|---|---|---|
| Gateway de mensagens | ✅ | ✅ |
| Dashboard web | ✅ | ✅ |
| Skills automáticas | ✅ | ✅ (auto-melhora) |
| Múltiplos provedores de IA | Limitado | 200+ via OpenRouter |
| Agentes paralelos (subagents) | ❌ | ✅ |
| Cron em linguagem natural | ❌ | ✅ |
| Migração do OpenClaw | — | `hermes claw migrate` |
| Imagem Docker oficial | `ghcr.io/openclaw/openclaw` | `nousresearch/hermes-agent` |
| Porta padrão | 18789 | 8642 (gateway) / 9119 (dashboard) |