#!/bin/bash

deploy_services() {
    print_step "INICIANDO SERVIÇOS DE INFRAESTRUTURA"
    
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

    # 3. Criação do Banco N8N
    print_step "CONFIGURANDO BANCO DE DADOS N8N"
    print_info "Tentando conectar ao Postgres para criar o banco 'n8n'..."
    
    # Loop para encontrar o container ID do postgres (pode demorar um pouco no swarm)
    POSTGRES_CONTAINER=""
    for i in {1..10}; do
        POSTGRES_CONTAINER=$(docker ps -q -f name=postgres_postgres)
        if [ -n "$POSTGRES_CONTAINER" ]; then
            break
        fi
        sleep 2
    done

    if [ -n "$POSTGRES_CONTAINER" ]; then
        if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE n8n;" >/dev/null 2>&1; then
            print_success "Banco de dados 'n8n' criado com sucesso!"
        else
            print_warning "Banco de dados 'n8n' já existe ou erro na criação (verifique logs)."
        fi
        
        if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE evolution;" >/dev/null 2>&1; then
            print_success "Banco de dados 'evolution' criado com sucesso!"
        else
            print_warning "Banco de dados 'evolution' já existe ou erro na criação (verifique logs)."
        fi

        if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE chatwoot_production;" >/dev/null 2>&1; then
            print_success "Banco de dados 'chatwoot_production' criado com sucesso!"
        else
            print_warning "Banco de dados 'chatwoot_production' já existe ou erro na criação (verifique logs)."
        fi

        if [ "$ENABLE_DIFY" = true ]; then
            if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE dify;" >/dev/null 2>&1; then
                print_success "Banco de dados 'dify' criado com sucesso!"
            else
                print_warning "Banco de dados 'dify' já existe ou erro na criação (verifique logs)."
            fi
        fi
    else
        print_error "Não foi possível encontrar o container do Postgres. Crie os bancos 'n8n', 'evolution' e 'chatwoot' manualmente depois."
    fi

    # 4. Deploy Aplicações
    print_step "DEPLOY DAS APLICAÇÕES DE NEGÓCIO"
    
    # Criar volume externo para Evolution
    docker volume create evolution_v2_data >/dev/null
    
    print_info "Deploying N8N Editor..."
    docker stack deploy --detach=true -c 08.n8n-editor.yaml n8n_editor >/dev/null 2>&1
    print_info "Deploying N8N Worker..."
    docker stack deploy --detach=true -c 09.n8n-workers.yaml n8n_worker >/dev/null 2>&1
    print_info "Deploying N8N Webhook..."
    docker stack deploy --detach=true -c 10.n8n-webhooks.yaml n8n_webhook >/dev/null 2>&1
    print_info "Deploying Evolution V2..."
    docker stack deploy --detach=true -c 18.evolution_v2.yaml evolution_v2 >/dev/null 2>&1
    print_info "Deploying Chatwoot..."
    docker stack deploy --detach=true -c 19.chatwoot.yaml chatwoot >/dev/null 2>&1
    
    # Aguardar Chatwoot inicializar
    print_info "Aguardando Chatwoot inicializar (60s)..."
    sleep 60
    
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
}

configure_chatwoot() {
    print_step "CONFIGURANDO CHATWOOT (MIGRAÇÕES E ACCOUNT)"
    
    # Encontrar o container do Chatwoot Rails
    print_info "Localizando container do Chatwoot Rails..."
    CHATWOOT_CONTAINER=""
    for i in {1..15}; do
        CHATWOOT_CONTAINER=$(docker ps -q -f name=chatwoot_chatwoot_rails)
        if [ -n "$CHATWOOT_CONTAINER" ]; then
            break
        fi
        print_info "Aguardando container inicializar... (tentativa $i/15)"
        sleep 4
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
    echo ""
    echo -e "${BOLD}${CYAN}📋 PRÓXIMOS PASSOS - CHATWOOT:${RESET}"
    echo -e "   ${ARROW} 1. Acesse https://${CHATWOOT_DOMAIN} e faça login com as credenciais acima"
    echo -e "   ${ARROW} 2. Configure seu primeiro Inbox em Settings → Inboxes → Add Inbox"
    echo -e "   ${ARROW} 3. (Opcional) Reabilite o healthcheck no arquivo 19.chatwoot.yaml após validar que tudo funciona"
    echo -e "   ${DIM}Nota: As migrações e a Account já foram criadas automaticamente${RESET}"
    echo ""
}
