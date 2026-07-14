#!/bin/bash

# =============================================================================
# Postiz Module
# Gerenciador de redes sociais com agendamento — self-hosted
# =============================================================================

setup_postiz_vars() {
    print_banner
    print_step "CONFIGURAÇÕES POSTIZ"

    echo -e "  ${YELLOW}⚠️  Antes de continuar, certifique-se de ter as API Keys das redes sociais${RESET}"
    echo -e "  ${DIM}que deseja conectar (Meta/Facebook, Instagram, YouTube, LinkedIn, etc.)${RESET}"
    echo -e "  ${DIM}Você pode pular qualquer rede social e configurar depois no painel do Postiz.${RESET}"
    echo -e ""

    confirm_input "${CYAN}🌐 Domínio Postiz (ex: postiz.meudominio.com): ${RESET}" \
        "Postiz será:" POSTIZ_DOMAIN

    confirm_input "${CYAN}🌐 Domínio Temporal UI (ex: postiz-temporal.meudominio.com): ${RESET}" \
        "Temporal UI será:" POSTIZ_TEMPORAL_DOMAIN

    # JWT_SECRET gerado automaticamente
    POSTIZ_JWT_SECRET=$(openssl rand -hex 32)
    print_success "JWT Secret gerado automaticamente"

    # Senha para Basic Auth do Temporal UI
    print_step "PROTEÇÃO DO TEMPORAL UI (Basic Auth)"
    echo -e "  ${DIM}O Temporal UI será protegido com usuário/senha via Traefik Basic Auth.${RESET}"
    confirm_input "${CYAN}👤 Usuário para o Temporal UI (padrão: admin): ${RESET}" \
        "Usuário Temporal UI:" POSTIZ_TEMPORAL_USER
    if [ -z "$POSTIZ_TEMPORAL_USER" ]; then POSTIZ_TEMPORAL_USER="admin"; fi

    confirm_input "${CYAN}🔑 Senha para o Temporal UI: ${RESET}" \
        "Senha Temporal UI:" POSTIZ_TEMPORAL_PASSWORD

    if command -v htpasswd >/dev/null 2>&1; then
        POSTIZ_TEMPORAL_HASH=$(htpasswd -nb "$POSTIZ_TEMPORAL_USER" "$POSTIZ_TEMPORAL_PASSWORD")
        print_success "Hash Basic Auth gerado"
    else
        print_info "htpasswd não encontrado — instalando apache2-utils..."
        apt-get install -y apache2-utils >/dev/null 2>&1 || true
        if command -v htpasswd >/dev/null 2>&1; then
            POSTIZ_TEMPORAL_HASH=$(htpasswd -nb "$POSTIZ_TEMPORAL_USER" "$POSTIZ_TEMPORAL_PASSWORD")
            print_success "Hash Basic Auth gerado"
        else
            print_warning "Não foi possível gerar o hash. Edite 22.postiz.yaml depois:"
            echo -e "  ${DIM}htpasswd -nb ${POSTIZ_TEMPORAL_USER} SUA_SENHA${RESET}"
            POSTIZ_TEMPORAL_HASH="admin:\$HASH_PENDENTE"
        fi
    fi

    export POSTIZ_DOMAIN POSTIZ_TEMPORAL_DOMAIN POSTIZ_JWT_SECRET
    export POSTIZ_TEMPORAL_USER POSTIZ_TEMPORAL_PASSWORD POSTIZ_TEMPORAL_HASH

    # ---- Redes Sociais -------------------------------------------------------
    print_step "CONFIGURAÇÃO DE REDES SOCIAIS (Enter para pular cada uma)"

    _ask_social "X (Twitter)"       "X_API_KEY"          "X_API_SECRET"
    _ask_social "LinkedIn"          "LINKEDIN_CLIENT_ID"  "LINKEDIN_CLIENT_SECRET"
    _ask_social "Reddit"            "REDDIT_CLIENT_ID"    "REDDIT_CLIENT_SECRET"
    _ask_social "Facebook"          "FACEBOOK_APP_ID"     "FACEBOOK_APP_SECRET"
    _ask_social "Instagram"         "INSTAGRAM_APP_ID"    "INSTAGRAM_APP_SECRET"
    _ask_social "YouTube"           "YOUTUBE_CLIENT_ID"   "YOUTUBE_CLIENT_SECRET"
    _ask_social "TikTok"            "TIKTOK_CLIENT_ID"    "TIKTOK_CLIENT_SECRET"
    _ask_social_discord
    _ask_social_slack
    _ask_social "Threads"           "THREADS_APP_ID"      "THREADS_APP_SECRET"

    # ---- OpenAI IA -----------------------------------------------------------
    echo -e ""
    read -p "$(echo -e "${CYAN}🤖 Deseja configurar a OpenAI API Key no Postiz? (s/n): ${RESET}")" \
        _OAI_OPT < /dev/tty || true
    if [[ "$_OAI_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
        read -p "$(echo -e "${CYAN}   OpenAI API Key (sk-...): ${RESET}")" \
            POSTIZ_OPENAI_API_KEY < /dev/tty || true
        print_success "OpenAI API Key configurada"
    else
        POSTIZ_OPENAI_API_KEY=""
    fi

    export POSTIZ_OPENAI_API_KEY

    # Inicializar variáveis não preenchidas como string vazia
    : "${X_API_KEY:=}"
    : "${X_API_SECRET:=}"
    : "${LINKEDIN_CLIENT_ID:=}"
    : "${LINKEDIN_CLIENT_SECRET:=}"
    : "${REDDIT_CLIENT_ID:=}"
    : "${REDDIT_CLIENT_SECRET:=}"
    : "${FACEBOOK_APP_ID:=}"
    : "${FACEBOOK_APP_SECRET:=}"
    : "${INSTAGRAM_APP_ID:=}"
    : "${INSTAGRAM_APP_SECRET:=}"
    : "${YOUTUBE_CLIENT_ID:=}"
    : "${YOUTUBE_CLIENT_SECRET:=}"
    : "${TIKTOK_CLIENT_ID:=}"
    : "${TIKTOK_CLIENT_SECRET:=}"
    : "${DISCORD_CLIENT_ID:=}"
    : "${DISCORD_CLIENT_SECRET:=}"
    : "${DISCORD_BOT_TOKEN_ID:=}"
    : "${SLACK_ID:=}"
    : "${SLACK_SECRET:=}"
    : "${SLACK_SIGNING_SECRET:=}"
    : "${THREADS_APP_ID:=}"
    : "${THREADS_APP_SECRET:=}"

    export X_API_KEY X_API_SECRET
    export LINKEDIN_CLIENT_ID LINKEDIN_CLIENT_SECRET
    export REDDIT_CLIENT_ID REDDIT_CLIENT_SECRET
    export FACEBOOK_APP_ID FACEBOOK_APP_SECRET
    export INSTAGRAM_APP_ID INSTAGRAM_APP_SECRET
    export YOUTUBE_CLIENT_ID YOUTUBE_CLIENT_SECRET
    export TIKTOK_CLIENT_ID TIKTOK_CLIENT_SECRET
    export DISCORD_CLIENT_ID DISCORD_CLIENT_SECRET DISCORD_BOT_TOKEN_ID
    export SLACK_ID SLACK_SECRET SLACK_SIGNING_SECRET
    export THREADS_APP_ID THREADS_APP_SECRET
}

# ---------------------------------------------------------------------------
# Helper: pergunta par de credenciais para uma rede social (ID + Secret)
# ---------------------------------------------------------------------------
_ask_social() {
    local LABEL="$1"
    local VAR_ID="$2"
    local VAR_SECRET="$3"

    read -p "$(echo -e "${CYAN}📱 Deseja configurar ${BOLD}${LABEL}${RESET}${CYAN}? (s/n): ${RESET}")" \
        _OPT < /dev/tty || true

    if [[ "$_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
        read -p "$(echo -e "${CYAN}   ${LABEL} App ID / Client ID: ${RESET}")" _VAL_ID < /dev/tty || true
        read -p "$(echo -e "${CYAN}   ${LABEL} App Secret / Client Secret: ${RESET}")" _VAL_SECRET < /dev/tty || true
        eval "${VAR_ID}=\"${_VAL_ID}\""
        eval "${VAR_SECRET}=\"${_VAL_SECRET}\""
        print_success "${LABEL} configurado"
    else
        eval "${VAR_ID}=\"\""
        eval "${VAR_SECRET}=\"\""
    fi

    export "${VAR_ID}" "${VAR_SECRET}"
}

# ---------------------------------------------------------------------------
# Helper: Discord — Client ID + Client Secret + Bot Token
# ---------------------------------------------------------------------------
_ask_social_discord() {
    read -p "$(echo -e "${CYAN}📱 Deseja configurar ${BOLD}Discord${RESET}${CYAN}? (s/n): ${RESET}")" \
        _OPT < /dev/tty || true

    if [[ "$_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
        read -p "$(echo -e "${CYAN}   Discord Client ID: ${RESET}")"       DISCORD_CLIENT_ID   < /dev/tty || true
        read -p "$(echo -e "${CYAN}   Discord Client Secret: ${RESET}")"   DISCORD_CLIENT_SECRET < /dev/tty || true
        read -p "$(echo -e "${CYAN}   Discord Bot Token: ${RESET}")"       DISCORD_BOT_TOKEN_ID  < /dev/tty || true
        print_success "Discord configurado"
    else
        DISCORD_CLIENT_ID=""
        DISCORD_CLIENT_SECRET=""
        DISCORD_BOT_TOKEN_ID=""
    fi

    export DISCORD_CLIENT_ID DISCORD_CLIENT_SECRET DISCORD_BOT_TOKEN_ID
}

# ---------------------------------------------------------------------------
# Helper: Slack — Slack ID + Secret + Signing Secret
# ---------------------------------------------------------------------------
_ask_social_slack() {
    read -p "$(echo -e "${CYAN}📱 Deseja configurar ${BOLD}Slack${RESET}${CYAN}? (s/n): ${RESET}")" \
        _OPT < /dev/tty || true

    if [[ "$_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
        read -p "$(echo -e "${CYAN}   Slack App ID (SLACK_ID): ${RESET}")"           SLACK_ID             < /dev/tty || true
        read -p "$(echo -e "${CYAN}   Slack Secret (SLACK_SECRET): ${RESET}")"       SLACK_SECRET         < /dev/tty || true
        read -p "$(echo -e "${CYAN}   Slack Signing Secret: ${RESET}")"              SLACK_SIGNING_SECRET < /dev/tty || true
        print_success "Slack configurado"
    else
        SLACK_ID=""
        SLACK_SECRET=""
        SLACK_SIGNING_SECRET=""
    fi

    export SLACK_ID SLACK_SECRET SLACK_SIGNING_SECRET
}

generate_postiz_yaml() {
    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/postiz"
    # Converter $ para $$ no hash para o Traefik YAML
    local _PT_HASH
    _PT_HASH=$(printf '%s' "${POSTIZ_TEMPORAL_HASH:-}" | sed 's/\$/\$\$/g')

    cat <<EOF > 22.postiz.yaml
version: "3.7"

services:

  # ─── Postiz (App principal) ───────────────────────────────────────────────
  postiz:
    image: ghcr.io/gitroomhq/postiz-app:latest

    environment:
      NODE_ENV: "production"
      TZ: "America/Sao_Paulo"
      MAIN_URL: "https://${POSTIZ_DOMAIN}"
      FRONTEND_URL: "https://${POSTIZ_DOMAIN}"
      NEXT_PUBLIC_BACKEND_URL: "https://${POSTIZ_DOMAIN}/api"
      BACKEND_INTERNAL_URL: "http://postiz:5000"
      JWT_SECRET: "${POSTIZ_JWT_SECRET}"

      DATABASE_URL: "postgresql://postgres:${POSTGRES_PASSWORD}@postgres_postgres:5432/postiz"
      REDIS_URL: "redis://:${REDIS_PASSWORD}@redis_redis:6379"

      TEMPORAL_ADDRESS: "temporal-internal:7233"

      IS_GENERAL: "true"
      DISABLE_REGISTRATION: "false"
      RUN_CRON: "true"

      STORAGE_PROVIDER: "local"
      UPLOAD_DIRECTORY: "/uploads"
      NEXT_PUBLIC_UPLOAD_DIRECTORY: "/uploads"

      # Redes sociais
      X_URL: "${X_URL:-}"
      X_API_KEY: "${X_API_KEY}"
      X_API_SECRET: "${X_API_SECRET}"
      LINKEDIN_CLIENT_ID: "${LINKEDIN_CLIENT_ID}"
      LINKEDIN_CLIENT_SECRET: "${LINKEDIN_CLIENT_SECRET}"
      REDDIT_CLIENT_ID: "${REDDIT_CLIENT_ID}"
      REDDIT_CLIENT_SECRET: "${REDDIT_CLIENT_SECRET}"
      GITHUB_CLIENT_ID: "${GITHUB_CLIENT_ID:-}"
      GITHUB_CLIENT_SECRET: "${GITHUB_CLIENT_SECRET:-}"
      BEEHIIVE_API_KEY: "${BEEHIIVE_API_KEY:-}"
      BEEHIIVE_PUBLICATION_ID: "${BEEHIIVE_PUBLICATION_ID:-}"
      FACEBOOK_APP_ID: "${FACEBOOK_APP_ID}"
      FACEBOOK_APP_SECRET: "${FACEBOOK_APP_SECRET}"
      INSTAGRAM_APP_ID: "${INSTAGRAM_APP_ID}"
      INSTAGRAM_APP_SECRET: "${INSTAGRAM_APP_SECRET}"
      YOUTUBE_CLIENT_ID: "${YOUTUBE_CLIENT_ID}"
      YOUTUBE_CLIENT_SECRET: "${YOUTUBE_CLIENT_SECRET}"
      TIKTOK_CLIENT_ID: "${TIKTOK_CLIENT_ID}"
      TIKTOK_CLIENT_SECRET: "${TIKTOK_CLIENT_SECRET}"
      PINTEREST_CLIENT_ID: "${PINTEREST_CLIENT_ID:-}"
      PINTEREST_CLIENT_SECRET: "${PINTEREST_CLIENT_SECRET:-}"
      DRIBBBLE_CLIENT_ID: "${DRIBBBLE_CLIENT_ID:-}"
      DRIBBBLE_CLIENT_SECRET: "${DRIBBBLE_CLIENT_SECRET:-}"
      DISCORD_CLIENT_ID: "${DISCORD_CLIENT_ID}"
      DISCORD_CLIENT_SECRET: "${DISCORD_CLIENT_SECRET}"
      DISCORD_BOT_TOKEN_ID: "${DISCORD_BOT_TOKEN_ID}"
      SLACK_ID: "${SLACK_ID}"
      SLACK_SECRET: "${SLACK_SECRET}"
      SLACK_SIGNING_SECRET: "${SLACK_SIGNING_SECRET}"
      MASTODON_URL: "https://mastodon.social"
      MASTODON_CLIENT_ID: "${MASTODON_CLIENT_ID:-}"
      MASTODON_CLIENT_SECRET: "${MASTODON_CLIENT_SECRET:-}"
      THREADS_APP_ID: "${THREADS_APP_ID}"
      THREADS_APP_SECRET: "${THREADS_APP_SECRET}"

      OPENAI_API_KEY: "${POSTIZ_OPENAI_API_KEY}"
      NEXT_PUBLIC_DISCORD_SUPPORT: ""
      NEXT_PUBLIC_POLOTNO: ""

      API_LIMIT: "30"
      NX_ADD_PLUGINS: "false"

      # Payment / Stripe (opcional)
      FEE_AMOUNT: "0.05"
      STRIPE_PUBLISHABLE_KEY: ""
      STRIPE_SECRET_KEY: ""
      STRIPE_SIGNING_KEY: ""
      STRIPE_SIGNING_KEY_CONNECT: ""
      TRUST_PROXY: "true"

    volumes:
      - postiz_uploads:/uploads
      - postiz_config:/config

    networks:
      - network_swarm_public
      - network_postiz_internal

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        reservations:
          cpus: "0.25"
          memory: 512M
        limits:
          cpus: "2.0"
          memory: 4096M
      restart_policy:
        condition: on-failure
        delay: 60s
        max_attempts: 10
        window: 120s
      update_config:
        parallelism: 1
        delay: 30s
        order: stop-first
        failure_action: rollback
      labels:
        traefik.enable: "true"
        traefik.swarm.network: "network_swarm_public"
        traefik.http.routers.postiz.rule: "Host(\`${POSTIZ_DOMAIN}\`)"
        traefik.http.routers.postiz.entrypoints: "websecure"
        traefik.http.routers.postiz.priority: "1"
        traefik.http.routers.postiz.tls.certresolver: "letsencryptresolver"
        traefik.http.routers.postiz.service: "postiz"
        traefik.http.routers.postiz.middlewares: "postiz-headers"
        traefik.http.services.postiz.loadbalancer.server.port: "5000"
        traefik.http.services.postiz.loadbalancer.passHostHeader: "true"
        traefik.http.middlewares.postiz-headers.headers.customrequestheaders.X-Forwarded-Proto: "https"
        traefik.http.middlewares.postiz-headers.headers.customrequestheaders.X-Forwarded-Port: "443"

    healthcheck:
      test: ["CMD", "node", "-e", "const r=require('http').get('http://localhost:5000/',res=>process.exit(res.statusCode<500?0:1));r.on('error',()=>process.exit(1));r.setTimeout(4000,()=>{r.destroy();process.exit(1)})"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 180s

  # ─── Temporal Elasticsearch ───────────────────────────────────────────────
  postiz_temporal_elasticsearch:
    image: elasticsearch:7.17.27

    environment:
      TZ: "America/Sao_Paulo"
      cluster.routing.allocation.disk.threshold_enabled: "true"
      cluster.routing.allocation.disk.watermark.low: "512mb"
      cluster.routing.allocation.disk.watermark.high: "256mb"
      cluster.routing.allocation.disk.watermark.flood_stage: "128mb"
      discovery.type: "single-node"
      ES_JAVA_OPTS: "-Xms256m -Xmx256m"
      xpack.security.enabled: "false"

    volumes:
      - postiz_elasticsearch:/usr/share/elasticsearch/data

    networks:
      - network_postiz_internal

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        reservations:
          cpus: "0.25"
          memory: 512M
        limits:
          cpus: "1.0"
          memory: 1024M
      restart_policy:
        condition: on-failure
        delay: 10s
        max_attempts: 5
        window: 120s
      labels:
        traefik.enable: "false"

    healthcheck:
      test: ["CMD-SHELL", "curl -fsS 'http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s' || exit 1"]
      interval: 10s
      timeout: 10s
      retries: 10
      start_period: 60s

  # ─── Temporal ─────────────────────────────────────────────────────────────
  postiz_temporal:
    image: temporalio/auto-setup:1.28.1

    environment:
      TZ: "America/Sao_Paulo"
      DB: "postgres12"
      DB_PORT: "5432"
      POSTGRES_USER: "postgres"
      POSTGRES_PWD: "${POSTGRES_PASSWORD}"
      POSTGRES_SEEDS: "postgres_postgres"
      DYNAMIC_CONFIG_FILE_PATH: "config/dynamicconfig/development-sql.yaml"
      ENABLE_ES: "true"
      ES_SEEDS: "postiz_temporal_elasticsearch"
      ES_VERSION: "v7"
      TEMPORAL_NAMESPACE: "default"

    volumes:
      - ${DATA_DIR}/dynamicconfig:/etc/temporal/config/dynamicconfig

    networks:
      network_swarm_public:
      network_postiz_internal:
        aliases:
          - temporal-internal

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        reservations:
          cpus: "0.25"
          memory: 512M
        limits:
          cpus: "1.0"
          memory: 1024M
      restart_policy:
        condition: on-failure
        delay: 15s
        max_attempts: 5
        window: 120s
      labels:
        traefik.enable: "false"

  # ─── Temporal UI ──────────────────────────────────────────────────────────
  postiz_temporal_ui:
    image: temporalio/ui:2.34.0

    environment:
      TZ: "America/Sao_Paulo"
      TEMPORAL_ADDRESS: "temporal-internal:7233"
      TEMPORAL_CORS_ORIGINS: "https://${POSTIZ_TEMPORAL_DOMAIN}"
      TEMPORAL_CSRF_COOKIE_INSECURE: "true"
      TEMPORAL_AUTH_ENABLED: "false"

    networks:
      - network_swarm_public
      - network_postiz_internal

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        reservations:
          cpus: "0.10"
          memory: 128M
        limits:
          cpus: "0.50"
          memory: 512M
      restart_policy:
        condition: on-failure
        delay: 10s
        max_attempts: 5
        window: 120s
      labels:
        traefik.enable: "true"
        traefik.swarm.network: "network_swarm_public"
        traefik.http.routers.postiz-temporal.rule: "Host(\`${POSTIZ_TEMPORAL_DOMAIN}\`)"
        traefik.http.routers.postiz-temporal.entrypoints: "websecure"
        traefik.http.routers.postiz-temporal.priority: "1"
        traefik.http.routers.postiz-temporal.tls.certresolver: "letsencryptresolver"
        traefik.http.routers.postiz-temporal.service: "postiz_temporal_ui"
        traefik.http.routers.postiz-temporal.middlewares: "postiz-temporal-auth"
        traefik.http.middlewares.postiz-temporal-auth.basicauth.users: "${_PT_HASH}"
        traefik.http.services.postiz_temporal_ui.loadbalancer.server.port: "8080"
        traefik.http.services.postiz_temporal_ui.loadbalancer.passHostHeader: "true"

volumes:
  postiz_uploads:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR}/uploads

  postiz_config:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR}/config

  postiz_elasticsearch:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR}/elasticsearch

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public

  network_postiz_internal:
    driver: overlay
    internal: true
    attachable: true
    name: network_postiz_internal
EOF
}

deploy_postiz() {
    print_step "DEPLOY POSTIZ"

    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/postiz"

    print_info "Criando diretórios de dados do Postiz..."
    mkdir -p "${DATA_DIR}/uploads"
    mkdir -p "${DATA_DIR}/config"
    mkdir -p "${DATA_DIR}/elasticsearch"
    mkdir -p "${DATA_DIR}/dynamicconfig"

    if [ ! -f "${DATA_DIR}/dynamicconfig/development-sql.yaml" ]; then
        cat > "${DATA_DIR}/dynamicconfig/development-sql.yaml" <<'TEMPORAL_CFG'
# Temporal dynamic config — valores padrão para ambiente single-node
system.forceSearchAttributesCacheRefreshOnRead:
  - value: true
    constraints: {}
TEMPORAL_CFG
        print_success "Arquivo dynamicconfig/development-sql.yaml criado"
    fi

    chown -R 1000:1000 "${DATA_DIR}/elasticsearch"
    chmod -R 755 "${DATA_DIR}/uploads" "${DATA_DIR}/config" "${DATA_DIR}/dynamicconfig"
    print_success "Permissões aplicadas"

    print_info "Deploying Postiz..."
    docker stack deploy --detach=true -c 22.postiz.yaml postiz >/dev/null 2>&1
    print_success "Stack 'postiz' enviada para o Swarm"
    print_info "Postiz iniciando em background (Temporal + Elasticsearch levam ~2min para ficar prontos)."
}

_verify_postiz_running() {
    print_step "VERIFICAÇÃO POSTIZ"

    local HEALTHY=false
    local POSTIZ_CONTAINER=""

    for i in {1..10}; do
        POSTIZ_CONTAINER=$(docker ps -q -f name=postiz_postiz)
        if [ -n "$POSTIZ_CONTAINER" ]; then
            if docker exec "$POSTIZ_CONTAINER" \
                node -e "const r=require('http').get('http://localhost:5000/',res=>process.exit(res.statusCode<500?0:1));r.on('error',()=>process.exit(1));r.setTimeout(4000,()=>{r.destroy();process.exit(1)})" \
                >/dev/null 2>&1; then
                HEALTHY=true
                break
            fi
        fi
        echo -ne "  ${INFO} ${CYAN}Verificando Postiz... (${i}/10)${RESET}\r"
        sleep 10
    done

    echo ""

    if [ "$HEALTHY" = true ]; then
        print_success "Postiz está ${BOLD}rodando e saudável${RESET} ✔"
        echo -e ""
        docker service ls --filter name=postiz \
            --format "    {{.Name}}  replicas={{.Replicas}}" 2>/dev/null || true
    else
        print_warning "Postiz ainda não respondeu ao healthcheck."
        echo -e "  ${ARROW} Ver logs:    ${DIM}docker service logs -f postiz_postiz${RESET}"
        echo -e "  ${ARROW} Status:      ${DIM}docker service ps postiz_postiz${RESET}"
        echo -e "  ${ARROW} Elasticsearch pode demorar até 2 minutos para ficar pronto."
        echo -e "  ${ARROW} Temporal depende do Elasticsearch — verifique os dois primeiro."
    fi
}

print_postiz_summary() {
    echo -e ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${GREEN}   ACESSO — POSTIZ${RESET}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${WHITE}URL:${RESET}               https://${POSTIZ_DOMAIN}"
    echo -e "  ${WHITE}Temporal UI:${RESET}       https://${POSTIZ_TEMPORAL_DOMAIN}"
    echo -e "  ${WHITE}Temporal usuário:${RESET}  ${POSTIZ_TEMPORAL_USER}"
    echo -e "  ${WHITE}Temporal senha:${RESET}    ${POSTIZ_TEMPORAL_PASSWORD}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${YELLOW}⚠️  Salve a senha do Temporal UI — não será exibida novamente!${RESET}"
    echo -e ""
    echo -e "${BOLD}${CYAN}📋 PRÓXIMOS PASSOS — POSTIZ:${RESET}"
    echo -e "  ${ARROW} 1. Acesse https://${POSTIZ_DOMAIN} e crie sua conta de administrador"
    echo -e "  ${ARROW} 2. Vá em ${BOLD}Settings → Social Platforms${RESET} para conectar as redes sociais"
    echo -e "  ${ARROW} 3. Redes sociais não configuradas agora podem ser adicionadas depois"
    echo -e "  ${DIM}     Edite 22.postiz.yaml e atualize: docker stack deploy -c 22.postiz.yaml postiz${RESET}"
    echo -e ""
}
