#!/bin/bash

# =============================================================================
# Prometheus Module
# Monitoramento e métricas via Prometheus + Basic Auth no Traefik
# =============================================================================

setup_prometheus_vars() {
    print_banner
    print_step "CONFIGURAÇÕES PROMETHEUS"

    confirm_input "${CYAN}🌐 Domínio Prometheus (ex: prometheus.meudominio.com): ${RESET}" \
        "Prometheus será:" PROMETHEUS_DOMAIN

    # Usuário para Basic Auth
    confirm_input "${CYAN}👤 Usuário Basic Auth (padrão: admin): ${RESET}" \
        "Usuário:" PROMETHEUS_USER
    if [ -z "$PROMETHEUS_USER" ]; then PROMETHEUS_USER="admin"; fi

    # Senha para Basic Auth
    confirm_input "${CYAN}🔑 Senha para proteger o Prometheus: ${RESET}" \
        "Senha Prometheus:" PROMETHEUS_PASSWORD

    # Gerar hash htpasswd
    if ! command -v htpasswd >/dev/null 2>&1; then
        print_info "htpasswd não encontrado — instalando apache2-utils..."
        apt-get install -y apache2-utils >/dev/null 2>&1 || true
    fi

    if command -v htpasswd >/dev/null 2>&1; then
        PROMETHEUS_HASH=$(htpasswd -nb "$PROMETHEUS_USER" "$PROMETHEUS_PASSWORD" \
            | sed 's/\$/\$\$/g')
        print_success "Hash Basic Auth gerado"
    else
        print_warning "Não foi possível gerar o hash — edite 23.prometheus.yaml depois:"
        echo -e "  ${DIM}htpasswd -nb ${PROMETHEUS_USER} SUA_SENHA | sed 's/\\\$/\\\$\\\$/g'${RESET}"
        PROMETHEUS_HASH="${PROMETHEUS_USER}:\$\$HASH_PENDENTE"
    fi

    export PROMETHEUS_DOMAIN PROMETHEUS_USER PROMETHEUS_PASSWORD PROMETHEUS_HASH
}

generate_prometheus_yaml() {
    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/prometheus"

    cat <<EOF > 23.prometheus.yaml
version: "3.7"

services:

  # ─── Prometheus ───────────────────────────────────────────────────────────
  prometheus:
    image: prom/prometheus:latest

    volumes:
      - prometheus_data:/prometheus
      - ${DATA_DIR}/prometheus.yml:/etc/prometheus/prometheus.yml

    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--storage.tsdb.retention.time=15d"
      - "--web.enable-lifecycle"

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
          memory: 1024M
      restart_policy:
        condition: on-failure
        delay: 10s
        max_attempts: 5
        window: 120s
      labels:
        traefik.enable: "true"
        traefik.swarm.network: "network_swarm_public"
        traefik.http.routers.prometheus.rule: "Host(\`${PROMETHEUS_DOMAIN}\`)"
        traefik.http.routers.prometheus.entrypoints: "websecure"
        traefik.http.routers.prometheus.priority: "1"
        traefik.http.routers.prometheus.tls.certresolver: "letsencryptresolver"
        traefik.http.routers.prometheus.service: "prometheus"
        traefik.http.routers.prometheus.middlewares: "prometheus-auth"
        traefik.http.middlewares.prometheus-auth.basicauth.users: "${PROMETHEUS_HASH}"
        traefik.http.services.prometheus.loadbalancer.server.port: "9090"

volumes:
  prometheus_data:
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

deploy_prometheus() {
    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/prometheus"

    print_step "DEPLOY PROMETHEUS"

    # Criar diretórios
    print_info "Criando diretórios de dados do Prometheus..."
    mkdir -p "${DATA_DIR}/data"
    chmod 777 "${DATA_DIR}/data"  # prometheus roda como uid 65534 (nobody)
    print_success "Diretório ${DATA_DIR}/data criado"

    # Gerar arquivo prometheus.yml
    print_info "Gerando ${DATA_DIR}/prometheus.yml..."
    cat > "${DATA_DIR}/prometheus.yml" <<'PROMCFG'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node"
    static_configs:
      - targets: ["node-exporter:9100"]
PROMCFG
    print_success "prometheus.yml criado"

    # Deploy da stack
    print_info "Deploying Prometheus..."
    docker stack deploy --detach=true -c 23.prometheus.yaml prometheus >/dev/null 2>&1
    print_success "Stack 'prometheus' enviada para o Swarm"

    # Aguardar e verificar
    print_info "Aguardando Prometheus inicializar (20s)..."
    sleep 20

    _verify_prometheus_running
}

_verify_prometheus_running() {
    print_step "VERIFICAÇÃO PROMETHEUS"

    local HEALTHY=false
    local PROM_CONTAINER=""

    for i in {1..8}; do
        PROM_CONTAINER=$(docker ps -q -f name=prometheus_prometheus)
        if [ -n "$PROM_CONTAINER" ]; then
            if docker exec "$PROM_CONTAINER" \
                wget -qO- http://localhost:9090/-/healthy >/dev/null 2>&1; then
                HEALTHY=true
                break
            fi
        fi
        echo -ne "  ${INFO} ${CYAN}Verificando Prometheus... (${i}/8)${RESET}\r"
        sleep 5
    done

    echo ""

    if [ "$HEALTHY" = true ]; then
        print_success "Prometheus está ${BOLD}rodando e saudável${RESET} ✔"
        docker service ls --filter name=prometheus_prometheus \
            --format "    {{.Name}}  replicas={{.Replicas}}" 2>/dev/null || true
    else
        print_warning "Prometheus ainda não respondeu ao healthcheck."
        echo -e "  ${ARROW} Ver logs:    ${DIM}docker service logs -f prometheus_prometheus${RESET}"
        echo -e "  ${ARROW} Status:      ${DIM}docker service ps prometheus_prometheus${RESET}"
    fi
}

print_prometheus_summary() {
    if [ "$ENABLE_PROMETHEUS" != true ]; then return; fi

    echo -e ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${GREEN}   ACESSO — PROMETHEUS${RESET}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${WHITE}URL:${RESET}      https://${PROMETHEUS_DOMAIN}"
    echo -e "  ${WHITE}Usuário:${RESET}  ${PROMETHEUS_USER}"
    echo -e "  ${WHITE}Senha:${RESET}    ${PROMETHEUS_PASSWORD}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${YELLOW}⚠️  Salve a senha do Prometheus — não será exibida novamente!${RESET}"
    echo -e ""
}
