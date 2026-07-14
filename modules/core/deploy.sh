#!/bin/bash

build_n8n_custom_image() {
    local N8N_VERSION="2.0.2"
    local IMAGE_TAG="alobexpress/n8n-custom:${N8N_VERSION}"
    local DOCKERFILE_DIR="/opt/alobexpress/n8n-custom"

    print_step "BUILD — IMAGEM CUSTOMIZADA DO N8N (FFmpeg + Extras)"

    # Criar pasta com permissões corretas
    print_info "Criando diretório ${DOCKERFILE_DIR}..."
    mkdir -p "${DOCKERFILE_DIR}"
    chmod 755 "${DOCKERFILE_DIR}"

    # Escrever Dockerfile no servidor
    print_info "Gravando Dockerfile em ${DOCKERFILE_DIR}/Dockerfile..."
    cat > "${DOCKERFILE_DIR}/Dockerfile" <<'DOCKERFILE'
FROM n8nio/n8n:2.0.2

USER root

# ffmpeg        — processamento de áudio/vídeo
# imagemagick   — manipulação de imagens
# ghostscript   — leitura e conversão de PDFs
# python3       — scripts Python nos nodes Code
# py3-pip       — gerenciador de pacotes Python
RUN apk add --no-cache \
    ffmpeg \
    imagemagick \
    ghostscript \
    python3 \
    py3-pip

USER node
DOCKERFILE

    # Build da imagem
    print_info "Iniciando build de '${IMAGE_TAG}' (pode levar alguns minutos)..."
    if docker build -t "${IMAGE_TAG}" "${DOCKERFILE_DIR}"; then
        print_success "Imagem '${IMAGE_TAG}' criada com sucesso!"
    else
        print_error "Falha no build da imagem n8n customizada. Verifique os logs acima."
        exit 1
    fi

    # Verificar FFmpeg dentro da imagem recém-criada
    # Usa --entrypoint para contornar o entrypoint padrão do n8n
    print_info "Verificando FFmpeg na imagem recém-criada..."
    FFMPEG_VER=$(docker run --rm --entrypoint ffmpeg "${IMAGE_TAG}" -version 2>&1 | head -1)
    if echo "${FFMPEG_VER}" | grep -q "ffmpeg version"; then
        print_success "FFmpeg OK: ${FFMPEG_VER}"
    else
        print_error "FFmpeg não encontrado na imagem. Verifique o Dockerfile."
        exit 1
    fi
}

install_n8n_custom_nodes() {
    print_step "INSTALANDO CUSTOM NODES DO N8N"

    # Aguardar editor estar disponível
    print_info "Aguardando n8n Editor inicializar (30s)..."
    sleep 30

    N8N_CONTAINER=""
    for i in {1..30}; do
        N8N_CONTAINER=$(docker ps -q -f name=n8n_editor_n8n_editor)
        if [ -n "$N8N_CONTAINER" ]; then
            break
        fi
        print_info "Aguardando container do n8n Editor... (tentativa $i/30)"
        sleep 6
    done

    if [ -z "$N8N_CONTAINER" ]; then
        print_error "Container do n8n Editor não encontrado. Instale os custom nodes manualmente via Settings → Community Nodes."
        return
    fi

    print_success "Container encontrado: ${N8N_CONTAINER}"

    # Garantir que o diretório de nodes existe
    docker exec -u node "$N8N_CONTAINER" /bin/sh -c "mkdir -p /home/node/.n8n/nodes" >/dev/null 2>&1

    install_node() {
        local PACKAGE="$1"
        local LABEL="$2"
        print_info "Instalando ${LABEL} (${PACKAGE})..."
        if docker exec -u node "$N8N_CONTAINER" \
            /bin/sh -c "cd /home/node/.n8n/nodes && npm install ${PACKAGE}" >/dev/null 2>&1; then
            print_success "${LABEL} instalado!"
        else
            print_warning "Falha ao instalar ${LABEL}. Instale manualmente via Settings → Community Nodes → ${PACKAGE}"
        fi
    }

    install_node "n8n-nodes-evolution-api-english"  "Evolution API (WhatsApp)"
    install_node "@devlikeapro/n8n-nodes-waha"       "WAHA (WhatsApp)"
    install_node "n8n-nodes-puppeteer"               "Puppeteer (Browser Automation)"
    install_node "n8n-nodes-text-manipulation"       "Text Manipulation"
    install_node "n8n-nodes-ollama"                  "Ollama (IA Local)"
    install_node "@mendable/n8n-nodes-firecrawl"     "Firecrawl (Web Scraping)"
    install_node "n8n-nodes-postiz"                  "Postiz (Social Media)"

    # Reiniciar editor para carregar os nodes
    print_info "Reiniciando n8n Editor para carregar os nodes instalados..."
    docker service update --force n8n_editor_n8n_editor >/dev/null 2>&1
    print_success "n8n Editor reiniciado!"

    # Aguardar subir novamente e listar nodes instalados
    print_info "Aguardando n8n Editor reiniciar (20s)..."
    sleep 20

    N8N_CONTAINER=$(docker ps -q -f name=n8n_editor_n8n_editor)
    if [ -n "$N8N_CONTAINER" ]; then
        print_step "CUSTOM NODES INSTALADOS"
        docker exec -u root "$N8N_CONTAINER" \
            ls /home/node/.n8n/nodes/node_modules 2>/dev/null \
            | grep -v "^$" \
            | while read -r NODE; do
                echo -e "   ${GREEN}✔${RESET} ${NODE}"
            done
    fi
}

