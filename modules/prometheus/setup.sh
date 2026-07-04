#!/bin/bash

# =============================================================================
# Prometheus Module
# Instala Prometheus + Grafana + Node Exporter como stack integrada
# O usuário só precisa responder UMA pergunta — os 3 sobem juntos
# =============================================================================

setup_prometheus_vars() {
    print_banner
    print_step "CONFIGURAÇÕES PROMETHEUS + GRAFANA + NODE EXPORTER"

    echo -e "  ${DIM}Ao instalar o Prometheus, o Grafana e o Node Exporter serão instalados${RESET}"
    echo -e "  ${DIM}automaticamente como parte da stack de monitoramento.${RESET}"
    echo -e ""

    # ── Prometheus ──────────────────────────────────────────────────────────
    confirm_input "${CYAN}🌐 Domínio Prometheus (ex: prometheus.meudominio.com): ${RESET}" \
        "Prometheus será:" PROMETHEUS_DOMAIN

    confirm_input "${CYAN}👤 Usuário Basic Auth Prometheus (padrão: admin): ${RESET}" \
        "Usuário:" PROMETHEUS_USER
    if [ -z "$PROMETHEUS_USER" ]; then PROMETHEUS_USER="admin"; fi

    confirm_input "${CYAN}🔑 Senha para proteger o Prometheus: ${RESET}" \
        "Senha Prometheus:" PROMETHEUS_PASSWORD

    # Gerar hash htpasswd para Prometheus
    if ! command -v htpasswd >/dev/null 2>&1; then
        print_info "htpasswd não encontrado — instalando apache2-utils..."
        apt-get install -y apache2-utils >/dev/null 2>&1 || true
    fi

    if command -v htpasswd >/dev/null 2>&1; then
        PROMETHEUS_HASH=$(htpasswd -nb "$PROMETHEUS_USER" "$PROMETHEUS_PASSWORD" \
            | sed 's/\$/\$\$/g')
        print_success "Hash Basic Auth Prometheus gerado"
    else
        print_warning "Não foi possível gerar o hash — edite 23.prometheus.yaml depois"
        PROMETHEUS_HASH="${PROMETHEUS_USER}:\$\$HASH_PENDENTE"
    fi

    # ── Grafana (automático com Prometheus) ─────────────────────────────────
    print_step "CONFIGURAÇÕES GRAFANA"

    confirm_input "${CYAN}🌐 Domínio Grafana (ex: grafana.meudominio.com): ${RESET}" \
        "Grafana será:" GRAFANA_DOMAIN

    confirm_input "${CYAN}👤 Usuário admin Grafana (padrão: admin): ${RESET}" \
        "Usuário Grafana:" GRAFANA_ADMIN_USER
    if [ -z "$GRAFANA_ADMIN_USER" ]; then GRAFANA_ADMIN_USER="admin"; fi

    confirm_input "${CYAN}🔑 Senha admin Grafana: ${RESET}" \
        "Senha Grafana:" GRAFANA_ADMIN_PASSWORD

    # Ativar flags de Grafana automaticamente
    ENABLE_GRAFANA=true
    export ENABLE_GRAFANA

    export PROMETHEUS_DOMAIN PROMETHEUS_USER PROMETHEUS_PASSWORD PROMETHEUS_HASH
    export GRAFANA_DOMAIN GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD
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

generate_node_exporter_yaml() {
    cat <<'EOF' > 25.node-exporter.yaml
version: "3.7"

services:

  # ─── Node Exporter ────────────────────────────────────────────────────────
  # Roda em modo global (um por nó do Swarm) — coleta métricas do host
  node-exporter:
    image: prom/node-exporter:latest

    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro

    command:
      - "--path.procfs=/host/proc"
      - "--path.rootfs=/rootfs"
      - "--path.sysfs=/host/sys"
      - "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"

    networks:
      - network_swarm_public

    deploy:
      mode: global
      resources:
        limits:
          cpus: "0.25"
          memory: 128M
      restart_policy:
        condition: on-failure
      labels:
        traefik.enable: "false"

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF
}

deploy_prometheus() {
    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/prometheus"

    print_step "DEPLOY PROMETHEUS + NODE EXPORTER + GRAFANA"

    # ── Criar diretórios ─────────────────────────────────────────────────────
    print_info "Criando diretórios de dados do Prometheus..."
    mkdir -p "${DATA_DIR}/data"
    chmod 777 "${DATA_DIR}/data"  # uid 65534 (nobody)
    print_success "Diretório ${DATA_DIR}/data criado"

    # ── Gerar prometheus.yml com os 3 jobs ───────────────────────────────────
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

  - job_name: "node-exporter"
    static_configs:
      - targets: ["node-exporter:9100"]
PROMCFG
    print_success "prometheus.yml criado (scrape: prometheus + node + node-exporter)"

    # ── Deploy Prometheus ────────────────────────────────────────────────────
    print_info "Deploying Prometheus..."
    docker stack deploy --detach=true -c 23.prometheus.yaml prometheus >/dev/null 2>&1
    print_success "Stack 'prometheus' enviada"

    # ── Deploy Node Exporter ─────────────────────────────────────────────────
    print_info "Deploying Node Exporter (modo global)..."
    docker stack deploy --detach=true -c 25.node-exporter.yaml node_exporter >/dev/null 2>&1
    print_success "Stack 'node_exporter' enviada"

    # ── Deploy Grafana (automático) ──────────────────────────────────────────
    deploy_grafana

    # ── Aguardar e verificar Prometheus ──────────────────────────────────────
    print_info "Aguardando Prometheus inicializar (20s)..."
    sleep 20
    _verify_prometheus_running

    # ── Recarregar config do Prometheus (após node-exporter subir) ───────────
    print_info "Recarregando configuração do Prometheus..."
    local PROM_CONTAINER
    PROM_CONTAINER=$(docker ps -q -f name=prometheus_prometheus)
    if [ -n "$PROM_CONTAINER" ]; then
        docker exec "$PROM_CONTAINER" \
            wget -qO- --post-data '' http://localhost:9090/-/reload >/dev/null 2>&1 || true
        print_success "Prometheus config recarregada ✔"
    fi
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
        docker service ls --filter name=prometheus \
            --format "    {{.Name}}  replicas={{.Replicas}}" 2>/dev/null || true
        docker service ls --filter name=node_exporter \
            --format "    {{.Name}}  replicas={{.Replicas}}" 2>/dev/null || true
    else
        print_warning "Prometheus ainda não respondeu ao healthcheck."
        echo -e "  ${ARROW} Ver logs: ${DIM}docker service logs -f prometheus_prometheus${RESET}"
        echo -e "  ${ARROW} Status:   ${DIM}docker service ps prometheus_prometheus${RESET}"
    fi
}

print_prometheus_summary() {
    if [ "$ENABLE_PROMETHEUS" != true ]; then return; fi

    echo -e ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${GREEN}   ACESSO — PROMETHEUS + GRAFANA + NODE EXPORTER${RESET}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${WHITE}Prometheus URL:${RESET}   https://${PROMETHEUS_DOMAIN}"
    echo -e "  ${WHITE}Prometheus user:${RESET}  ${PROMETHEUS_USER} / ${PROMETHEUS_PASSWORD}"
    echo -e "  ${WHITE}Grafana URL:${RESET}      https://${GRAFANA_DOMAIN}"
    echo -e "  ${WHITE}Grafana user:${RESET}     ${GRAFANA_ADMIN_USER} / ${GRAFANA_ADMIN_PASSWORD}"
    echo -e "  ${WHITE}Node Exporter:${RESET}    modo global (sem UI — scrape via Prometheus)"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${YELLOW}⚠️  Salve as senhas acima — não serão exibidas novamente!${RESET}"
    echo -e ""
    echo -e "${BOLD}${CYAN}📋 PRÓXIMOS PASSOS — GRAFANA:${RESET}"
    echo -e "  ${ARROW} 1. Acesse https://${GRAFANA_DOMAIN} e faça login"
    echo -e "  ${ARROW} 2. Adicione Prometheus como datasource:"
    echo -e "       ${DIM}Configuration → Data Sources → Prometheus${RESET}"
    echo -e "       ${DIM}URL: http://prometheus_prometheus:9090${RESET}"
    echo -e "  ${ARROW} 3. Importe dashboards prontos:"
    echo -e "       ${DIM}Node Exporter Full: ID 1860${RESET}"
    echo -e "       ${DIM}Docker Swarm:       ID 609${RESET}"
    echo -e ""
}
