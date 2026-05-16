# Changelog

Todas as mudanças notáveis neste projeto serão documentadas neste arquivo.

## [2.1.0] - 2026-01-16

### ✨ Adicionado
- **Módulo Chatwoot**: Integração completa do Chatwoot v3.8.0
  - Configuração automatizada via script `install.sh`
  - Geração automática de `SECRET_KEY_BASE` usando OpenSSL
  - **Execução automática de migrações** (`db:chatwoot_prepare`)
  - **Criação automática de usuário administrador** com senha gerada
  - **Criação automática de Account** e vinculação ao usuário
  - Integração com Postgres e Redis existentes
  - Configuração de SMTP via Resend
  - Suporte a WebSocket para chat em tempo real
  - Sidekiq para processamento de jobs em background
  - Volume persistente para storage de arquivos
  - Healthcheck configurável (desabilitado no primeiro deploy)

- **Documentação Chatwoot**:
  - Guia completo de setup em `docs/CHATWOOT-SETUP.md`
  - Instruções de configuração DNS (DKIM, SPF, DMARC) no Resend
  - Troubleshooting detalhado
  - Guia de integração com Evolution API

- **Módulo `modules/chatwoot/setup.sh`**:
  - Função `setup_chatwoot_vars()` para coleta de inputs do usuário
  - Função `generate_chatwoot_yaml()` para geração do arquivo de configuração
  - Criação automática de diretórios de storage
  - Validação de inputs e confirmação de dados

- **Função `configure_chatwoot()` em `modules/core/deploy.sh`**:
  - Aguarda o container do Chatwoot inicializar (até 60 segundos)
  - Executa automaticamente `rails db:chatwoot_prepare`
  - Cria usuário administrador com senha aleatória segura (16 caracteres)
  - Usa nome do negócio como nome do administrador
  - Cria Account automaticamente com nome do negócio
  - Vincula usuário como administrador via `AccountUser`
  - **Envia email de confirmação automaticamente** (com tratamento de erro se DNS não configurado)
  - Exibe credenciais de acesso em formato destacado
  - Tratamento de erros com instruções de recuperação manual
  - Verifica se Account/User já existem antes de criar (idempotente)

### 🔧 Modificado
- **install.sh**: Adicionado carregamento do módulo Chatwoot
- **modules/chatwoot/setup.sh**:
  - Adicionado `chown -R 1000:1000` para permissões corretas do diretório de storage
  - Mensagem de sucesso após configurar permissões
- **modules/core/deploy.sh**:
  - Criação automática do banco `chatwoot_production`
  - Deploy do stack Chatwoot após Evolution API
  - Exibição de credenciais do Chatwoot no resumo final
  - Instruções pós-deploy para configuração inicial
  - Aviso sobre configuração DNS no Resend

- **README.md**:
  - Atualização da versão para 2.1.0
  - Adição do Chatwoot na lista de serviços
  - Nova seção de configuração do Chatwoot
  - Atualização da tabela DNS com entrada do Chatwoot
  - Atualização da seção de backups incluindo Chatwoot

### 📋 Arquivos Criados
- `modules/chatwoot/setup.sh` - Módulo principal do Chatwoot
- `docs/CHATWOOT-SETUP.md` - Documentação completa
- `CHANGELOG.md` - Este arquivo

### 🔄 Integração
- Chatwoot pré-configurado para integração com Evolution API
- Variável `CHATWOOT_IMPORT_DATABASE_CONNECTION_URI` configurada na Evolution
- Suporte a importação de conversas do WhatsApp via Evolution

### 🛡️ Segurança
- SECRET_KEY_BASE gerado com 128 caracteres hexadecimais (64 bytes)
- Senhas e credenciais exibidas apenas uma vez no resumo final
- Recomendação de configuração DNS para autenticação de emails

### 📦 Dependências
- Postgres 16 (banco `chatwoot_production`)
- Redis 7 (para cache e Sidekiq)
- Resend (SMTP para envio de emails)

### ⚠️ Notas de Migração
- Usuários existentes devem executar o script de instalação novamente ou:
  1. Baixar o módulo `modules/chatwoot/setup.sh`
  2. Executar manualmente as funções de setup
  3. Fazer deploy do stack: `docker stack deploy -c 19.chatwoot.yaml chatwoot`
  4. Seguir as instruções em `docs/CHATWOOT-SETUP.md`

---

## [2.0.1] - 2026-01-15

### 🔧 Modificado
- Melhorias na documentação
- Correções de bugs menores

### 🐛 Corrigido
- Problemas de permissão em volumes
- Erros de timeout no Traefik

---

## [2.0.0] - 2026-01-10

### ✨ Adicionado
- Suporte multi-cloud (AWS e Google Cloud)
- Módulo Dify AI
- Sistema de backup automatizado (S3 e local)
- Otimização automática de recursos (regra 80/20)

### 🔧 Modificado
- Refatoração completa da estrutura modular
- Melhorias no sistema de logging
- Atualização de todas as imagens Docker

---

## [1.0.0] - 2025-12-01

### ✨ Inicial
- Primeira versão estável
- Suporte para N8N, Evolution API, Traefik, Portainer
- Deploy via Docker Swarm
- Certificados SSL automáticos via Let's Encrypt