verify_n8n_ffmpeg() {
    print_step "VERIFICANDO FFMPEG NOS SERVIÇOS N8N"

    verify_service_ffmpeg() {
        local FILTER="$1"
        local LABEL="$2"
        local CID
        CID=$(docker ps -q -f name="${FILTER}")
        if [ -n "$CID" ]; then
            VER=$(docker exec "$CID" ffmpeg -version 2>&1 | head -1)
            if echo "$VER" | grep -q "ffmpeg version"; then
                print_success "${LABEL}: FFmpeg OK"
            else
                print_warning "${LABEL}: FFmpeg não encontrado no container em execução"
            fi
        else
            print_warning "${LABEL}: container não encontrado (verifique com 'docker service ps')"
        fi
    }

    verify_service_ffmpeg "n8n_editor_n8n_editor"   "n8n Editor"
    verify_service_ffmpeg "n8n_worker_n8n_worker"    "n8n Worker"
    verify_service_ffmpeg "n8n_webhook_n8n_webhook"  "n8n Webhook"
}

deploy_services() {
    print_step "INICIANDO SERVIÇOS DE INFRAESTRUTURA"

    # ── Verificar se já existe instalação anterior ────────────────────────────
    local EXISTING_STACKS
    EXISTING_STACKS=$(docker stack ls --format "{{.Name}}" 2>/dev/null | grep -v "^$" || true)

    if [ -n "$EXISTING_STACKS" ]; then
        echo -e ""
        echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${BOLD}${YELLOW}║   ⚠️  STACKS EXISTENTES DETECTADAS                       ║${RESET}"
        echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════╝${RESET}"
        echo -e ""
        echo -e "  As seguintes stacks já estão rodando no Swarm:"
        echo "$EXISTING_STACKS" | while read -r STACK; do
            echo -e "   ${ARROW} ${BOLD}${STACK}${RESET}"
        done
        echo -e ""
        echo -e "  ${WHITE}Escolha o que fazer:${RESET}"
        echo -e ""
        echo -e "  ${CYAN}[1] Redeploy${RESET}     — Atualiza as stacks existentes sem apagar dados"
        echo -e "        ${DIM}(docker stack deploy — seguro, preserva volumes e bancos)${RESET}"
        echo -e ""
        echo -e "  ${CYAN}[2] Reinstalação limpa${RESET} — Remove TODAS as stacks e faz deploy do zero"
        echo -e "        ${RED}⚠️  remove containers mas NÃO apaga volumes/dados${RESET}"
        echo -e "        ${DIM}Os bancos de dados e arquivos persistentes são preservados.${RESET}"
        echo -e "        ${DIM}(use se os containers estiverem em estado de erro)${RESET}"
        echo -e ""
        echo -e "  ${CYAN}[3] Continuar assim mesmo${RESET} — Prossegue sem alterar nada"
        echo -e ""

        local DEPLOY_CHOICE=""
        while true; do
            read -p "$(echo -e "${GREEN}Opção (1/2/3): ${RESET}")" DEPLOY_CHOICE < /dev/tty || true
            case "$DEPLOY_CHOICE" in
                1)
                    print_info "Modo redeploy — stacks existentes serão atualizadas"
                    break
                    ;;
                2)
                    print_warning "Removendo stacks existentes..."
                    echo "$EXISTING_STACKS" | while read -r STACK; do
                        print_info "Removendo stack: ${STACK}..."
                        docker stack rm "$STACK" >/dev/null 2>&1 || true
                    done
                    print_info "Aguardando containers encerrarem (15s)..."
                    sleep 15
                    print_success "Stacks removidas — iniciando deploy limpo"
                    break
                    ;;
                3)
                    print_info "Prosseguindo sem alterar stacks existentes"
                    break
                    ;;
                *)
                    print_error "Opção inválida. Digite 1, 2 ou 3."
                    ;;
            esac
        done
        echo -e ""
    fi

    # 0. Build da imagem customizada do n8n (antes de qualquer deploy)
    build_n8n_custom_image

    # 1. Traefik e Portainer
    print_info "Deploying Traefik..."
    docker stack deploy --detach=true -c 04.traefik.yaml traefik >/dev/null 2>&1
    print_info "Deploying Portainer..."
    docker stack deploy --detach=true -c 05.portainer.yaml portainer >/dev/null 2>&1
    
    print_info "Aguardando serviços de infraestrutura subirem (15s)..."
    sleep 15
    
    # 2. Bancos de Dados
    print_info "Deploying Postgres..."
    docker stack deploy --detach=true -c 06.postgres.yaml postgres >/dev/null 2>&1
    print_info "Deploying Redis..."
    docker stack deploy --detach=true -c 07.redis.yaml redis >/dev/null 2>&1
    print_info "Deploying RabbitMQ..."
    docker stack deploy --detach=true -c 11.rabbitmq.yaml rabbitmq >/dev/null 2>&1
    
    print_info "Aguardando bancos de dados e RabbitMQ inicializarem (30s)..."
    sleep 30

    # 3. Criação dos Bancos de Dados
    print_step "CONFIGURANDO BANCO DE DADOS"
    print_info "Aguardando Postgres ficar pronto para aceitar conexões..."

    # Passo 1: esperar o container aparecer no Docker (até 60s)
    POSTGRES_CONTAINER=""
    for i in {1..30}; do
        POSTGRES_CONTAINER=$(docker ps -q -f name=postgres_postgres)
        if [ -n "$POSTGRES_CONTAINER" ]; then
            print_success "Container Postgres encontrado: ${POSTGRES_CONTAINER}"
            break
        fi
        echo -ne "  ${INFO} ${CYAN}Aguardando container Postgres... (${i}/30)${RESET}\r"
        sleep 2
    done
    echo ""

    # Passo 2: esperar o Postgres aceitar conexões (até 60s adicionais)
    if [ -n "$POSTGRES_CONTAINER" ]; then
        print_info "Aguardando Postgres aceitar conexões..."
        local PG_READY=false
        for i in {1..30}; do
            # Usar psql diretamente — mais confiável que pg_isready em Alpine
            if docker exec -i "$POSTGRES_CONTAINER" \
                psql -U postgres -c "SELECT 1;" >/dev/null 2>&1; then
                PG_READY=true
                print_success "Postgres aceitando conexões! (${i}x2s)"
                break
            fi
            echo -ne "  ${INFO} ${CYAN}Aguardando Postgres estar pronto... (${i}/30)${RESET}\r"
            sleep 2
        done
        echo ""

        if [ "$PG_READY" = false ]; then
            print_warning "Postgres ainda não respondeu via psql — tentando criar bancos mesmo assim..."
        fi
    fi

    # Exportar para módulos reutilizarem sem buscar novamente
    export POSTGRES_CONTAINER

    if [ -n "$POSTGRES_CONTAINER" ]; then
        # Helper local para criar banco sem duplicar código
        _create_db() {
            local DB="$1"
            if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE ${DB};" >/dev/null 2>&1; then
                print_success "Banco '${DB}' criado"
            else
                print_warning "Banco '${DB}' já existe ou erro na criação"
            fi
        }

        # Bancos sempre necessários
        _create_db "n8n"
        _create_db "evolution"
        _create_db "chatwoot_production"

        # Bancos condicionais
        [ "$ENABLE_DIFY"     = true ] && _create_db "dify"
        [ "$ENABLE_POSTIZ"   = true ] && _create_db "postiz"
        [ "$ENABLE_METABASE" = true ] && _create_db "metabase"
    else
        print_error "Container do Postgres não encontrado após 60s."
        echo -e "  ${YELLOW}Crie os bancos manualmente após o Postgres subir:${RESET}"
        echo -e "  ${DIM}PG=\$(docker ps -q -f name=postgres_postgres)${RESET}"
        echo -e "  ${DIM}for DB in n8n evolution chatwoot_production postiz metabase; do${RESET}"
        echo -e "  ${DIM}  docker exec -i \$PG psql -U postgres -c \"CREATE DATABASE \$DB;\"; done${RESET}"
    fi

    # 4. Deploy Aplicações
    print_step "DEPLOY DAS APLICAÇÕES DE NEGÓCIO"
    
    # Criar volume externo para Evolution
    docker volume create evolution_v2_data >/dev/null

    # Criar pasta local para o nó Read/Write Files from Disk do n8n
    print_info "Criando diretório de arquivos locais do n8n..."
    mkdir -p "/opt/infra/${BUSINESS_NAME}/n8n-local-files"
    chmod 777 "/opt/infra/${BUSINESS_NAME}/n8n-local-files"
    print_success "Diretório criado: /opt/infra/${BUSINESS_NAME}/n8n-local-files (montado como /files nos containers)"

    print_info "Deploying N8N Editor..."
    docker stack deploy --detach=true -c 08.n8n-editor.yaml n8n_editor >/dev/null 2>&1
    print_info "Deploying N8N Worker..."
    docker stack deploy --detach=true -c 09.n8n-workers.yaml n8n_worker >/dev/null 2>&1
    print_info "Deploying N8N Webhook..."
    docker stack deploy --detach=true -c 10.n8n-webhooks.yaml n8n_webhook >/dev/null 2>&1

    # Aguardar stacks n8n subirem antes de verificar FFmpeg e instalar nodes
    print_info "Aguardando stacks n8n iniciarem (45s)..."
    sleep 45

    # Verificar FFmpeg nos três serviços n8n
    verify_n8n_ffmpeg

    # Instalar custom nodes via terminal e reiniciar o editor
    install_n8n_custom_nodes

    print_info "Deploying Evolution V2..."
    docker stack deploy --detach=true -c 18.evolution_v2.yaml evolution_v2 >/dev/null 2>&1
    print_info "Deploying Chatwoot..."
    docker stack deploy --detach=true -c 19.chatwoot.yaml chatwoot >/dev/null 2>&1

    # Deploy OpenClaw (se escolhido no lugar do Dify)
    deploy_openclaw

    # Aguardar Chatwoot inicializar (Rails + Sidekiq são pesados no cold start)
    print_info "Aguardando Chatwoot inicializar (90s)..."
    sleep 90
    
    # Configurar Chatwoot (Migrações e Account)
    configure_chatwoot
    print_info "Chatwoot configurado — prosseguindo com demais módulos..."

    if [ "$ENABLE_DIFY" = true ]; then
        print_info "Realizando deploy do Dify AI..."
        # Criar volumes externos para Dify se necessário
        docker volume create pgvector_data >/dev/null
        docker volume create dify_plugin_cwd >/dev/null

        # 1. Deploy PGVector e Sandbox (Dependências)
        print_info "Deploying Dify PGVector & Sandbox..."
        docker stack deploy --detach=true -c 12.dify-pgvector.yaml dify_pgvector >/dev/null 2>&1
        docker stack deploy --detach=true -c 13.dify-sandbox.yaml dify_sandbox >/dev/null 2>&1
        
        # 2. Deploy API (Migration)
        print_info "Iniciando Dify API (Migrações de Banco de Dados)..."
        docker stack deploy --detach=true -c 15.dify-api.yaml dify_api >/dev/null 2>&1
        print_info "Aguardando migrações do Dify API (45s)..."
        sleep 45

        # 3. Deploy Plugin Daemon
        print_info "Deploying Dify Plugin Daemon..."
        docker stack deploy --detach=true -c 17.dify-plugindaemon.yaml dify_plugin_daemon >/dev/null 2>&1

        # 4. Deploy Web e Worker
        print_info "Deploying Dify Web & Worker..."
        docker stack deploy --detach=true -c 14.dify-web.yaml dify_web >/dev/null 2>&1
        docker stack deploy --detach=true -c 16.dify-worker.yaml dify_worker >/dev/null 2>&1
    fi

    # Deploy Postiz (gerenciador de redes sociais — independente do módulo de IA)
    if [ "$ENABLE_POSTIZ" = true ]; then
        deploy_postiz
    fi

    # Deploy Prometheus + Grafana + Node Exporter (stack integrada)
    if [ "$ENABLE_PROMETHEUS" = true ]; then
        deploy_prometheus
    fi

    # Deploy Open Design
    if [ "$ENABLE_OPEN_DESIGN" = true ]; then
        deploy_open_design
    fi

    # Deploy Metabase
    if [ "$ENABLE_METABASE" = true ]; then
        deploy_metabase
    fi

    # Deploy Hermes Agent
    if [ "$ENABLE_HERMES" = true ]; then
        deploy_hermes
    fi
}

