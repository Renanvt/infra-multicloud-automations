#!/bin/bash

# =============================================================================
# Hermes Agent Module
# Gateway de IA + Dashboard web — NousResearch Hermes Agent
#
# Em VMs com <= 8GB RAM: instala apenas o gateway (sem dashboard)
# O acesso ao Hermes é feito via terminal/CLI nesse caso
# =============================================================================

setup_hermes_vars() {
    if [ "$ENABLE_HERMES" != true ]; then return; fi

    print_banner
    print_step "CONFIGURAÇÕES HERMES AGENT"

    : "${HERMES_DASHBOARD_ENABLED:=true}"

    if [ "$HERMES_DASHBOARD_ENABLED" = false ]; then
        echo -e "  ${YELLOW}VM com RAM limitada detectada — Hermes será instalado sem Dashboard.${RESET}"
        echo -e "  ${DIM}O Gateway ficará disponível para uso via CLI e API interna.${RESET}"
        echo -e "  ${DIM}Para acessar: docker exec -it \$(docker ps -q -f name=hermes_hermes_gateway) hermes${RESET}"
        echo -e ""
    fi

    confirm_input "${CYAN}🌐 Domínio Hermes Gateway (ex: hermes.meudominio.com): ${RESET}" \
        "Hermes Gateway será:" HERMES_DOMAIN

    if [ "$HERMES_DASHBOARD_ENABLED" = true ]; then
        confirm_input "${CYAN}🌐 Domínio Hermes Dashboard (ex: hermes-dashboard.meudominio.com): ${RESET}" \
            "Hermes Dashboard será:" HERMES_DASHBOARD_DOMAIN
    else
        HERMES_DASHBOARD_DOMAIN=""
    fi

    export HERMES_DOMAIN HERMES_DASHBOARD_DOMAIN HERMES_DASHBOARD_ENABLED
}

generate_hermes_yaml() {
    if [ "$ENABLE_HERMES" != true ]; then return; fi

    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/hermes"
    : "${HERMES_DASHBOARD_ENABLED:=true}"

    # Bloco do dashboard — incluído só se a VM suportar
    local DASHBOARD_SERVICE=""
    if [ "$HERMES_DASHBOARD_ENABLED" = true ]; then
        DASHBOARD_SERVICE=$(cat <<DASH_BLOCK

  # ─── Dashboard (Web UI) ───────────────────────────────────────────────────
  hermes_dashboard:
    image: nousresearch/hermes-agent:latest
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    command: dashboard --host 0.0.0.0

    environment:
      HERMES_HOME: /opt/data
      GATEWAY_HEALTH_URL: http://hermes_gateway:8642

    volumes:
      - ${DATA_DIR}:/opt/data

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
      update_config:
        parallelism: 1
        delay: 30s
        order: stop-first
        failure_action: rollback
      labels:
        traefik.enable: "true"
        traefik.swarm.network: "network_swarm_public"
        traefik.http.routers.hermes-dashboard.rule: "Host(\`${HERMES_DASHBOARD_DOMAIN}\`)"
        traefik.http.routers.hermes-dashboard.entrypoints: "websecure"
        traefik.http.routers.hermes-dashboard.priority: "1"
        traefik.http.routers.hermes-dashboard.tls.certresolver: "letsencryptresolver"
        traefik.http.routers.hermes-dashboard.service: "hermes_dashboard"
        traefik.http.services.hermes_dashboard.loadbalancer.server.port: "9119"
        traefik.http.services.hermes_dashboard.loadbalancer.passHostHeader: "true"
DASH_BLOCK
)
    fi

    cat <<EOF > 20.hermes-agent.yaml
version: "3.7"

services:

  # ─── Gateway (API + Agent) ────────────────────────────────────────────────
  hermes_gateway:
    image: nousresearch/hermes-agent:latest
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    command: gateway run

    environment:
      HERMES_HOME: /opt/data

    volumes:
      - ${DATA_DIR}:/opt/data

    tmpfs:
      - /tmp:size=512m

    shm_size: 1g

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
          memory: 512M
        limits:
          cpus: "2.0"
          memory: 4096M
      restart_policy:
        condition: on-failure
        delay: 10s
        max_attempts: 5
        window: 120s
      update_config:
        parallelism: 1
        delay: 30s
        order: stop-first
        failure_action: rollback
      labels:
        traefik.enable: "true"
        traefik.swarm.network: "network_swarm_public"
        traefik.http.routers.hermes.rule: "Host(\`${HERMES_DOMAIN}\`)"
        traefik.http.routers.hermes.entrypoints: "websecure"
        traefik.http.routers.hermes.priority: "1"
        traefik.http.routers.hermes.tls.certresolver: "letsencryptresolver"
        traefik.http.routers.hermes.service: "hermes_gateway"
        traefik.http.services.hermes_gateway.loadbalancer.server.port: "8642"
        traefik.http.services.hermes_gateway.loadbalancer.passHostHeader: "true"

    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8642/health >/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
${DASHBOARD_SERVICE}
networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF
}

