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

    # Loop robusto: até 60s para o Postgres aceitar conexões (Swarm pode demorar)
    POSTGRES_CONTAINER=""
    for i in {1..30}; do
        POSTGRES_CONTAINER=$(docker ps -q -f name=postgres_postgres)
        if [ -n "$POSTGRES_CONTAINER" ]; then
            # Verificar se o Postgres já está aceitando conexões (não só rodando)
            if docker exec -i "$POSTGRES_CONTAINER" \
                pg_isready -U postgres >/dev/null 2>&1; then
                print_success "Postgres pronto! (${i}x2s)"
                break
            fi
        fi
        echo -ne "  ${INFO} ${CYAN}Aguardando Postgres... (${i}/30)${RESET}\r"
        sleep 2
        POSTGRES_CONTAINER=""
    done
    echo ""

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
        print_error "Postgres não respondeu após 60s. Crie os bancos manualmente:"
        echo -e "  ${DIM}docker exec -i \$(docker ps -q -f name=postgres_postgres) psql -U postgres -c 'CREATE DATABASE n8n;'${RESET}"
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
    
    # Executar migrações do banco de dados
    print_info "Executando migrações do banco de dados (db:chatwoot_prepare)..."
    if docker exec -i -e REDIS_URL="redis://:${REDIS_PASSWORD}@redis_redis:6379" "$CHATWOOT_CONTAINER" bundle exec rails db:chatwoot_prepare 2>&1 | tee /tmp/chatwoot_migrate.log | grep -q "migrated"; then
        print_success "Migrações executadas com sucesso!"
    else
        print_warning "Erro ao executar migrações. Verifique os logs:"
        echo -e "  ${DIM}docker service logs chatwoot_chatwoot_rails --tail 50${RESET}"
        cat /tmp/chatwoot_migrate.log
        return
    fi
    
    # Verificar se já existe Account
    print_info "Verificando se Account já existe..."
    ACCOUNT_COUNT=$(docker exec -i -e REDIS_URL="redis://:${REDIS_PASSWORD}@redis_redis:6379" "$CHATWOOT_CONTAINER" bundle exec rails runner 'puts Account.count' 2>/dev/null | tail -1)
    
    if [ "$ACCOUNT_COUNT" -gt 0 ] 2>/dev/null; then
        print_success "Account já existe (total: $ACCOUNT_COUNT)"
        
        # Verificar se usuário existe
        USER_COUNT=$(docker exec -i -e REDIS_URL="redis://:${REDIS_PASSWORD}@redis_redis:6379" "$CHATWOOT_CONTAINER" bundle exec rails runner 'puts User.count' 2>/dev/null | tail -1)
        if [ "$USER_COUNT" -gt 0 ] 2>/dev/null; then
            print_success "Usuário já existe (total: $USER_COUNT)"
            print_info "Chatwoot já está configurado!"
        fi
        return
    fi
    
    # Criar usuário administrador
    print_info "Criando usuário administrador..."
    ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
    
    ADMIN_NAME="${BUSINESS_NAME:-Admin}"
    ADMIN_NAME="${ADMIN_NAME^}" # Primeira letra maiúscula
    
    CREATE_USER_CMD="u = User.new(name: '${ADMIN_NAME}', email: '${CHATWOOT_ADMIN_EMAIL}', password: '${ADMIN_PASSWORD}', password_confirmation: '${ADMIN_PASSWORD}', confirmed_at: Time.now); u.skip_confirmation!; u.save!; puts 'Usuario criado!'"
    
    if docker exec -i -e REDIS_URL="redis://:${REDIS_PASSWORD}@redis_redis:6379" "$CHATWOOT_CONTAINER" bundle exec rails runner "$CREATE_USER_CMD" 2>&1 | grep -q "Usuario criado"; then
        print_success "Usuário administrador criado!"
    else
        print_warning "Erro ao criar usuário. Pode já existir."
    fi
    
    # Criar Account e vincular ao usuário
    print_info "Criando Account e vinculando ao usuário..."
    ACCOUNT_NAME="${BUSINESS_NAME:-Minha Empresa}"
    ACCOUNT_NAME="${ACCOUNT_NAME^}" # Primeira letra maiúscula
    
    CREATE_ACCOUNT_CMD="a = Account.create!(name: '${ACCOUNT_NAME}'); u = User.first; AccountUser.create!(account: a, user: u, role: :administrator); puts 'Conta criada e usuario vinculado'"
    
    if docker exec -i -e REDIS_URL="redis://:${REDIS_PASSWORD}@redis_redis:6379" "$CHATWOOT_CONTAINER" bundle exec rails runner "$CREATE_ACCOUNT_CMD" 2>&1 | grep -q "Conta criada"; then
        print_success "Account criada e vinculada ao usuário!"
        
        # Salvar credenciais de acesso
        export CHATWOOT_ADMIN_PASSWORD="$ADMIN_PASSWORD"
        
        # Tentar enviar email de confirmação (opcional - pode falhar se DNS não configurado)
        print_info "Tentando enviar email de confirmação..."
        SEND_EMAIL_CMD="mail = UserMailer.confirmation_instructions(User.last, User.last.confirmation_token); mail.deliver_now; puts 'Email enviado'"
        
        if docker exec -i -e REDIS_URL="redis://:${REDIS_PASSWORD}@redis_redis:6379" "$CHATWOOT_CONTAINER" bundle exec rails runner "$SEND_EMAIL_CMD" 2>&1 | grep -q "Email enviado"; then
            print_success "Email de confirmação enviado para ${CHATWOOT_ADMIN_EMAIL}"
        else
            print_warning "Não foi possível enviar email de confirmação."
            echo -e "  ${YELLOW}⚠️  Verifique se os registros DNS (DKIM, SPF, DMARC) estão configurados no Resend${RESET}"
            echo -e "  ${DIM}O usuário já está confirmado e pode fazer login normalmente.${RESET}"
        fi
        
        print_success "Chatwoot configurado com sucesso!"
        echo -e ""
        echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
        echo -e "${BOLD}${GREEN}   CREDENCIAIS DE ACESSO - CHATWOOT${RESET}"
        echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
        echo -e "  ${WHITE}URL:${RESET} https://${CHATWOOT_DOMAIN}/app/login"
        echo -e "  ${WHITE}Email:${RESET} ${CHATWOOT_ADMIN_EMAIL}"
        echo -e "  ${WHITE}Senha:${RESET} ${ADMIN_PASSWORD}"
        echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
        echo -e "  ${YELLOW}⚠️  SALVE ESTAS CREDENCIAIS AGORA!${RESET}"
        echo -e ""
    else
        print_warning "Erro ao criar Account. Execute manualmente:"
        echo -e "  ${DIM}docker exec -i \$(docker ps -q -f name=chatwoot_rails) -e REDIS_URL=\"redis://:${REDIS_PASSWORD}@redis_redis:6379\" bundle exec rails runner 'a = Account.create!(name: \"${ACCOUNT_NAME}\"); AccountUser.create!(account: a, user: User.first, role: :administrator)'${RESET}"
    fi
}