configure_chatwoot() {
    print_step "CONFIGURANDO CHATWOOT (MIGRAÇÕES E ACCOUNT)"
    
    # Encontrar o container do Chatwoot Rails
    print_info "Localizando container do Chatwoot Rails..."
    CHATWOOT_CONTAINER=""
    for i in {1..30}; do
        CHATWOOT_CONTAINER=$(docker ps -q -f name=chatwoot_chatwoot_rails)
        if [ -n "$CHATWOOT_CONTAINER" ]; then
            break
        fi
        print_info "Aguardando container inicializar... (tentativa $i/30)"
        sleep 6
    done

    if [ -z "$CHATWOOT_CONTAINER" ]; then
        print_error "Container do Chatwoot Rails não encontrado!"
        print_warning "Execute manualmente após o container inicializar:"
        echo -e "  ${DIM}docker exec -i \$(docker ps -q -f name=chatwoot_rails) -e REDIS_URL=\"redis://:${REDIS_PASSWORD}@redis_redis:6379\" bundle exec rails db:chatwoot_prepare${RESET}"
        return
    fi
    
    print_success "Container encontrado: $CHATWOOT_CONTAINER"

    # Aguardar o Rails estar totalmente pronto verificando os logs do serviço
    # O Chatwoot faz bundle install no entrypoint — pode levar 5+ minutos
    print_info "Aguardando Rails inicializar completamente (bundle install + boot)..."
    local RAILS_READY=false
    for i in {1..60}; do
        local LOG_OUTPUT
        # Usar docker service logs que funciona tanto no primeiro deploy
        # quanto em redeploys (pega logs da task mais recente do serviço)
        LOG_OUTPUT=$(docker service logs chatwoot_chatwoot_rails --tail 10 --no-trunc 2>/dev/null | tail -10)
        # Fallback para docker logs direto se service logs não retornar nada
        if [ -z "$LOG_OUTPUT" ]; then
            LOG_OUTPUT=$(docker logs "$CHATWOOT_CONTAINER" 2>&1 | tail -5)
        fi
        # Verificar se o Puma já está escutando (Rails pronto)
        if echo "$LOG_OUTPUT" | grep -q "Listening on http"; then
            RAILS_READY=true
            print_success "Rails pronto! Puma escutando na porta 3000 (${i}x5s)"
            break
        fi
        # Mostrar progresso baseado no que está acontecendo
        if echo "$LOG_OUTPUT" | grep -q "bundle install\|Bundle complete\|bundle check"; then
            echo -ne "  ${INFO} ${CYAN}bundle install em andamento... (${i}/60)${RESET}\r"
        elif echo "$LOG_OUTPUT" | grep -q "Booting Puma\|starting in single mode"; then
            echo -ne "  ${INFO} ${CYAN}Puma iniciando... (${i}/60)${RESET}\r"
        elif echo "$LOG_OUTPUT" | grep -q "Waiting for postgres\|Database ready"; then
            echo -ne "  ${INFO} ${CYAN}Aguardando Postgres... (${i}/60)${RESET}\r"
        else
            echo -ne "  ${INFO} ${CYAN}Aguardando Rails ficar pronto... (${i}/60)${RESET}\r"
        fi
        sleep 5
    done
    echo ""

    if [ "$RAILS_READY" = false ]; then
        print_warning "Rails demorou mais que 5 min — verificando se já subiu via service logs..."
        # Última tentativa via service logs
        if docker service logs chatwoot_chatwoot_rails --tail 10 2>/dev/null | grep -q "Listening on http"; then
            RAILS_READY=true
            print_success "Rails confirmado via service logs"
        else
            print_warning "Tentando migrações mesmo assim..."
            sleep 15
        fi
    fi
    
    # Executar migrações do banco de dados
    print_info "Executando migrações do banco de dados (db:chatwoot_prepare)..."
    local MIGRATE_OUTPUT
    MIGRATE_OUTPUT=$(docker exec -i -e REDIS_URL="redis://:${REDIS_PASSWORD}@redis_redis:6379" \
        "$CHATWOOT_CONTAINER" bundle exec rails db:chatwoot_prepare 2>&1)
    local MIGRATE_EXIT=$?

    # Salvar saída para diagnóstico
    echo "$MIGRATE_OUTPUT" > /tmp/chatwoot_migrate.log

    # Considerar sucesso se:
    # - exit code 0
    # - saída contém "migrated" ou "Loading Installation config" (já migrado)
    # - saída não contém "Error" ou "error"
    if [ $MIGRATE_EXIT -eq 0 ] || \
       echo "$MIGRATE_OUTPUT" | grep -qi "loading installation config\|migrated\|already up"; then
        if echo "$MIGRATE_OUTPUT" | grep -qi "loading installation config" && \
           ! echo "$MIGRATE_OUTPUT" | grep -qi "error\|exception"; then
            print_success "Banco já estava preparado (migrações anteriores detectadas)"
        else
            print_success "Migrações executadas com sucesso!"
        fi
    else
        print_warning "Erro ao executar migrações. Saída:"
        echo "$MIGRATE_OUTPUT" | tail -20 | sed 's/^/  /'
        print_info "Para reexecutar manualmente:"
        echo -e "  ${DIM}CW=\$(docker ps -q -f name=chatwoot_chatwoot_rails)${RESET}"
        echo -e "  ${DIM}docker exec -i \$CW bundle exec rails db:chatwoot_prepare${RESET}"
        return
    fi
    
    # Verificar se já existe Account
    print_info "Verificando se Account já existe..."
    local ACCOUNT_COUNT_RAW
    ACCOUNT_COUNT_RAW=$(docker exec -i -e REDIS_URL="redis://:${REDIS_PASSWORD}@redis_redis:6379" \
        "$CHATWOOT_CONTAINER" bundle exec rails runner 'puts Account.count' 2>/dev/null)
    # Extrair só o número da última linha (rails runner pode emitir logs extras)
    ACCOUNT_COUNT=$(echo "$ACCOUNT_COUNT_RAW" | grep -E '^[0-9]+$' | tail -1)
    ACCOUNT_COUNT="${ACCOUNT_COUNT:-0}"
    
    if [ "$ACCOUNT_COUNT" -gt 0 ] 2>/dev/null; then
        print_success "Account já existe (total: $ACCOUNT_COUNT) — Chatwoot já configurado!"
        # Exibir URL de acesso mesmo assim
        echo -e "  ${WHITE}URL:${RESET} https://${CHATWOOT_DOMAIN}/app/login"
        echo -e "  ${WHITE}Email:${RESET} ${CHATWOOT_ADMIN_EMAIL}"
        if [ -n "$CHATWOOT_ADMIN_PASSWORD" ]; then
            echo -e "  ${WHITE}Senha:${RESET} ${CHATWOOT_ADMIN_PASSWORD}"
        else
            echo -e "  ${YELLOW}Senha: verifique em /var/log/${BUSINESS_NAME}/credentials.env${RESET}"
        fi
        print_info "Chatwoot OK — continuando deploy dos demais serviços..."
        return 0
    fi
    
    # Criar usuário administrador
    print_info "Criando usuário administrador..."
    ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
    
    ADMIN_NAME="${BUSINESS_NAME:-Admin}"
    ADMIN_NAME="${ADMIN_NAME^}"
    
    # Tenta criar — se já existir, busca o existente
    CREATE_USER_CMD="
begin
  u = User.find_by(email: '${CHATWOOT_ADMIN_EMAIL}')
  if u.nil?
    u = User.new(name: '${ADMIN_NAME}', email: '${CHATWOOT_ADMIN_EMAIL}', password: '${ADMIN_PASSWORD}', password_confirmation: '${ADMIN_PASSWORD}', confirmed_at: Time.now)
    u.skip_confirmation!
    u.save!
    puts 'Usuario criado!'
  else
    puts 'Usuario existente encontrado!'
  end
rescue => e
  puts \"Erro: \#{e.message}\"
end"

    USER_RESULT=$(docker exec -i -e REDIS_URL="redis://:${REDIS_PASSWORD}@redis_redis:6379" \
        "$CHATWOOT_CONTAINER" bundle exec rails runner "$CREATE_USER_CMD" 2>&1 | tail -3)
    
    if echo "$USER_RESULT" | grep -qi "criado\|existente"; then
        print_success "Usuário pronto: ${CHATWOOT_ADMIN_EMAIL}"
    else
        print_warning "Aviso na criação do usuário: $USER_RESULT"
    fi
    
    # Criar Account e vincular ao usuário (ou verificar se já existe)
    print_info "Criando Account e vinculando ao usuário..."
    ACCOUNT_NAME="${BUSINESS_NAME:-Minha Empresa}"
    ACCOUNT_NAME="${ACCOUNT_NAME^}"
    
    CREATE_ACCOUNT_CMD="
begin
  u = User.find_by(email: '${CHATWOOT_ADMIN_EMAIL}') || User.first
  a = Account.first_or_create!(name: '${ACCOUNT_NAME}')
  au = AccountUser.find_or_initialize_by(account: a, user: u)
  au.role = :administrator
  au.save!
  puts 'Conta criada e usuario vinculado'
rescue => e
  puts \"Erro: \#{e.message}\"
end"
    
    ACCOUNT_RESULT=$(docker exec -i -e REDIS_URL="redis://:${REDIS_PASSWORD}@redis_redis:6379" \
        "$CHATWOOT_CONTAINER" bundle exec rails runner "$CREATE_ACCOUNT_CMD" 2>&1 | tail -3)
    
    if echo "$ACCOUNT_RESULT" | grep -qi "vinculado"; then
        print_success "Account configurada com sucesso!"
        export CHATWOOT_ADMIN_PASSWORD="$ADMIN_PASSWORD"
        
        # Salvar senha no credentials.env
        if [ -f "${LOG_DIR}/credentials.env" ]; then
            echo "CHATWOOT_ADMIN_PASSWORD=\"${ADMIN_PASSWORD}\"" >> "${LOG_DIR}/credentials.env"
        fi
        
        echo -e ""
        echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
        echo -e "${BOLD}${GREEN}   CREDENCIAIS DE ACESSO - CHATWOOT${RESET}"
        echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
        echo -e "  ${WHITE}URL:${RESET}   https://${CHATWOOT_DOMAIN}/app/login"
        echo -e "  ${WHITE}Email:${RESET} ${CHATWOOT_ADMIN_EMAIL}"
        echo -e "  ${WHITE}Senha:${RESET} ${ADMIN_PASSWORD}"
        echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
        echo -e "  ${YELLOW}⚠️  SALVE ESTAS CREDENCIAIS AGORA!${RESET}"
        echo -e ""
    else
        print_warning "Aviso na criação da Account: $ACCOUNT_RESULT"
        echo -e "  ${DIM}Execute manualmente se necessário:${RESET}"
        echo -e "  ${DIM}CW=\$(docker ps -q -f name=chatwoot_chatwoot_rails)${RESET}"
        echo -e "  ${DIM}docker exec -i \$CW bundle exec rails runner 'a = Account.first_or_create!(name: \"${ACCOUNT_NAME}\"); AccountUser.find_or_create_by!(account: a, user: User.first, role: :administrator)'${RESET}"
    fi
}