deploy_hermes() {
    if [ "$ENABLE_HERMES" != true ]; then return; fi

    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/hermes"
    : "${HERMES_DASHBOARD_ENABLED:=true}"

    print_step "DEPLOY HERMES AGENT"

    if [ "$HERMES_DASHBOARD_ENABLED" = false ]; then
        print_info "Modo Gateway-only (VM com RAM limitada) — Dashboard não será instalado"
    fi

    print_info "Criando diretório de dados ${DATA_DIR}..."
    mkdir -p "${DATA_DIR}"
    chmod 755 "${DATA_DIR}"
    print_success "Diretório criado"

    print_info "Deploying Hermes Gateway..."
    docker stack deploy --detach=true -c 20.hermes-agent.yaml hermes >/dev/null 2>&1
    print_success "Stack 'hermes' enviada para o Swarm"

    # Criar alias 'hermes' para facilitar configuração posterior
    # Usa o nome do serviço Swarm — funciona mesmo se o container reiniciou
    local ALIAS_LINE="alias hermes='docker exec -it \$(docker ps -q -f name=hermes_hermes_gateway --filter status=running | head -1) hermes'"
    local ALIAS_SETUP="alias hermes-setup='docker run --rm -it -v /opt/infra/${BUSINESS_NAME}/hermes:/opt/data nousresearch/hermes-agent:latest hermes setup'"
    if ! grep -q "alias hermes=" /root/.bashrc 2>/dev/null; then
        echo "$ALIAS_LINE" >> /root/.bashrc
        echo "$ALIAS_SETUP" >> /root/.bashrc
        print_success "Aliases criados — use: hermes-setup  (funciona mesmo com gateway parado)"
    fi

    print_info "Hermes instalado."
    print_info "Para configurar, abra novo terminal e execute: hermes-setup"
} 

_verify_hermes_running() {
    print_step "VERIFICAÇÃO HERMES AGENT"

    local HEALTHY=false
    local HERMES_CONTAINER=""

    for i in {1..8}; do
        HERMES_CONTAINER=$(docker ps -q -f name=hermes_hermes_gateway 2>/dev/null) || HERMES_CONTAINER=""
        if [ -n "$HERMES_CONTAINER" ]; then
            docker exec "$HERMES_CONTAINER" \
                curl -fsS http://127.0.0.1:8642/health >/dev/null 2>&1 \
                && HEALTHY=true && break || true
        fi
        echo -ne "  ${INFO} ${CYAN}Verificando Hermes... (${i}/8)${RESET}\r"
        sleep 5
    done

    echo ""

    if [ "$HEALTHY" = true ]; then
        print_success "Hermes Agent está ${BOLD}rodando e saudável${RESET} ✔"
        docker service ls --filter name=hermes \
            --format "    {{.Name}}  replicas={{.Replicas}}" 2>/dev/null || true
    else
        print_warning "Hermes Agent ainda não respondeu ao healthcheck."
        echo -e "  ${YELLOW}Isso é normal se nenhuma plataforma de mensagens foi configurada.${RESET}"
        echo -e "  ${DIM}Configure o gateway.toml em /opt/infra/${BUSINESS_NAME}/hermes/ e redeploy.${RESET}"
        echo -e "  ${ARROW} Ver logs: ${DIM}docker service logs -f hermes_hermes_gateway${RESET}"
        echo -e "  ${ARROW} Status:   ${DIM}docker service ps hermes_hermes_gateway${RESET}"
    fi

    return 0
}

print_hermes_summary() {
    if [ "$ENABLE_HERMES" != true ]; then return; fi

    : "${HERMES_DASHBOARD_ENABLED:=true}"

    echo -e ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${GREEN}   ACESSO — HERMES AGENT${RESET}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${WHITE}Gateway API:${RESET}  https://${HERMES_DOMAIN}"
    if [ "$HERMES_DASHBOARD_ENABLED" = true ]; then
        echo -e "  ${WHITE}Dashboard:${RESET}    https://${HERMES_DASHBOARD_DOMAIN}"
    else
        echo -e "  ${WHITE}Dashboard:${RESET}    ${YELLOW}não instalado (VM com RAM limitada)${RESET}"
        echo -e "  ${WHITE}Acesso CLI:${RESET}   ${DIM}docker exec -it \$(docker ps -q -f name=hermes_hermes_gateway) hermes${RESET}"
    fi
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e ""
}
