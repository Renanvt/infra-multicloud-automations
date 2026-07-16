#!/bin/bash

# =============================================================================
# Postiz2 Module
# Segunda instância do Postiz para gerenciar contas adicionais de redes sociais
# Stack independente com Redis e Temporal próprios
# =============================================================================

setup_postiz2_vars() {
    if [ "$ENABLE_POSTIZ2" != true ]; then return; fi

    print_banner
    print_step "CONFIGURAÇÕES POSTIZ 2"

    echo -e "  ${DIM}O Postiz 2 é uma segunda instância independente do Postiz.${RESET}"
    echo -e "  ${DIM}Útil para gerenciar contas de redes sociais separadas.${RESET}"
    echo -e ""

    confirm_input "${CYAN}🌐 Domínio Postiz 2 (ex: postiz2.meudominio.com): ${RESET}" \
        "Postiz 2 será:" POSTIZ2_DOMAIN

    # JWT_SECRET gerado automaticamente
    POSTIZ2_JWT_SECRET=$(openssl rand -hex 32)
    print_success "JWT Secret gerado automaticamente"

    export POSTIZ2_DOMAIN POSTIZ2_JWT_SECRET
}

generate_postiz2_yaml() {
    if [ "$ENABLE_POSTIZ2" != true ]; then return; fi

    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/postiz2"

    cat <<EOF > 28.postiz2.yaml
version: "3.8"

services:
  postiz2:
    image: ghcr.io/gitroomhq/postiz-app:latest
    environment:
      NODE_ENV: "production"
      TZ: "America/Sao_Paulo"
      MAIN_URL: "https://${POSTIZ2_DOMAIN}"
      FRONTEND_URL: "https://${POSTIZ2_DOMAIN}"
      NEXT_PUBLIC_BACKEND_URL: "https://${POSTIZ2_DOMAIN}/api"
      BACKEND_INTERNAL_URL: "http://postiz2:5000"
      JWT_SECRET: "${POSTIZ2_JWT_SECRET}"
      DATABASE_URL: "postgresql://postgres:${POSTGRES_PASSWORD}@postgres_postgres:5432/postiz2"
      REDIS_URL: "redis://:${REDIS_PASSWORD}@postiz2_redis:6379"
      TEMPORAL_ADDRESS: "postiz2_temporal:7233"
      TEMPORAL_NAMESPACE: "default"
      IS_GENERAL: "true"
      DISABLE_REGISTRATION: "false"
      RUN_CRON: "true"
      STORAGE_PROVIDER: "local"
      UPLOAD_DIRECTORY: "/uploads"
      NEXT_PUBLIC_UPLOAD_DIRECTORY: "/uploads"
      API_LIMIT: "30"
      NX_ADD_PLUGINS: "false"
      TRUST_PROXY: "true"

      # Redes sociais — preencha conforme necessário
      FACEBOOK_APP_ID: ""
      FACEBOOK_APP_SECRET: ""
      INSTAGRAM_APP_ID: ""
      INSTAGRAM_APP_SECRET: ""
      YOUTUBE_CLIENT_ID: ""
      YOUTUBE_CLIENT_SECRET: ""
      PINTEREST_CLIENT_ID: ""
      PINTEREST_CLIENT_SECRET: ""
      THREADS_APP_ID: ""
      THREADS_APP_SECRET: ""
      OPENAI_API_KEY: ""

    volumes:
      - postiz2_uploads:/uploads
      - postiz2_config:/config
    networks:
      - network_swarm_public
      - network_postiz2_internal
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
          cpus: "1.50"
          memory: 2048M
      restart_policy:
        condition: on-failure
        delay: 30s
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
        traefik.http.routers.postiz2.rule: "Host(\`${POSTIZ2_DOMAIN}\`)"
        traefik.http.routers.postiz2.entrypoints: "websecure"
        traefik.http.routers.postiz2.tls.certresolver: "letsencryptresolver"
        traefik.http.routers.postiz2.service: "postiz2"
        traefik.http.services.postiz2.loadbalancer.server.port: "5000"
        traefik.http.services.postiz2.loadbalancer.passHostHeader: "true"
    healthcheck:
      test: ["CMD", "node", "-e", "const r=require('http').get('http://localhost:5000/',res=>process.exit(res.statusCode<500?0:1));r.on('error',()=>process.exit(1));r.setTimeout(4000,()=>{r.destroy();process.exit(1)})"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 180s

  postiz2_redis:
    image: redis:7-alpine
    command:
      - redis-server
      - --appendonly
      - "yes"
      - --requirepass
      - "${REDIS_PASSWORD}"
    volumes:
      - postiz2_redis:/data
    networks:
      - network_postiz2_internal
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "0.50"
          memory: 512M
      restart_policy:
        condition: on-failure
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a '${REDIS_PASSWORD}' ping | grep PONG"]
      interval: 10s
      timeout: 5s
      retries: 10

  postiz2_temporal_elasticsearch:
    image: elasticsearch:7.17.27
    environment:
      TZ: "America/Sao_Paulo"
      discovery.type: "single-node"
      ES_JAVA_OPTS: "-Xms256m -Xmx256m"
      xpack.security.enabled: "false"
      cluster.routing.allocation.disk.threshold_enabled: "true"
      cluster.routing.allocation.disk.watermark.low: "512mb"
      cluster.routing.allocation.disk.watermark.high: "256mb"
      cluster.routing.allocation.disk.watermark.flood_stage: "128mb"
    volumes:
      - postiz2_elasticsearch:/usr/share/elasticsearch/data
    networks:
      - network_postiz2_internal
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        reservations:
          memory: 384M
        limits:
          cpus: "0.75"
          memory: 768M
      restart_policy:
        condition: on-failure
        delay: 10s
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS 'http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s' || exit 1"]
      interval: 10s
      timeout: 10s
      retries: 10
      start_period: 60s

  postiz2_temporal:
    image: temporalio/auto-setup:1.28.1
    environment:
      TZ: "America/Sao_Paulo"
      DB: "postgres12"
      DB_PORT: "5432"
      POSTGRES_USER: "postgres"
      POSTGRES_PWD: "${POSTGRES_PASSWORD}"
      POSTGRES_SEEDS: "postgres_postgres"
      DBNAME: "postiz2_temporal"
      VISIBILITY_DBNAME: "postiz2_temporal_visibility"
      DYNAMIC_CONFIG_FILE_PATH: "config/dynamicconfig/development-sql.yaml"
      ENABLE_ES: "true"
      ES_SEEDS: "postiz2_temporal_elasticsearch"
      ES_VERSION: "v7"
    volumes:
      - ${DATA_DIR}/dynamicconfig:/etc/temporal/config/dynamicconfig:ro
    networks:
      - network_swarm_public
      - network_postiz2_internal
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        reservations:
          memory: 384M
        limits:
          cpus: "0.75"
          memory: 768M
      restart_policy:
        condition: on-failure
        delay: 15s
        max_attempts: 10
        window: 120s

volumes:
  postiz2_uploads:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR}/uploads
  postiz2_config:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR}/config
  postiz2_redis:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR}/redis
  postiz2_elasticsearch:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR}/elasticsearch

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
  network_postiz2_internal:
    driver: overlay
    internal: true
    attachable: true
    name: network_postiz2_internal
