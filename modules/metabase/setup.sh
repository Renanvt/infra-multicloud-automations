#!/bin/bash

# =============================================================================
# Metabase Module
# BI e análise de dados self-hosted — banco de dados via PostgreSQL compartilhado
# =============================================================================

setup_metabase_vars() {
    print_banner
    print_step "CONFIGURAÇÕES METABASE"

    confirm_input "${CYAN}🌐 Domínio Metabase (ex: metabase.meudominio.com): ${RESET}" \
        "Metabase será:" METABASE_DOMAIN

    export METABASE_DOMAIN
}

generate_metabase_yaml() {
    cat <<EOF > 27.metabase.yaml
version: "3.7"

services:

  # ─── Metabase ─────────────────────────────────────────────────────────────
  metabase:
    image: metabase/metabase:latest

    environment:
      MB_DB_TYPE: "postgres"
      MB_DB_DBNAME: "metabase"
      MB_DB_PORT: "5432"
      MB_DB_USER: "postgres"
      MB_DB_PASS: "${POSTGRES_PASSWORD}"
      MB_DB_HOST: "postgres_postgres"
      MB_SITE_URL: "https://${METABASE_DOMAIN}"
      JAVA_TIMEZONE: "America/Sao_Paulo"

    networks:
      - network_swarm_public

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        reservations:
          cpus: "0.50"
          memory: 512M
        limits:
          cpus: "2.0"
          memory: 2048M
      restart_policy:
        condition: on-failure
        delay: 30s
        max_attempts: 5
        window: 120s
      labels:
        traefik.enable: "true"
        traefik.swarm.network: "network_swarm_public"
        traefik.http.routers.metabase.rule: "Host(\`${METABASE_DOMAIN}\`)"
        traefik.http.routers.metabase.entrypoints: "websecure"
        traefik.http.routers.metabase.priority: "1"
        traefik.http.routers.metabase.tls.certresolver: "letsencryptresolver"
        traefik.http.routers.metabase.service: "metabase"
        traefik.http.services.metabase.loadbalancer.server.port: "3000"

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF
}

deploy_metabase() {
    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/metabase"

    print_step "DEPLOY METABASE"

    # Criar diretório de dados
    print_info "Criando diretório ${DATA_DIR}/data..."
    mkdir -p "${DATA_DIR}/data"
    print_success "Diretório criado"

    # Banco 'metabase' já criado em deploy_services (bloco central de bancos)

    # Deploy da stack
    print_info "Deploying Metabase..."
    docker stack deploy --detach=true -c 27.metabase.yaml metabase >/dev/null 2>&1
    print_success "Stack 'metabase' enviada para o Swarm"

    # Metabase demora mais para inicializar (JVM + migrações de banco)
    print_info "Aguardando Metabase inicializar (60s — JVM + migrações de banco)..."
    sleep 60

    _verify_metabase_running
}

_verify_metabase_running() {
    print_step "VERIFICAÇÃO METABASE"

    local HEALTHY=false
    local MB_CONTAINER=""

    for i in {1..12}; do
        MB_CONTAINER=$(docker ps -q -f name=metabase_metabase)
        if [ -n "$MB_CONTAINER" ]; then
            if docker exec "$MB_CONTAINER" \
                wget -qO- http://localhost:3000/api/health >/dev/null 2>&1; then
                HEALTHY=true
                break
            fi
        fi
        echo -ne "  ${INFO} ${CYAN}Verificando Metabase... (${i}/12)${RESET}\r"
        sleep 10
    done

    echo ""

    if [ "$HEALTHY" = true ]; then
        print_success "Metabase está ${BOLD}rodando e saudável${RESET} ✔"
        docker service ls --filter name=metabase_metabase \
            --format "    {{.Name}}  replicas={{.Replicas}}" 2>/dev/null || true
    else
        print_warning "Metabase ainda não respondeu (JVM pode demorar até 3 min)."
        echo -e "  ${ARROW} Ver logs: ${DIM}docker service logs -f metabase_metabase${RESET}"
        echo -e "  ${ARROW} Status:   ${DIM}docker service ps metabase_metabase${RESET}"
        echo -e "  ${DIM}  Aguarde mais alguns minutos e acesse https://${METABASE_DOMAIN}${RESET}"
    fi
}

print_metabase_summary() {
    if [ "$ENABLE_METABASE" != true ]; then return; fi

    echo -e ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${GREEN}   ACESSO — METABASE${RESET}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${WHITE}URL:${RESET}  https://${METABASE_DOMAIN}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e ""
    echo -e "${BOLD}${CYAN}📋 PRÓXIMOS PASSOS — METABASE:${RESET}"
    echo -e "  ${ARROW} 1. Acesse https://${METABASE_DOMAIN}"
    echo -e "  ${ARROW} 2. Crie sua conta de administrador no assistente de setup"
    echo -e "  ${ARROW} 3. Conecte o banco de dados que deseja analisar"
    echo -e "  ${DIM}     (pode levar até 3 minutos para a primeira inicialização)${RESET}"
    echo -e ""
}