print_summary() {
    # ── Reiniciar Portainer para garantir janela de 5 min para criar senha ──
    # O Portainer é deployado no início da instalação e expira após 5 min sem login.
    # Como a instalação pode durar 10-20 min, forçamos um restart aqui no final
    # para que o usuário tenha a janela completa disponível ao acessar o painel.
    print_step "REINICIANDO PORTAINER (janela de criação de senha)"
    if docker service update --force portainer_portainer >/dev/null 2>&1; then
        print_success "Portainer reiniciado — janela de 5 minutos para criar senha iniciada agora"
    else
        print_warning "Não foi possível reiniciar o Portainer automaticamente"
        echo -e "  ${DIM}Reinicie manualmente: docker service update --force portainer_portainer${RESET}"
    fi

    # Validação dos Serviços
    print_step "VALIDANDO SERVIÇOS (DOCKER SWARM)"
    docker service ls --format "table {{.Name}}\t{{.Replicas}}\t{{.Image}}" \
        || echo -e "${YELLOW}Não foi possível listar os serviços.${RESET}"
    echo ""

    # ── Resumo visual de instalação concluída ────────────────────────────────
    echo -e ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║   🚀 INSTALAÇÃO CONCLUÍDA COM SUCESSO!                       ║${RESET}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo -e ""
    echo -e "${BOLD}${CYAN}  SERVIÇOS INSTALADOS E URLs DE ACESSO:${RESET}"
    echo -e ""
    echo -e "  ${GREEN}✔${RESET} ${WHITE}Portainer${RESET}       https://${PORTAINER_DOMAIN}"
    echo -e "  ${GREEN}✔${RESET} ${WHITE}N8N Editor${RESET}      https://${N8N_EDITOR_DOMAIN}"
    echo -e "  ${GREEN}✔${RESET} ${WHITE}N8N Webhook${RESET}     https://${N8N_WEBHOOK_DOMAIN}"
    echo -e "  ${GREEN}✔${RESET} ${WHITE}RabbitMQ${RESET}        https://${RABBITMQ_DOMAIN}"
    echo -e "  ${GREEN}✔${RESET} ${WHITE}Evolution API${RESET}   https://${EVOLUTION_DOMAIN}"
    echo -e "  ${GREEN}✔${RESET} ${WHITE}Chatwoot${RESET}        https://${CHATWOOT_DOMAIN}"

    [ "$ENABLE_DIFY"        = true ] && echo -e "  ${GREEN}✔${RESET} ${WHITE}Dify Web${RESET}        https://${DIFY_WEB_DOMAIN}"
    [ "$ENABLE_DIFY"        = true ] && echo -e "  ${GREEN}✔${RESET} ${WHITE}Dify API${RESET}        https://${DIFY_API_DOMAIN}"
    [ "$ENABLE_OPENCLAW"    = true ] && echo -e "  ${GREEN}✔${RESET} ${WHITE}OpenClaw${RESET}        https://${OPENCLAW_DOMAIN}"
    [ "$ENABLE_POSTIZ"      = true ] && echo -e "  ${GREEN}✔${RESET} ${WHITE}Postiz${RESET}          https://${POSTIZ_DOMAIN}"
    [ "$ENABLE_POSTIZ"      = true ] && echo -e "  ${GREEN}✔${RESET} ${WHITE}Postiz Temporal${RESET} https://${POSTIZ_TEMPORAL_DOMAIN}"
    [ "$ENABLE_PROMETHEUS"  = true ] && echo -e "  ${GREEN}✔${RESET} ${WHITE}Prometheus${RESET}      https://${PROMETHEUS_DOMAIN}"
    [ "$ENABLE_GRAFANA"     = true ] && echo -e "  ${GREEN}✔${RESET} ${WHITE}Grafana${RESET}         https://${GRAFANA_DOMAIN}"
    [ "$ENABLE_OPEN_DESIGN" = true ] && echo -e "  ${GREEN}✔${RESET} ${WHITE}Open Design${RESET}     https://${OPEN_DESIGN_DOMAIN}"
    [ "$ENABLE_METABASE"    = true ] && echo -e "  ${GREEN}✔${RESET} ${WHITE}Metabase${RESET}        https://${METABASE_DOMAIN}"
    [ "$ENABLE_HERMES"      = true ] && echo -e "  ${GREEN}✔${RESET} ${WHITE}Hermes Gateway${RESET}  https://${HERMES_DOMAIN}"
    [ "$ENABLE_HERMES"      = true ] && [ -n "$HERMES_DASHBOARD_DOMAIN" ] && \
        echo -e "  ${GREEN}✔${RESET} ${WHITE}Hermes Dashboard${RESET} https://${HERMES_DASHBOARD_DOMAIN}"

    echo -e ""
    echo -e "${BOLD}${YELLOW}  ⚠️  ATENÇÃO: O Portainer foi reiniciado — você tem 5 MINUTOS para criar a senha de admin!${RESET}"
    echo -e "     Acesse AGORA: ${BOLD}https://${PORTAINER_DOMAIN}${RESET}"
    echo -e ""
    echo -e "${BOLD}${MAGENTA}  🔒 CREDENCIAIS GERADAS — SALVE AGORA:${RESET}"
    echo -e ""
    echo -e "  ${WHITE}Postgres:${RESET}          ${POSTGRES_PASSWORD}"
    echo -e "  ${WHITE}Redis:${RESET}             ${REDIS_PASSWORD}"
    echo -e "  ${WHITE}RabbitMQ:${RESET}          ${RABBITMQ_USER} / ${RABBITMQ_PASSWORD}"
    echo -e "  ${WHITE}N8N Encryption Key:${RESET} ${N8N_ENCRYPTION_KEY}"
    echo -e "  ${WHITE}Evolution API Key:${RESET}  ${EVOLUTION_API_KEY}"
    echo -e "  ${WHITE}Chatwoot Email:${RESET}    ${CHATWOOT_ADMIN_EMAIL}"
    [ -n "$CHATWOOT_ADMIN_PASSWORD" ] && \
        echo -e "  ${WHITE}Chatwoot Senha:${RESET}    ${CHATWOOT_ADMIN_PASSWORD}"
    [ "$ENABLE_POSTIZ"      = true ] && [ -n "$POSTIZ_TEMPORAL_PASSWORD" ] && \
        echo -e "  ${WHITE}Postiz Temporal:${RESET}   ${POSTIZ_TEMPORAL_USER} / ${POSTIZ_TEMPORAL_PASSWORD}"
    [ "$ENABLE_PROMETHEUS"  = true ] && \
        echo -e "  ${WHITE}Prometheus:${RESET}        ${PROMETHEUS_USER} / ${PROMETHEUS_PASSWORD}"
    [ "$ENABLE_GRAFANA"     = true ] && \
        echo -e "  ${WHITE}Grafana:${RESET}           ${GRAFANA_ADMIN_USER} / ${GRAFANA_ADMIN_PASSWORD}"
    [ "$ENABLE_OPEN_DESIGN" = true ] && \
        echo -e "  ${WHITE}Open Design:${RESET}       ${OPEN_DESIGN_USER} / ${OPEN_DESIGN_PASSWORD}"

    echo -e ""
    echo -e "  ${DIM}Credenciais completas salvas em: /var/log/${BUSINESS_NAME}/credentials.env${RESET}"
    echo -e ""

    # Avisos importantes
    if [ "$CHATWOOT_RESEND_CONFIGURED" != "true" ]; then
        echo -e "${BOLD}${YELLOW}  📧 RESEND (CHATWOOT) — Configure para receber emails:${RESET}"
        echo -e "     ${ARROW} https://resend.com/domains → DKIM, SPF, DMARC para ${CHATWOOT_ADMIN_EMAIL#*@}"
        echo -e ""
    fi

    echo -e "${BOLD}${CYAN}  📋 PRÓXIMOS PASSOS:${RESET}"
    echo -e "  ${ARROW} 1. Acesse o Portainer: https://${PORTAINER_DOMAIN} (crie a senha — timer reiniciado agora!)"
    echo -e "  ${ARROW} 2. Acesse o N8N: https://${N8N_EDITOR_DOMAIN}"
    echo -e "  ${ARROW} 3. Acesse o Chatwoot: https://${CHATWOOT_DOMAIN}/app/login"
    [ "$ENABLE_POSTIZ"   = true ] && echo -e "  ${ARROW} 4. Configure redes sociais no Postiz: https://${POSTIZ_DOMAIN}"
    [ "$ENABLE_GRAFANA"  = true ] && echo -e "  ${ARROW} 5. Adicione Prometheus como datasource no Grafana: http://prometheus_prometheus:9090"
    echo -e ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║   ✅ Tudo pronto! Bom trabalho.                              ║${RESET}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo -e ""
}
