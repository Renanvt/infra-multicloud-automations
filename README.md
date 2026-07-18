<!--
 alobexpress-setup (c) by Jonatan Renan
 
 alobexpress-setup is licensed under a
 Creative Commons Attribution 4.0 International License.
-->

<p align="center">
  <a href="" rel="noopener">
 <img width=200px height=200px src="https://i.imgur.com/FxL5qM0.jpg" alt="Bot logo"></a>
</p>

<h2 align="center">INFRAESTRUTURA ALOB EXPRESS (MULTI-CLOUD) v2.1.0</h2>
<h3 align="center">AWS & Google Cloud | Docker Swarm | N8N | Traefik | Portainer | Evolution API | Chatwoot | Dify AI</h3>

<div align="center">

[![Status](https://img.shields.io/badge/status-active-success.svg)]()
[![Platform](https://img.shields.io/badge/cloud-AWS%20%7C%20GCP-orange.svg)]()
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](/LICENSE)

</div>

---

<p align="center"> 🤖 Infraestrutura como Código (IaC) moderna e unificada para automação de alta performance. 🤖
    <br> 
</p>

# 📋 Índice

- [Visão Geral e Arquitetura](#-visão-geral-e-arquitetura)
- [Preparação da Nuvem (Passo a Passo)](#-preparação-da-nuvem)
  - [Opção A: Amazon AWS](#opção-a-amazon-aws)
  - [Opção B: Google Cloud Platform (GCP)](#opção-b-google-cloud-platform-gcp)
- [Instalação Automatizada](#-instalação-automatizada)
- [Pós-Instalação e Configuração](#-pós-instalação-e-configuração)
  - [Localização dos Arquivos de Configuração](#-localização-dos-arquivos-de-configuração)
  - [Alterar Credenciais (credentials.env)](#-alterar-credenciais-credentialsenv)
  - [DNS (Cloudflare)](#dns-cloudflare)
  - [Banco de Dados N8N](#criar-banco-de-dados-n8n-obrigatório)
  - [CORS (Evolution API)](#-configurar-cors-para-evolution-api)
- [Custos e Otimização Financeira](#-custos-e-otimização)
- [Segurança e Backups Automáticos](#-segurança-e-manutenção)
- [Otimização Automática de Recursos (80/20)](#-otimização-automática-de-recursos)
- [📘 Guia Prático de DevOps (Docker & Cloud)](#-guia-prático-de-devops-docker--cloud)
  - [Comandos Essenciais](#comandos-essenciais)
  - [Transferência de Arquivos](#transferência-de-arquivos-uploaddownload)
  - [Logs e Monitoramento Avançado](#logs-e-monitoramento-avançado)
- [Instalação Standalone do Dify (Híbrido)](#-instalação-standalone-do-dify-híbrido)
- [Troubleshooting](#-troubleshooting)

---

# 🏗 Visão Geral e Arquitetura

Este projeto utiliza **Docker Swarm** para orquestrar contêineres de forma resiliente e escalável, suportando tanto **AWS** quanto **Google Cloud**.

### Diagrama de Infraestrutura

![infra-aloexpress](/img/infrastructure-diagram.png)

```mermaid
graph TD
    User((Internet User)) -->|HTTPS/443| CloudFW[Cloud Firewall]
    CloudFW -->|TCP| Traefik
    
    subgraph "Single High-Spec VM (16GB RAM)"
        Traefik[Traefik Proxy v3]
        Portainer[Portainer CE]
        
        subgraph "Data Layer"
            Postgres[(Postgres 16)]
            Redis[(Redis 7)]
            PgVector[(PgVector)]
        end
        
        subgraph "Business Apps"
            n8n[n8n Automation]
            EvoAPI[Evolution API]
            Chatwoot[Chatwoot]
            Typebot[Typebot]
        end
        
        subgraph "AI Services"
            DifyAPI[Dify API]
            DifyWeb[Dify Web]
            DifyWorker[Dify Worker]
            DifySand[Dify Sandbox]
        end
    end

    %% Routing
    Traefik --> n8n
    Traefik --> EvoAPI
    Traefik --> Chatwoot
    Traefik --> Typebot
    Traefik --> DifyWeb
    Traefik --> DifyAPI

    %% Connections
    n8n -.-> Postgres
    EvoAPI -.-> Postgres
    EvoAPI -.-> Redis
    Chatwoot -.-> Postgres
    Chatwoot -.-> Redis
    
    DifyAPI -.-> PgVector
    DifyAPI -.-> Redis
    DifyWorker -.-> PgVector
    
    style Traefik fill:#f9f,stroke:#333,stroke-width:2px
    style Postgres fill:#bbf,stroke:#333,stroke-width:2px
    style PgVector fill:#bbf,stroke:#333,stroke-width:2px
```

---

# ☁ Preparação da Nuvem

Escolha seu provedor de nuvem e siga os passos detalhados de preparação.

## Opção A: Amazon AWS

### 1. Criar Bucket S3 (Para Backups e Evolution API)
1. Acesse: [S3 Console](https://s3.console.aws.amazon.com/s3/)
2. **Create bucket** (Crie DOIS buckets separados):
   
   #### A. Bucket de Mídia (Público) - Para Evolution API
   - **Nome Sugerido**: `alobexpress-evolution-media-2025` (ou similar)
   - **Configuração de Bloqueio Público**:
     - ⬜ Desmarque "Block all public access" (Bloquear todo acesso público).
     - Confirme que você entende os riscos (é necessário para o WhatsApp baixar as mídias).
   
   - **Bucket Policy (Leitura Pública Obrigatória)**:
     1. Vá na aba **Permissions** > **Bucket policy** > **Edit**.
     2. Cole o JSON abaixo (troque `SEU_BUCKET_DE_MIDIA` pelo nome real):
     ```json
     {
         "Version": "2012-10-17",
         "Statement": [
             {
                 "Effect": "Allow",
                 "Principal": "*",
                 "Action": "s3:GetObject",
                 "Resource": "arn:aws:s3:::SEU_BUCKET_DE_MIDIA/*"
             }
         ]
     }
     ```

   - **CORS (Cross-origin resource sharing)**:
     1. Ainda na aba **Permissions**, role até o final em **CORS** > **Edit**.
     2. Cole o JSON abaixo (Permite que o navegador/WhatsApp baixe os arquivos):
     ```json
     [
         {
             "AllowedHeaders": ["*"],
             "AllowedMethods": ["GET", "HEAD"],
             "AllowedOrigins": ["*"],
             "ExposeHeaders": []
         }
     ]
     ```

   #### B. Bucket de Backup e Dify (Privado)
   - **Nome Sugerido**: `alobexpress-storage-2025` (ou similar)
   - **Configuração de Bloqueio Público**:
     - ✅ **Marque a opção "Block all public access"** (Bloquear todo acesso público).
     - Isso garante que seus backups e arquivos do Dify (RAG) não fiquem expostos na internet.
   - **Bucket Policy (Acesso Restrito ao Root/IAM)**:
     ```json
     {
         "Version": "2012-10-17",
         "Statement": [
             {
                 "Sid": "PermissaoRestrita",
                 "Effect": "Allow",
                 "Principal": { "AWS": "arn:aws:iam::SEU_ACCOUNT_ID:root" },
                 "Action": [
                     "s3:PutObject",
                     "s3:GetObject",
                     "s3:ListBucket"
                 ],
                 "Resource": [
                     "arn:aws:s3:::SEU_BUCKET_DE_BACKUP",
                     "arn:aws:s3:::SEU_BUCKET_DE_BACKUP/*"
                 ]
             }
         ]
     }
     ```
     - Ative o Versionamento (Versioning).
     - Crie uma Lifecycle Rule para expirar arquivos antigos após 30/90 dias.
3. **Região**: `us-east-1` (Recomendado).



### 2. Criar Usuário IAM
1. Acesse IAM > Users > Create user.
2. Nome: `seu_negocio-user`.
3. Permissões: `AmazonS3FullAccess`.
4. **Crie Access Keys** e SALVE-AS.

### 3. Criar Instância EC2
1. **Imagem (AMI)**: `Ubuntu Server 22.04 LTS`.
2. **Tipo**: `t3.large` (Recomendado para stack completa) ou `t3.small` (apenas N8N/Evolution).
3. **Storage**: 80GB gp3.
4. **Security Group**:
   - Permitir **SSH (22)** do seu IP.
   - Permitir **HTTP (80)** de 0.0.0.0/0.
   - Permitir **HTTPS (443)** de 0.0.0.0/0.

## Opção B: Google Cloud Platform (GCP) - Recomendado

### 1. Criar Compute Engine (VM)
1. **Região**: `us-central1` (Iowa) ou `us-east1`.
2. **Máquina**: `e2-standard-4` (4 vCPU, 16GB RAM) para stack completa (com Dify).
3. **Disco de Inicialização**:
   - Imagem: `Debian GNU/Linux 12 (bookworm)` ou `Ubuntu 22.04 LTS`.
   - Tamanho: 80GB SSD Persistente.
4. **Firewall**:
   - ✅ Permitir tráfego HTTP.
   - ✅ Permitir tráfego HTTPS.

---

# 🚀 Instalação Automatizada

O script modular `install.sh` orquestra a instalação e detecta o ambiente para ambos os provedores.

### 1. Conectar na VM
```bash
# AWS
ssh -i "sua-chave.pem" ubuntu@seu-ip-publico

# GCP (via Console ou Terminal)
gcloud compute ssh --zone "us-central1-a" "nome-da-vm"
```

### 2. Instalação Rápida (Recomendada)
O comando abaixo baixa o instalador e todos os módulos necessários automaticamente:

```bash
curl -sL https://raw.githubusercontent.com/Renanvt/infra-cloud-aws-google/main/install.sh | sudo bash
```

### 3. Instalação Manual (Git)
Se preferir clonar o repositório completo:

```bash
# 1. Clone o repositório
git clone https://github.com/Renanvt/infra-cloud-aws-google.git infra-alob
cd infra-alob

# 2. Dê permissão de execução
chmod +x install.sh

# 3. Execute o instalador
sudo ./install.sh
```

### 4. Instalação Manual (Upload)
Se preferir enviar os arquivos manualmente:

```bash
# Compacte o projeto na sua máquina local
tar -czvf infra.tar.gz install.sh modules/

# Envie para o servidor
scp infra.tar.gz ubuntu@SEU_IP:/home/ubuntu/

# No servidor:
tar -xzvf infra.tar.gz
chmod +x install.sh
sudo ./install.sh
```

---

# ⚙ Pós-Instalação e Configuração

## 📂 Localização dos Arquivos de Configuração
Os arquivos de configuração `.yaml` (Docker Compose) e `.env` são gerados e salvos automaticamente no diretório do negócio:
`/opt/infra/<NOME_DO_NEGOCIO>/`

## 🔑 Alterar Credenciais (credentials.env)

Todas as senhas, chaves e hashes gerados durante a instalação ficam salvos em:

```
/var/log/<NOME_DO_NEGOCIO>/credentials.env
```


### Como visualizar as credenciais atuais

```bash
# Substitua NOME_DO_NEGOCIO pelo nome informado no instalador (ex: alobexpress)
sudo cat /var/log/NOME_DO_NEGOCIO/credentials.env
```

> **Atalho:** se você já sabe o nome do negócio, rode direto:
> ```bash
> cat /var/log/alobexpress/credentials.env
> ```

### Como alterar uma senha

1. Edite o YAML do serviço correspondente dentro de `/opt/infra/<NOME_DO_NEGOCIO>/`:

   ```bash
   cd /opt/infra/NOME_DO_NEGOCIO
   nano 26.open-design.yaml   # exemplo
   ```

2. Para serviços com **Basic Auth** (Open Design, Postiz Temporal UI), gere um novo hash:

   ```bash
   # Instalar htpasswd se necessário
   apt-get install -y apache2-utils

   # Gerar hash — substitua USUARIO e NOVA_SENHA
   htpasswd -nb USUARIO NOVA_SENHA | sed 's/\$/\$\$/g'
   ```

   Cole o hash gerado na linha `basicauth.users` do YAML correspondente.

3. Redeploy o serviço para aplicar:

   ```bash
   docker stack deploy --detach=true -c 26.open-design.yaml open_design
   docker stack deploy --detach=true -c 22.postiz.yaml postiz
   ```

4. Atualize o registro no `credentials.env`:

   ```bash
   nano /var/log/NOME_DO_NEGOCIO/credentials.env
   # Edite apenas os valores — nunca exponha este arquivo publicamente
   ```

### Referência rápida de credenciais por serviço

| Serviço | Arquivo YAML | Observação |
|---------|-------------|------------|
| Postgres | todos os YAMLs com `DATABASE_URL` | Alterar exige redeploy de todos os dependentes |
| Redis | todos os YAMLs com `REDIS_URL` | Idem |
| Open Design | `26.open-design.yaml` → `basicauth.users` | Requer hash htpasswd |
| Postiz Temporal UI | `22.postiz.yaml` → `basicauth.users` do `postiz_temporal_ui` | Requer hash htpasswd |
| N8N Encryption Key | `08.n8n-editor.yaml` | ⚠️ Alterar invalida credenciais salvas no N8N |
| Evolution API Key | `18.evolution_v2.yaml` | Atualizar também nas integrações (Chatwoot, N8N) |

---

## DNS (Cloudflare)
Configure seus apontamentos DNS no Cloudflare apontando para o **IP Público** da sua VM.
**Use "DNS Only" (Nuvem Cinza) inicialmente para garantir a geração dos certificados SSL.**

| Tipo | Nome | Destino | Comentário |
|------|------|----------|------------|
| **A** | `automations` | `SEU_IP_VM` | Apontamento Principal |
| **CNAME** | `painel` | `automations.meu-dominio.com` | Portainer |
| **CNAME** | `n8n` | `automations.meu-dominio.com` | N8N Editor |
| **CNAME** | `evolution` | `automations.meu-dominio.com` | Evolution API |
| **CNAME** | `chatwoot` | `automations.meu-dominio.com` | Chatwoot |
| **CNAME** | `dify` | `automations.meu-dominio.com` | Dify Web |
| **CNAME** | `api` | `automations.meu-dominio.com` | Dify API |

## Criar Banco de Dados N8N (Obrigatório)
O N8N precisa que o banco de dados seja criado manualmente no primeiro uso (se o script não conseguir).

1. Acesse o **Portainer** (`https://painel.seu-dominio.com`).
2. Vá em **Containers** > Encontre o `postgres`.
3. Clique no ícone **>_ Console** > **Connect**.
4. Execute: `psql -U postgres -c "CREATE DATABASE n8n;"`

## 💬 Configurar Chatwoot

O Chatwoot é uma plataforma de atendimento ao cliente open-source que se integra perfeitamente com a Evolution API.

### Pré-requisitos
1. **Configurar DNS no Resend** (OBRIGATÓRIO):
   - Acesse: https://resend.com/domains
   - Configure os registros DKIM, SPF e DMARC para o domínio do seu email
   - Sem essa configuração, os emails do Chatwoot não serão entregues!

### Configuração Automática

O script de instalação executa automaticamente:
- ✅ Criação do banco de dados `chatwoot_production`
- ✅ Configuração de permissões do diretório de storage (1000:1000)
- ✅ Execução das migrações (`db:chatwoot_prepare`)
- ✅ Criação do usuário administrador com senha gerada
- ✅ Criação da Account e vinculação ao usuário
- ✅ Envio de email de confirmação (se DNS configurado corretamente)

### Primeiro Acesso

1. **Localizar Credenciais**: As credenciais foram exibidas no final da instalação
   ```
   Chatwoot Admin Email: seu-email@dominio.com
   Chatwoot Admin Password: [senha gerada]
   ```

2. **Fazer Login**:
   - Acesse: `https://chatwoot.seu-dominio.com/app/login`
   - Use as credenciais fornecidas

3. **Configurar Empresa**:
   - Vá em **Settings → Account Settings**
   - Configure nome, logo e preferências
   - Crie seu primeiro **Inbox** em **Settings → Inboxes → Add Inbox**

### Integração com Evolution API

O Chatwoot já está pré-configurado para se integrar com a Evolution API. Para conectar:

1. No Chatwoot: **Settings** → **Inboxes** → **Add Inbox** → **API**
2. Na Evolution API, use o endpoint:
   ```bash
   POST https://evolution.seu-dominio.com/chatwoot/set/{instance}
   ```

**Documentação Completa**: Consulte [docs/CHATWOOT-SETUP.md](docs/CHATWOOT-SETUP.md) para instruções detalhadas.

## 🛡️ Configurar CORS (para Evolution API)
*Já coberto na seção [Preparação da Nuvem](#1-criar-bucket-s3-para-backups-e-evolution-api).*
Certifique-se de que o **Bucket de Mídia** possui a configuração de CORS permitindo `GET` e `HEAD` para funcionar corretamente com o WhatsApp e Navegadores.


# 🛠 Operações Avançadas (AWS)

## Como Expandir Volume AWS

1. No Console AWS > Volumes > Modify Volume > Aumente o tamanho.
2. Na VM:
   ```bash
   # Listar discos
   lsblk
   
   # Expandir partição
   sudo growpart /dev/nvme0n1 1
   
   # Redimensionar sistema de arquivos
   sudo resize2fs /dev/nvme0n1p1
   ```

## Como Atachar Volume EBS
Se você precisar de um segundo disco (`/data`):

1. Crie o volume na mesma Zona de Disponibilidade (AZ).
2. Attach volume à instância.
3. Na VM:
   ```bash
   # Formatar (apenas se for novo!)
   sudo mkfs -t ext4 /dev/xvdf

   # Montar
   sudo mkdir /data
   sudo mount /dev/xvdf /data
   
   # Persistir no fstab (Cuidado!)
   # UUID=... /data ext4 defaults,nofail 0 2
   ```


---

# 💰 Custos e Otimização

## AWS (Free Tier & Projeções)
*   **EC2 (t3.small)**: ~$15-20/mês (Básico).
*   **EC2 (t3.large)**: ~$60-70/mês (Stack Completa).
*   **EBS (80GB)**: ~$8/mês.

### Breakdown de Custos Mensais AWS
![Breakdown 1](img/1.PNG)
![Breakdown 2](img/2.PNG)

### Projeção de Custos Real
![Projeção](img/3.PNG)

## Google Cloud (Estimativas)
*   **VM Principal (e2-standard-4)**: ~$105,84/mês (Alta performance, 16GB RAM).
*   **VM Média (e2-standard-2)**: ~$57,42/mês (8GB RAM).

### Otimizações
1.  **S3 Lifecycle (Automação de Custos)**:
    Para reduzir custos, configure o S3 para mover backups antigos para "Glacier" (armazenamento frio/barato) e apagar após 90 dias.
    
    1. Crie um arquivo chamado `s3-lifecycle.json` com o conteúdo abaixo:
    ```json
    {
        "Rules": [
            {
                "ID": "MoveToGlacierAndExpire",
                "Prefix": "backups/",
                "Status": "Enabled",
                "Transitions": [
                    {
                        "Days": 30,
                        "StorageClass": "GLACIER"
                    }
                ],
                "Expiration": {
                    "Days": 90
                }
            }
        ]
    }
    ```
    
    2. Aplique a regra no seu bucket de backup:
    ```bash
    aws s3api put-bucket-lifecycle-configuration --bucket NOME_DO_BUCKET_BACKUP --lifecycle-configuration file://s3-lifecycle.json
    ```

2.  **N8N Pruning**: O script já configura limpeza automática de execuções antigas (72h) para economizar disco.

## Sistema de Backups Automáticos (S3)

O sistema inclui scripts para realizar backups completos (Banco de Dados + Volumes) e enviá-los para um Bucket S3 da AWS.

### 1. Requisitos no S3
1. Crie um Bucket S3 (ex: `alobexpress-storage-2025`).
2. **Importante**: Crie uma pasta chamada `backups/` (no plural) dentro deste bucket. O script espera encontrar esta pasta.

### 2. Permissões AWS
Certifique-se de que as permissões foram configuradas conforme a [Seção de Preparação](#1-criar-bucket-s3-para-backups-e-evolution-api).

Se você optou por criar um **Usuário IAM Dedicado** (em vez de usar a Bucket Policy no root), adicione esta política ao usuário:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PermissaoBackupS3",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::alobexpress-storage-2025",
                "arn:aws:s3:::alobexpress-storage-2025/backups/*"
            ]
        }
    ]
}
```

### 3. O que é salvo?
O script `backup_to_s3.sh` realiza o backup de todos os componentes críticos:
*   **N8N**: Todos os fluxos, credenciais e histórico (via Dump do Postgres).
*   **Chatwoot**: Conversas, contatos e configurações (via Dump do Postgres + Volume de storage).
*   **Dify**: Base de conhecimento (Vector Store), fluxos e configurações (via Dump do Postgres + PgVector).
*   **Evolution API**: Instâncias e sessões (via Volume `evolution_v2_data`).
*   **Infra**: Certificados SSL (Traefik) e dados do Portainer.

**Nota sobre o Arquivo de Backup (.tar.gz):**
O arquivo gerado no S3 possui a extensão `.tar.gz`. Se você baixar e extrair este arquivo no Windows, ele pode aparecer como uma pasta com o mesmo nome do arquivo (ex: `backup_20251231_144856`). Dentro desta pasta, você encontrará os arquivos SQL e pastas de volume. Isso é normal e esperado.

### 4. Executando o Backup

#### Opção A: Backup para S3 (Recomendado)
**Execução Manual:**
```bash
# Execute e siga as instruções interativas
./backup_to_s3.sh
```

**Instalação Rápida (Curl):**
Se o arquivo não existir (nova VM), baixe e execute diretamente:
```bash
curl -sL "https://setup.alobexpress.com.br/backup_to_s3.sh" -o backup_to_s3.sh
chmod +x backup_to_s3.sh
sudo ./backup_to_s3.sh
```

**Automação (Cron):**
Para rodar todo dia às 03:00am, adicione ao crontab (`crontab -e`):
```bash
0 3 * * * S3_BUCKET=alobexpress-storage-2025 S3_REGION=us-east-1 S3_ACCESS_KEY=SUA_KEY S3_SECRET_KEY=SUA_SECRET /opt/infra/NOME_DO_NEGOCIO/backup_to_s3.sh >> /var/log/backup_s3.log 2>&1
```

#### Opção B: Backup Local (VM)
Ideal para snapshots rápidos antes de mudanças. O script salva localmente e gerencia rotação (padrão: 7 dias).

**Instalação Rápida (Curl):**
```bash
curl -sL "https://setup.alobexpress.com.br/backup_to_vm.sh" -o backup_to_vm.sh
chmod +x backup_to_vm.sh
sudo ./backup_to_vm.sh
```

**Variáveis Opcionais:**
Você pode definir o diretório e retenção:
```bash
BACKUP_ROOT_DIR=/meus/backups RETENTION_DAYS=15 ./backup_to_vm.sh
```

### 5. Restaurando Backup (Disaster Recovery)

Se você precisar restaurar um backup (ex: migração de servidor ou recuperação de desastre), use o script `restore_from_s3.sh`.

1. **Baixe e execute o script**:
   ```bash
   # Se o repositório já estiver clonado:
   sudo ./restore_from_s3.sh
   
   # Ou baixe e execute diretamente (em nova VM):
   curl -fsSL https://raw.githubusercontent.com/alob-express/infra-alob-express/main/restore_from_s3.sh -o restore_from_s3.sh
   chmod +x restore_from_s3.sh
   sudo ./restore_from_s3.sh
   ```

2. **Siga o assistente**:
   - O script pedirá suas credenciais S3.
   - Listará os backups disponíveis.
   - Baixará e restaurará automaticamente Volumes e Banco de Dados.

> **Nota**: O script gerencia a parada/início da stack se necessário para garantir a integridade dos dados.

# ⚡ Otimização Automática de Recursos

O sistema aplica a regra de ouro de **80/20** para evitar travamentos e garantir estabilidade sob alta carga:

*   **Limite Máximo (Limits)**: Containers podem usar até 80% da RAM total disponível.
*   **Reserva Garantida (Requests)**: 10% reservado para serviços críticos (Garantia de QoS).

**Dify AI (SLA)**: Para o Dify, garantimos 2 vCPUs e 4GB de RAM dedicados para evitar queda de conexões durante processamento de vetores.

### Monitoramento em Tempo Real (DevOps)
Para verificar se a alocação de recursos está adequada:

```bash
# Ver consumo de CPU/RAM em tempo real
docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Verificar limites definidos
docker inspect NOME_CONTAINER --format '{{.HostConfig.Memory}}'
```

---



# 📘 Guia Prático de DevOps (Docker & Cloud)

Esta seção contém comandos e procedimentos essenciais para o dia a dia.

## Comandos Essenciais

### Gestão de Stacks (Serviços)
```bash
# Listar serviços rodando
docker service ls

# Ver logs de um serviço (tempo real)
docker service logs -f NOME_SERVICO

# Reiniciar um serviço (forçar update)
docker service update --force NOME_SERVICO
```

### Gestão de Containers Individuais
```bash
# Listar todos (inclusive parados)
docker ps -a

# Ver logs de um container específico
docker logs --tail 100 -f NOME_CONTAINER

# Entrar no terminal do container
docker exec -it NOME_CONTAINER /bin/sh
```

### Manutenção Completa (Parar/Iniciar)

**Parar tudo com segurança:**
```bash
docker stack rm traefik portainer postgres redis rabbitmq n8n_editor n8n_worker n8n_webhook evolution_v2 dify_pgvector dify_sandbox dify_api dify_web dify_worker
```

**Iniciar tudo:**
```bash
# 1. Infra
docker stack deploy -c infra/04.traefik.yaml traefik
docker stack deploy -c infra/05.portainer.yaml portainer
docker stack deploy -c infra/06.postgres.yaml postgres
docker stack deploy -c infra/07.redis.yaml redis
docker stack deploy -c infra/11.rabbitmq.yaml rabbitmq

# 2. Apps
docker stack deploy -c infra/08.n8n-editor.yaml n8n_editor
docker stack deploy -c infra/18.evolution_v2.yaml evolution_v2
# ... (demais serviços)
```

## Transferência de Arquivos (Upload/Download)

### Baixar da VM para seu PC
**Método via Navegador (SSH GCP):**
1. Na VM: `sudo tar -czf /tmp/backup.tar.gz /caminho/da/pasta`
2. No SSH do Navegador: Clique na engrenagem ⚙️ > **Download file** > Digite `/tmp/backup.tar.gz`.

**Método via Terminal (gcloud):**
```bash
gcloud compute scp INSTANCIA:/tmp/backup.tar.gz ~/Downloads/ --zone=us-central1-a
```

### Enviar do PC para a VM
```bash
gcloud compute scp ~/Downloads/arquivo.txt INSTANCIA:/tmp/ --zone=us-central1-a
```


## 🔄 Guia de Restauração de Backup (S3)

Se você precisa restaurar dados de um backup anterior, siga este checklist rigoroso para garantir a integridade dos dados.

### ✅ Checklist Pré-Restauração

**1. Pré-requisitos de Acesso:**
Certifique-se de que você consegue acessar as URLs dos serviços (mesmo que vazios):
- [ ] Portainer: `https://${PORTAINER_DOMAIN}`
- [ ] N8N Editor: `https://${N8N_EDITOR_DOMAIN}`
- [ ] RabbitMQ: `https://${RABBITMQ_DOMAIN}`
- [ ] Evolution API: `https://${EVOLUTION_DOMAIN}`
- [ ] Dify (se instalado): `https://${DIFY_WEB_DOMAIN}`

**2. Tempo de Estabilização:**
- [ ] Aguarde pelo menos **5 minutos** após o início dos containers.
  - *Motivo:* O Postgres precisa inicializar o banco e rodar migrations iniciais antes de aceitar sobrescrita de dados.

**3. Status dos Serviços:**
- [ ] Verifique no Portainer se todos os containers estão com status `running` ou `healthy`.
- [ ] Não inicie a restauração se houver containers em `restarting`.

### 🚀 Executando a Restauração

**Opção A: Durante o Setup**
O script de instalação perguntará ao final se deseja restaurar. Responda `sim` e siga o assistente.

**Opção B: Manualmente (Pós-instalação)**
```bash
cd /opt/infra/NOME_DO_NEGOCIO
sudo ./restore_from_s3.sh
```

### ⏳ Pós-Restauração

1. O script pode solicitar a reinicialização da stack.
2. Após o término, **aguarde novamente 2 a 5 minutos** para que os serviços carreguem os dados restaurados do disco para a memória.
3. Valide se seus fluxos (N8N), instâncias (Evolution) e dados (Dify) reapareceram.

---

## Logs e Monitoramento Avançado

### Ver logs de TODOS os containers rodando (Script Rápido)
```bash
for container in $(docker ps --format '{{.Names}}'); do 
    echo "=== Logs de $container ===" 
    docker logs --tail 50 $container 
    echo "" 
done
```

### 🧹 Limpeza Segura de Disco (Best Practices)

Evite usar `docker system prune -a --volumes` cegamente, pois isso apaga dados persistentes! Use os comandos abaixo:

#### 1. Diagnóstico
```bash
# Ver quanto espaço você vai liberar (SEM apagar nada)
docker system df

# Ver espaço em disco do sistema
df -h
```

#### 2. Limpeza Segura (Sem perda de dados)
```bash
# Limpar apenas containers parados
docker container prune

# Limpar apenas imagens "dangling" (imagens quebradas/sem tag)
docker image prune

# Limpar redes não usadas
docker network prune

# Limpar todas imagens não usadas (MANTÉM volumes/dados)
docker system prune -a
```

#### 3. Gestão de Volumes (Cuidado!)
```bash
# Listar todos os volumes
docker volume ls

# Ver onde o volume está sendo usado
docker ps -a --filter volume=NOME_DO_VOLUME

# Backup de volume (Exemplo)
docker run --rm -v NOME_VOLUME:/data -v $(pwd):/backup alpine tar czf /backup/volume-backup.tar.gz /data
```

> **Recomendação**: Use `docker system prune -a` para limpeza geral. Isso limpa containers parados, imagens não usadas e redes, mas **MANTÉM seus volumes e bancos de dados intactos**.

---

# 🤖 Instalação Standalone do Dify (Híbrido)

Para rodar o Dify em uma VM separada (Híbrido: AWS <-> GCP), use o script dedicado:

```bash
curl -sL https://setup.alobexpress.com.br/setup_dify.sh | sudo bash
```

Siga o assistente interativo para configurar a integração de rede entre as duas VMs.

---

# 🚨 Troubleshooting

## Traefik - Erro ao Obter Certificados SSL (AWS)

### Sintoma
Logs do Traefik mostram erros como:
```
Unable to obtain ACME certificate for domains [...]: error: 403
acme: error presenting token: [...] could not find the start of authority
```

### Causa Raiz
O **Security Group da AWS não possui regras de entrada (Inbound Rules)** configuradas, bloqueando as portas 80 e 443 necessárias para validação ACME do Let's Encrypt.

### Solução Passo a Passo

#### 1. Verificar Security Group (AWS Console)
1. Acesse: **EC2 > Instances > Sua instância**
2. Aba **Security** (parte inferior)
3. Clique no **Security Group** (ex: `n8n-securitygroup`)
4. Aba **Inbound rules**

#### 2. Adicionar Regras Obrigatórias
Se a tabela estiver vazia ou sem as regras HTTP/HTTPS, clique em **"Edit inbound rules"** e adicione:

| Type  | Protocol | Port Range | Source    | Description |
|-------|----------|------------|-----------|-------------|
| HTTP  | TCP      | 80         | 0.0.0.0/0 | Allow HTTP for ACME validation |
| HTTPS | TCP      | 443        | 0.0.0.0/0 | Allow HTTPS |
| SSH   | TCP      | 22         | Seu IP    | SSH Access |

**⚠️ CRÍTICO**: A porta **80** é obrigatória para validação ACME, mesmo que você só use HTTPS depois.

#### 3. Validar Conectividade
Após salvar as regras, aguarde 30 segundos e teste:

```bash
# Do seu PC (PowerShell/Terminal):
curl http://SEU_IP_PUBLICO

# Deve retornar "404 Not Found" (isso é bom! Significa que o Traefik respondeu)
# Se der timeout, o Security Group ainda está bloqueando
```

#### 4. Limpar Certificados e Reiniciar Traefik
```bash
# Na VM:
# 1. Parar o Traefik
docker stack rm traefik

# 2. Aguardar parar completamente
sleep 10

# 3. Limpar certificados corrompidos
docker volume rm volume_swarm_certificates
docker volume create volume_swarm_certificates

# 4. Redeployar
cd /opt/infra/<SEU_NEGOCIO>
docker stack deploy -c 04.traefik.yaml traefik

# 5. Acompanhar logs
docker service logs -f traefik_traefik
```

#### 5. Verificar Sucesso
Nos logs, você deve ver:
```
✅ "The ACME certificate has been generated"
✅ "Serving default certificate"
```

Acesse seus domínios via HTTPS para confirmar os certificados válidos.

### Prevenção
- Sempre configure o Security Group **antes** de rodar o instalador
- Use "DNS Only" (nuvem cinza) no Cloudflare durante a primeira geração de certificados
- Aguarde propagação DNS (2-5 minutos) antes de iniciar o Traefik

---

## Portainer - Tempo Limite Expirado

### Sintoma
Ao acessar o Portainer pela primeira vez, aparece mensagem de que o tempo para criar senha expirou.

### Causa
O Portainer é reiniciado automaticamente ao final da instalação para zerar o timer de 5 minutos. Se ainda assim o tempo expirou (você demorou mais de 5 min após o fim da instalação), reinicie manualmente:

### Solução
```bash
docker service update --force portainer_portainer

# Acesse imediatamente após o comando:
# https://painel.seu-dominio.com
# Você tem 5 minutos para criar a senha de admin
```

---

## Evolution API - Redis Disconnected (Logs Vermelhos)

### Sintoma
Logs do Evolution mostram repetidamente:
```
[Redis] [string] redis disconnected
[Redis] [string] redis connecting
```

### Diagnóstico
- ✅ **NORMAL no início**: O Evolution tenta conectar antes do Redis estar pronto
- ✅ Após 2-5 minutos, deve aparecer `[Redis] [string] redis ready`
- ❌ **PROBLEMA**: Se continuar após 10 minutos, verifique se o Redis está rodando:

```bash
docker service ls | grep redis
docker service logs redis_redis
```

---

## Container Reiniciando (Loop)

### Diagnóstico
```bash
# Ver logs do container
docker logs --tail 50 NOME_CONTAINER

# Ver motivo da parada (OOM Kill, Exit Code)
docker inspect NOME_CONTAINER --format='{{.State.Status}} - {{.State.ExitCode}}'
```

### Causas Comuns
1. **Falta de memória (OOM Kill)**: Ajuste os limites no arquivo YAML
2. **Erro de conexão com banco**: Verifique se Postgres/Redis estão rodando
3. **Variável de ambiente faltando**: Revise o arquivo YAML

---

## Traefik - "Port is missing"

### Solução
Certifique-se de que o serviço tem a porta definida nos labels:
```yaml
deploy:
  labels:
    - "traefik.http.services.NOME.loadbalancer.server.port=8080"
```

---

## Evolution API - Erro S3 "ENOTFOUND"

### Causa
O endpoint do S3 está com `https://` no início.

### Solução
O Evolution V2 requer apenas o hostname:
- ❌ Errado: `https://s3.us-east-1.amazonaws.com`
- ✅ Correto: `s3.us-east-1.amazonaws.com`

Edite o arquivo `18.evolution_v2.yaml` e remova o protocolo.

---

## Open Design / Postiz — Erro 502 após Migração de VM

### Sintoma
Serviços que funcionavam na VM anterior retornam 502 ou não sobem na nova VM.

### Causa Raiz
A VM nova não tem os certificados SSL gerados ainda. O Traefik precisa gerar novos certificados via Let's Encrypt, e para isso o DNS deve estar em modo **DNS Only (nuvem cinza)** no Cloudflare — nunca em Proxied durante esse processo.

### Solução

1. No Cloudflare, confirme que **todos os registros DNS estão em "DNS Only" (nuvem cinza)**

2. Limpe os certificados antigos e force a regeneração:

   ```bash
   docker stack rm traefik
   sleep 15
   docker volume rm volume_swarm_certificates
   docker volume create volume_swarm_certificates
   cd /opt/infra/NOME_DO_NEGOCIO
   docker stack deploy --detach=true -c 04.traefik.yaml traefik
   docker service logs -f traefik_traefik
   ```

3. Aguarde aparecer nos logs: `"The ACME certificate has been generated"`

4. Redeploy dos serviços afetados:

   ```bash
   docker stack deploy --detach=true -c 26.open-design.yaml open_design
   docker stack deploy --detach=true -c 22.postiz.yaml postiz
   ```

---

## Open Design — Container em Erro / Não Inicia

### Sintoma
`docker service ps open_design_open-design` mostra estado de erro ou `0/1` réplicas, mesmo com YAML correto.

### Diagnóstico

```bash
docker service logs -f open_design_open-design
docker service ps open_design_open-design --no-trunc
```

### Causa Raiz: Imagem Incorreta

A imagem `vanjayak/open-design` está desatualizada. A imagem oficial é `ghcr.io/nexu-io/od:latest`, com variáveis de ambiente diferentes.

| Variável antiga (incorreta) | Variável correta |
|-----------------------------|-----------------|
| `OD_DISABLE_API_AUTH: "1"` | `OPEN_DESIGN_DISABLE_API_AUTH: "1"` |
| `OD_BIND_HOST: "0.0.0.0"` | *(não necessário)* |
| `OD_PORT: "7456"` | *(não necessário)* |
| `OD_ALLOWED_ORIGINS: "..."` | `OPEN_DESIGN_ALLOWED_ORIGINS: "..."` |

### Solução

```bash
docker stack rm open_design
sleep 10

# Edite o YAML: troque a imagem e as variáveis
nano /opt/infra/NOME_DO_NEGOCIO/26.open-design.yaml

docker stack deploy --detach=true -c 26.open-design.yaml open_design
docker service logs -f open_design_open-design
```

**Outras causas comuns**

```bash
# Diretório de dados não existe
mkdir -p /opt/infra/NOME_DO_NEGOCIO/open-design/data
chmod 755 /opt/infra/NOME_DO_NEGOCIO/open-design/data
docker service update --force open_design_open-design

# Hash Basic Auth inválido — regere com:
apt-get install -y apache2-utils
htpasswd -nb USUARIO SENHA | sed 's/\$/\$\$/g'
# Cole no yaml e redeploy
docker stack deploy --detach=true -c 26.open-design.yaml open_design
```

---

## Postiz — Erro 502 (APIs retornam status 502)

### Sintoma
O frontend carrega mas as chamadas de API (`/api/user/self`, `/api/copilot/chat`, etc.) retornam 502. Console mostra `TypeError: XX.find is not a function`.

### Causa
O container do Postiz está em loop de restart aguardando o Temporal + Elasticsearch ficarem prontos. O Temporal depende do Elasticsearch, que pode levar 2-3 minutos para inicializar.

### Solução

```bash
# 1. Verificar estado de todos os serviços do Postiz
docker service ls | grep postiz

# 2. Ver logs do Elasticsearch (deve mostrar "started" antes do Temporal iniciar)
docker service logs -f postiz_postiz_temporal_elasticsearch

# 3. Ver logs do Temporal
docker service logs -f postiz_postiz_temporal

# 4. Se o Elasticsearch estiver com erro de permissão no diretório:
chown -R 1000:1000 /opt/infra/NOME_DO_NEGOCIO/postiz/elasticsearch
docker service update --force postiz_postiz_temporal_elasticsearch

# 5. Aguardar o Temporal ficar pronto e reiniciar o Postiz
docker service update --force postiz_postiz
```

### Verificar ordem de inicialização
O Postiz precisa que os serviços subam nesta ordem:
1. `postiz_temporal_elasticsearch` → healthy
2. `postiz_temporal` → running
3. `postiz` → healthy

---

## Hermes Agent — Gateway Para com WARNING (Sem Plataformas Configuradas)

### Sintoma
O container do Hermes sobe mas para imediatamente com mensagens como:
```
WARNING gateway.run: No messaging platforms enabled.
WARNING gateway.run: No env user allowlists configured.
```
`docker service ps hermes_hermes_gateway` mostra `0/1` ou status de erro.

### Causa
O Hermes Gateway requer ao menos uma plataforma de mensagens configurada (Telegram, WhatsApp, etc.) e/ou uma allowlist de usuários para funcionar. Sem isso, ele encerra a execução intencionalmente.

### Solução

1. Acesse o diretório de dados do Hermes na VM:
   ```bash
   ls /opt/infra/NOME_DO_NEGOCIO/hermes/
   ```

2. Crie ou edite o arquivo de configuração do gateway:
   ```bash
   nano /opt/infra/NOME_DO_NEGOCIO/hermes/gateway.toml
   ```

3. Consulte a documentação oficial do Hermes para configurar sua plataforma de mensagens preferida. No mínimo, configure `GATEWAY_ALLOW_ALL_USERS=true` para testes:
   ```bash
   # Edite o YAML e adicione a variável de ambiente:
   nano /opt/infra/NOME_DO_NEGOCIO/20.hermes-agent.yaml
   # Adicione em environment:
   #   GATEWAY_ALLOW_ALL_USERS: "true"
   docker stack deploy --detach=true -c 20.hermes-agent.yaml hermes
   ```

> **Nota**: O Hermes Dashboard (`hermes_dashboard`) requer que o Gateway esteja rodando e saudável. Ele depende do `GATEWAY_HEALTH_URL` configurado no YAML.

---

## Cloudflare — Proxied vs DNS Only

### Quando usar cada modo

| Modo | Quando usar |
|------|-------------|
| **DNS Only** (nuvem cinza) | Sempre na instalação inicial e ao trocar de VM — necessário para o Traefik gerar certificados SSL via Let's Encrypt |
| **Proxied** (nuvem laranja) | Após os certificados SSL estarem válidos e os serviços funcionando, para ganhar proteção DDoS e CDN da Cloudflare |

### Ao trocar de VM, siga esta ordem:
1. Aponte o registro A para o novo IP da VM no Cloudflare em modo **DNS Only**
2. Instale a infra e aguarde o Traefik gerar os certificados (verifique nos logs)
3. Confirme que todos os serviços respondem via HTTPS
4. **Só então** ative o modo Proxied, se desejar

> ⚠️ Ativar o modo Proxied antes dos certificados estarem prontos pode causar loops de certificado ou erros 526 (Invalid SSL Certificate).

---
<img width=200px height=200px src="img/5.PNG" alt="Bot logo"></a>

**Versão**: 2.1.0 | **Atualizado**: Julho 2026 | **Novo**: Troubleshooting expandido (Open Design, Postiz, Hermes, Cloudflare)
