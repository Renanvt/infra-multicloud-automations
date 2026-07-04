#!/bin/bash

# =============================================================================
# Grafana Module
# Dashboards e visualização de métricas — integra com Prometheus
# =============================================================================

setup_grafana_vars() {
    print_banner
    print_step "CONFIGURAÇÕES GRAFANA"

    confirm_input "${CYAN}🌐 Domínio Grafana (ex: grafana.meudominio.com): ${RESET}" \
        "Grafana será:" GRAFANA_DOMAIN

    confirm_input "${CYAN}👤 Usuário admin Grafana (padrão: admin): ${RESET}" \
        "Usuário:" GRAFANA_ADMIN_USER
    if [ -z "$GRAFANA_ADMIN_USER" ]; then GRAFANA_ADMIN_USER="admin"; fi

    confirm_input "${CYAN}🔑 Senha admin Grafana: ${RESET}" \
        "Senha Grafana:" GRAFANA_ADMIN_PASSWORD

    export GRAFANA_DOMAIN GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD
}

generate_grafana_yaml() {
    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/grafana"

    cat <<EOF > 24.grafana.yaml
version: "3.7"

services:

  # ─── Grafana ──────────────────────────────────────────────────────────────
  grafana:
    image: grafana/grafana:latest

    environment:
      GF_SECURITY_ADMIN_USER: "${GRAFANA_ADMIN_USER}"
      GF_SECURITY_ADMIN_PASSWORD: "${GRAFANA_ADMIN_PASSWORD}"
      GF_SERVER_ROOT_URL: "https://${GRAFANA_DOMAIN}"
      GF_SERVER_DOMAIN: "${GRAFANA_DOMAIN}"
      GF_USERS_ALLOW_SIGN_UP: "false"

    volumes:
      - grafana_data:/var/lib/grafana

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
          cpus: "0.25"
          memory: 256M
        limits:
          cpus: "1.0"
          memory: 512M
      restart_policy:
        condition: on-failure
        delay: 10s
        max_attempts: 5
        window: 120s
      labels:
        traefik.enable: "true"
        traefik.swarm.network: "network_swarm_public"
        traefik.http.routers.grafana.rule: "Host(\`${GRAFANA_DOMAIN}\`)"
        traefik.http.routers.grafana.entrypoints: "websecure"
        traefik.http.routers.grafana.priority: "1"
        traefik.http.routers.grafana.tls.certresolver: "letsencryptresolver"
        traefik.http.routers.grafana.service: "grafana"
        traefik.http.services.grafana.loadbalancer.server.port: "3000"

volumes:
  grafana_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR}/data

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF
}

deploy_grafana() {
    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/grafana"

    print_step "DEPLOY GRAFANA"

    # Criar diretório — Grafana roda como uid 472
    print_info "Criando diretório de dados do Grafana..."
    mkdir -p "${DATA_DIR}/data"
    chown -R 472:472 "${DATA_DIR}/data"
    print_success "Diretório ${DATA_DIR}/data criado (uid 472)"

    # Deploy da stack
    print_info "Deploying Grafana..."
    docker stack deploy --detach=true -c 24.grafana.yaml grafana >/dev/null 2>&1
    print_success "Stack 'grafana' enviada para o Swarm"

    print_info "Aguardando Grafana inicializar (20s)..."
    sleep 20

    _verify_grafana_running
}

_verify_grafana_running() {
    print_step "VERIFICAÇÃO GRAFANA"

    local HEALTHY=false
    local GRAFANA_CONTAINER=""

    for i in {1..8}; do
        GRAFANA_CONTAINER=$(docker ps -q -f name=grafana_grafana)
        if [ -n "$GRAFANA_CONTAINER" ]; then
            if docker exec "$GRAFANA_CONTAINER" \
                wget -qO- http://localhost:3000/api/health >/dev/null 2>&1; then
                HEALTHY=true
                break
            fi
        fi
        echo -ne "  ${INFO} ${CYAN}Verificando Grafana... (${i}/8)${RESET}\r"
        sleep 5
    done

    echo ""

    if [ "$HEALTHY" = true ]; then
        print_success "Grafana está ${BOLD}rodando e saudável${RESET} ✔"
        docker service ls --filter name=grafana_grafana \
            --format "    {{.Name}}  replicas={{.Replicas}}" 2>/dev/null || true
    else
        print_warning "Grafana ainda não respondeu ao healthcheck."
        echo -e "  ${ARROW} Ver logs:    ${DIM}docker service logs -f grafana_grafana${RESET}"
        echo -e "  ${ARROW} Status:      ${DIM}docker service ps grafana_grafana${RESET}"
    fi
}

print_grafana_summary() {
    if [ "$ENABLE_GRAFANA" != true ]; then return; fi

    echo -e ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${GREEN}   ACESSO — GRAFANA${RESET}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${WHITE}URL:${RESET}      https://${GRAFANA_DOMAIN}"
    echo -e "  ${WHITE}Usuário:${RESET}  ${GRAFANA_ADMIN_USER}"
    echo -e "  ${WHITE}Senha:${RESET}    ${GRAFANA_ADMIN_PASSWORD}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${YELLOW}⚠️  Salve a senha do Grafana — não será exibida novamente!${RESET}"
    echo -e ""
    echo -e "${BOLD}${CYAN}📋 PRÓXIMOS PASSOS — GRAFANA:${RESET}"
    echo -e "  ${ARROW} 1. Acesse https://${GRAFANA_DOMAIN} e faça login com as credenciais acima"
    echo -e "  ${ARROW} 2. Adicione o Prometheus como datasource:"
    echo -e "       ${DIM}Configuration → Data Sources → Add → Prometheus${RESET}"
    echo -e "       ${DIM}URL: http://prometheus_prometheus:9090${RESET}"
    echo -e "  ${ARROW} 3. Importe dashboards prontos em grafana.com/dashboards"
    echo -e "       ${DIM}Node Exporter: ID 1860 | Docker Swarm: ID 609${RESET}"
    echo -e ""
}
