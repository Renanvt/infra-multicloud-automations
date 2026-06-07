# FFmpeg no n8n — Instalação Permanente via Imagem Customizada + Custom Nodes

Guia para instalar o FFmpeg de forma permanente e adicionar custom nodes no n8n rodando via Docker Swarm.

---

## Por que precisa de imagem customizada

A imagem oficial `n8nio/n8n` não inclui o FFmpeg. É possível instalar via `apk add` diretamente no container, mas a instalação some ao reiniciar. A solução permanente é criar uma imagem customizada baseada na oficial com o FFmpeg já incluído.

Os custom nodes (Evolution API, WAHA, Puppeteer, etc.) **não devem ser instalados via Dockerfile** — o n8n recria o diretório `.n8n` ao iniciar e apaga o que foi instalado na imagem. A forma correta é instalar via terminal ou pelo painel do n8n após o container estar rodando.

---

## Parte 1 — FFmpeg (via imagem customizada)

### 1. Criar o Dockerfile

```bash
mkdir -p /opt/infra/SEU_PROJETO/n8n-custom
nano /opt/infra/SEU_PROJETO/n8n-custom/Dockerfile
```

Cole o conteúdo:

```dockerfile
FROM n8nio/n8n:2.0.2
USER root
# Utilitários do sistema
RUN apk add --no-cache \
    ffmpeg \
    imagemagick \
    ghostscript \
    python3 \
    py3-pip
USER node
```

> Atualize `2.0.2` para a versão do n8n que você está usando.
> Para descobrir: `docker service inspect n8n_editor_n8n_editor --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'`

Salve com `Ctrl+X`, `Y`, `Enter`.

### 2. Fazer o build da imagem

```bash
cd /opt/infra/SEU_PROJETO/n8n-custom
docker build -t SEU_PROJETO/n8n-custom:2.0.2 .
```

### 3. Atualizar os YAMLs das stacks

O n8n tem três stacks separadas (`n8n_editor`, `n8n_webhook`, `n8n_worker`). Edite o YAML de cada uma e troque a imagem:

```yaml
# De:
image: n8nio/n8n:2.0.2

# Para:
image: SEU_PROJETO/n8n-custom:2.0.2
```

### 4. Aplicar a nova imagem nos serviços

```bash
docker service update --image SEU_PROJETO/n8n-custom:2.0.2 n8n_editor_n8n_editor
docker service update --image SEU_PROJETO/n8n-custom:2.0.2 n8n_webhook_n8n_webhook
docker service update --image SEU_PROJETO/n8n-custom:2.0.2 n8n_worker_n8n_worker
```

> **Atenção:** não use apenas `--force` sem especificar a imagem — ele reinicia o container com a imagem antiga.

### 5. Verificar instalação do FFmpeg

```bash
docker exec -it $(docker ps --filter name=n8n_editor_n8n_editor -q) ffmpeg -version
docker exec -it $(docker ps --filter name=n8n_webhook_n8n_webhook -q) ffmpeg -version
docker exec -it $(docker ps --filter name=n8n_worker_n8n_worker -q) ffmpeg -version
```

---

## Parte 2 — Custom Nodes

> **Importante:** custom nodes NÃO devem ser instalados via Dockerfile. O n8n recria o diretório `/home/node/.n8n` ao iniciar e apaga qualquer coisa instalada na imagem. A instalação correta é feita após o container estar rodando.

### Opção A — Via painel do n8n (mais simples)

Acesse o n8n → **Settings → Community Nodes → Install** e cole o nome do pacote:

- `n8n-nodes-evolution-api-english` — Evolution API v2.3+ (WhatsApp)
- `@devlikeapro/n8n-nodes-waha` — WhatsApp via WAHA
- `n8n-nodes-puppeteer` — automação de browser
- `n8n-nodes-text-manipulation` — manipulação avançada de texto
- `n8n-nodes-ollama` — modelos de IA locais via Ollama

### Opção B — Via terminal (mesmo resultado)