EOF
}

deploy_postiz2() {
    if [ "$ENABLE_POSTIZ2" != true ]; then return; fi

    print_step "DEPLOY POSTIZ 2"

    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/postiz2"
    local POSTIZ1_DIR="/opt/infra/${BUSINESS_NAME}/postiz"

    # Criar diretórios
    print_info "Criando diretórios de dados do Postiz 2..."
    mkdir -p "${DATA_DIR}/uploads" \
             "${DATA_DIR}/config" \
             "${DATA_DIR}/redis" \
             "${DATA_DIR}/elasticsearch" \
             "${DATA_DIR}/dynamicconfig"

    # Copiar configuração dinâmica do Temporal do Postiz 1
    if [ -d "${POSTIZ1_DIR}/dynamicconfig" ]; then
        cp -a "${POSTIZ1_DIR}/dynamicconfig/." "${DATA_DIR}/dynamicconfig/"
        print_success "Configuração do Temporal copiada do Postiz 1"
    else
        # Criar config padrão se Postiz 1 não existir
        cat > "${DATA_DIR}/dynamicconfig/development-sql.yaml" <<'TEMPORAL_CFG'
# Temporal dynamic config — valores padrão para ambiente single-node
system.forceSearchAttributesCacheRefreshOnRead:
  - value: true
    constraints: {}
TEMPORAL_CFG
        print_success "Arquivo dynamicconfig/development-sql.yaml criado"
    fi

    # Ajustar permissões
    chown -R 1000:1000 "${DATA_DIR}/elasticsearch"
    chown -R 999:999 "${DATA_DIR}/redis"
    chmod -R 775 "${DATA_DIR}"
    print_success "Permissões aplicadas"

    # Criar banco postiz2 no Postgres
    print_info "Criando banco de dados 'postiz2'..."
    local PG_CONTAINER
    PG_CONTAINER=$(docker ps -q -f name=postgres_postgres | head -1)
    if [ -n "$PG_CONTAINER" ]; then
        if docker exec -i "$PG_CONTAINER" psql -U postgres -c "CREATE DATABASE postiz2;" >/dev/null 2>&1; then
            print_success "Banco 'postiz2' criado"
        else
            print_warning "Banco 'postiz2' já existe ou erro na criação"
        fi
    else
        print_warning "Container Postgres não encontrado — crie o banco manualmente:"
        echo -e "  ${DIM}docker exec -i \$(docker ps -q -f name=postgres_postgres) psql -U postgres -c 'CREATE DATABASE postiz2;'${RESET}"
    fi

    # Deploy da stack
    print_info "Deploying Postiz 2..."
    docker stack deploy --detach=true -c 28.postiz2.yaml postiz2 >/dev/null 2>&1
    print_success "Stack 'postiz2' enviada para o Swarm"
    print_info "Postiz 2 iniciando em background (Temporal + Elasticsearch levam ~2min)."
    print_info "Valide com: curl -I https://${POSTIZ2_DOMAIN}/api/auth/can-register"
}

print_postiz2_summary() {
    if [ "$ENABLE_POSTIZ2" != true ]; then return; fi

    echo -e ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${GREEN}   ACESSO — POSTIZ 2${RESET}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${WHITE}URL:${RESET}  https://${POSTIZ2_DOMAIN}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e ""
    echo -e "${BOLD}${CYAN}📋 SE O POSTIZ 2 RETORNAR 502 APÓS 2 MINUTOS:${RESET}"
    echo -e "  ${ARROW} docker service update --force postiz2_postiz2_temporal"
    echo -e "  ${ARROW} docker service update --force postiz2_postiz2"
    echo -e "  ${DIM}(o Temporal precisa que o Elasticsearch esteja healthy primeiro)${RESET}"
    echo -e ""
}