print_summary() {
    # Validação dos Serviços
    print_step "VALIDANDO SERVIÇOS (DOCKER SWARM)"
    echo -e "${CYAN}Verificando status dos serviços...${RESET}"
    docker service ls --format "table {{.Name}}\t{{.Replicas}}\t{{.Image}}" || echo -e "${YELLOW}Não foi possível listar os serviços (Docker pode estar ocupado).${RESET}"
    echo ""

    # Resumo Final
    print_step "SETUP CONCLUÍDO!"
    if [ "$IS_AWS" = true ]; then
        echo -e "${GREEN}✅ Infraestrutura AWS (Swarm) implantada!${RESET}"
    else
        echo -e "${GREEN}✅ Infraestrutura Google Cloud (Swarm) implantada!${RESET}"
    fi
    echo ""
    echo -e "${BOLD}${CYAN}Acesse seus serviços:${RESET}"
    echo -e "   ${ARROW} Portainer: https://${PORTAINER_DOMAIN}"
    echo -e "   ${ARROW} N8N Editor: https://${N8N_EDITOR_DOMAIN}"
    echo -e "   ${ARROW} N8N Webhook: https://${N8N_WEBHOOK_DOMAIN}"
    echo -e "   ${ARROW} RabbitMQ Panel: https://${RABBITMQ_DOMAIN}"
    echo -e "   ${ARROW} Evolution API: https://${EVOLUTION_DOMAIN}"
    echo -e "   ${ARROW} Evolution Manager: https://${EVOLUTION_DOMAIN}/manager"
    echo -e "   ${ARROW} Chatwoot: https://${CHATWOOT_DOMAIN}"
    
    if [ "$ENABLE_DIFY" = true ]; then
        echo -e "   ${ARROW} Dify Web: https://${DIFY_WEB_DOMAIN}"
        echo -e "   ${ARROW} Dify API: https://${DIFY_API_DOMAIN}"
    fi

    if [ "$ENABLE_OPENCLAW" = true ]; then
        echo -e "   ${ARROW} OpenClaw: https://${OPENCLAW_DOMAIN}"
    fi

    if [ "$ENABLE_POSTIZ" = true ]; then
        echo -e "   ${ARROW} Postiz:   https://${POSTIZ_DOMAIN}"
        echo -e "   ${ARROW} Postiz Temporal UI: https://${POSTIZ_TEMPORAL_DOMAIN}"
    fi

    if [ "$ENABLE_PROMETHEUS" = true ]; then
        echo -e "   ${ARROW} Prometheus:   https://${PROMETHEUS_DOMAIN}"
        echo -e "   ${ARROW} Grafana:       https://${GRAFANA_DOMAIN}"
        echo -e "   ${ARROW} Node Exporter: (modo global — sem UI)"
    fi

    if [ "$ENABLE_OPEN_DESIGN" = true ]; then
        echo -e "   ${ARROW} Open Design:   https://${OPEN_DESIGN_DOMAIN}"
    fi

    if [ "$ENABLE_METABASE" = true ]; then
        echo -e "   ${ARROW} Metabase:       https://${METABASE_DOMAIN}"
    fi

    if [ "$ENABLE_HERMES" = true ]; then
        echo -e "   ${ARROW} Hermes Gateway:   https://${HERMES_DOMAIN}"
        echo -e "   ${ARROW} Hermes Dashboard: https://${HERMES_DASHBOARD_DOMAIN}"
    fi

    echo ""
    echo -e "${YELLOW}⚠️  ATENÇÃO: Você tem 5 MINUTOS para criar a senha de admin no Portainer!${RESET}"
    echo -e "   Acesse agora: https://${PORTAINER_DOMAIN}"
    echo ""
    echo -e "${BOLD}${MAGENTA}🔒 CREDENCIAIS GERADAS (SALVE AGORA!):${RESET}"
    echo -e "   ${WHITE}Postgres Password:${RESET} ${POSTGRES_PASSWORD}"
    echo -e "   ${WHITE}Redis Password:${RESET} ${REDIS_PASSWORD}"
    echo -e "   ${WHITE}RabbitMQ User/Pass:${RESET} ${RABBITMQ_USER} / ${RABBITMQ_PASSWORD}"
    echo -e "   ${WHITE}N8N Encryption Key:${RESET} ${N8N_ENCRYPTION_KEY}"
    echo -e "   ${WHITE}Evolution Global API Key:${RESET} ${EVOLUTION_API_KEY}"
    echo -e "   ${WHITE}Chatwoot Secret Key:${RESET} ${CHATWOOT_SECRET_KEY}"
    echo -e "   ${WHITE}Chatwoot Admin Email:${RESET} ${CHATWOOT_ADMIN_EMAIL}"
    if [ -n "$CHATWOOT_ADMIN_PASSWORD" ]; then
        echo -e "   ${WHITE}Chatwoot Admin Password:${RESET} ${CHATWOOT_ADMIN_PASSWORD}"
    fi
    echo ""
    echo -e "${BOLD}${YELLOW}📧 CONFIGURAÇÃO RESEND (CHATWOOT):${RESET}"
    echo -e "   ${YELLOW}⚠️  IMPORTANTE: Configure os registros DNS no Resend:${RESET}"
    echo -e "   ${ARROW} Acesse: https://resend.com/domains"
    echo -e "   ${ARROW} Configure DKIM, SPF e DMARC para o domínio: ${CHATWOOT_ADMIN_EMAIL#*@}"
    echo -e "   ${DIM}Sem essa configuração, os emails do Chatwoot não serão entregues!${RESET}"
    
    if [ "$ENABLE_DIFY" = true ]; then
        echo -e "   ${WHITE}Dify Secret Key:${RESET} ${DIFY_SECRET_KEY}"
        echo -e "   ${WHITE}Dify Inner API Key (Plugin Daemon):${RESET} ${DIFY_INNER_API_KEY}"
    else
        echo -e "${DIM}Dify não foi instalado.${RESET}"
    fi

    # Credenciais OpenClaw
    print_openclaw_summary

    # Credenciais / acesso Postiz
    if [ "$ENABLE_POSTIZ" = true ]; then
        print_postiz_summary
    fi

    # Credenciais / acesso Prometheus (inclui Grafana e Node Exporter)
    print_prometheus_summary

    # Credenciais / acesso Open Design
    print_open_design_summary

    # Credenciais / acesso Metabase
    print_metabase_summary

    # Credenciais / acesso Hermes Agent
    print_hermes_summary

    echo ""
    echo -e "${BOLD}${CYAN}📋 PRÓXIMOS PASSOS - CHATWOOT:${RESET}"
    echo -e "   ${ARROW} 1. Acesse https://${CHATWOOT_DOMAIN} e faça login com as credenciais acima"
    echo -e "   ${ARROW} 2. Configure seu primeiro Inbox em Settings → Inboxes → Add Inbox"
    echo -e "   ${ARROW} 3. (Opcional) Reabilite o healthcheck no arquivo 19.chatwoot.yaml após validar que tudo funciona"
    echo -e "   ${DIM}Nota: As migrações e a Account já foram criadas automaticamente${RESET}"
    echo ""
}