```bash
docker exec -it --user node $(docker ps --filter name=n8n_editor_n8n_editor -q) \
  /bin/sh -c "cd /home/node/.n8n/nodes && npm install n8n-nodes-evolution-api-english"

docker exec -it --user node $(docker ps --filter name=n8n_editor_n8n_editor -q) \
  /bin/sh -c "cd /home/node/.n8n/nodes && npm install @devlikeapro/n8n-nodes-waha"

docker exec -it --user node $(docker ps --filter name=n8n_editor_n8n_editor -q) \
  /bin/sh -c "cd /home/node/.n8n/nodes && npm install n8n-nodes-puppeteer"

docker exec -it --user node $(docker ps --filter name=n8n_editor_n8n_editor -q) \
  /bin/sh -c "cd /home/node/.n8n/nodes && npm install n8n-nodes-text-manipulation"

docker exec -it --user node $(docker ps --filter name=n8n_editor_n8n_editor -q) \
  /bin/sh -c "cd /home/node/.n8n/nodes && npm install n8n-nodes-ollama"

docker exec -it --user node $(docker ps --filter name=n8n_editor_n8n_editor -q) \
  /bin/sh -c "cd /home/node/.n8n/nodes && npm install @mendable/n8n-nodes-firecrawl"
```

Após instalar todos, reinicie o serviço para carregar os nodes:

```bash
docker service update --force n8n_editor_n8n_editor
```

### Verificar nodes instalados

```bash
docker exec -it --user root $(docker ps --filter name=n8n_editor_n8n_editor -q) \
  ls /home/node/.n8n/nodes/node_modules
```

---

## Atualizando o n8n no futuro

Quando atualizar a versão do n8n, refaça o processo da Parte 1 com a nova versão:

```bash
# 1. Editar o Dockerfile com a nova versão
nano /opt/infra/SEU_PROJETO/n8n-custom/Dockerfile
# Troque: FROM n8nio/n8n:2.0.2 → FROM n8nio/n8n:NOVA_VERSAO

# 2. Rebuild
cd /opt/infra/SEU_PROJETO/n8n-custom
docker build -t SEU_PROJETO/n8n-custom:NOVA_VERSAO .

# 3. Atualizar serviços
docker service update --image SEU_PROJETO/n8n-custom:NOVA_VERSAO n8n_editor_n8n_editor
docker service update --image SEU_PROJETO/n8n-custom:NOVA_VERSAO n8n_webhook_n8n_webhook
docker service update --image SEU_PROJETO/n8n-custom:NOVA_VERSAO n8n_worker_n8n_worker
```

> Os custom nodes instalados via painel ou terminal são salvos no volume persistente do n8n e **não precisam ser reinstalados** ao atualizar a versão.

---

## Erros conhecidos

### ❌ `ffmpeg: executable file not found in $PATH` após update

**Causa:** o `docker service update --force` não troca a imagem.

**Solução:** sempre especifique a imagem explicitamente:
```bash
docker service update --image SEU_PROJETO/n8n-custom:2.0.2 n8n_editor_n8n_editor
```

### ❌ Custom node instalado no Dockerfile não aparece no n8n

**Causa:** o n8n recria o diretório `/home/node/.n8n` ao iniciar, apagando os nodes instalados na imagem.

**Solução:** instale sempre via **Settings → Community Nodes** no painel ou via terminal como descrito na Parte 2.

### ❌ `EUNSUPPORTEDPROTOCOL: catalog:` ao instalar node

**Causa:** o pacote usa workspace monorepo incompatível com instalação direta.

**Solução:** use o nome correto do pacote. Para Evolution API o nome correto é `n8n-nodes-evolution-api-english`, não `n8n-nodes-evolution-api`.

### ❌ Imagem some após recriar o servidor

**Causa:** a imagem customizada existe apenas localmente no servidor.

**Solução:** guarde o Dockerfile e refaça o build. Para persistência total faça push para o Docker Hub:

```bash
docker login
docker push SEU_PROJETO/n8n-custom:2.0.2
```

