#!/bin/bash

# =============================================================================
# Open Design Module
# Editor de design self-hosted (Open Design) com Basic Auth via Traefik
# =============================================================================

setup_open_design_vars() {
    print_banner
    print_step "CONFIGURAÇÕES OPEN DESIGN"

    confirm_input "${CYAN}🌐 Domínio Open Design (ex: design.meudominio.com): ${RESET}" \
        "Open Design será:" OPEN_DESIGN_DOMAIN

    confirm_input "${CYAN}👤 Usuário Basic Auth (padrão: admin): ${RESET}" \
        "Usuário:" OPEN_DESIGN_USER
    if [ -z "$OPEN_DESIGN_USER" ]; then OPEN_DESIGN_USER="admin"; fi

    confirm_input "${CYAN}🔑 Senha para proteger o Open Design: ${RESET}" \
        "Senha Open Design:" OPEN_DESIGN_PASSWORD

    # Gerar hash htpasswd
    if ! command -v htpasswd >/dev/null 2>&1; then
        print_info "htpasswd não encontrado — instalando apache2-utils..."
        apt-get install -y apache2-utils >/dev/null 2>&1 || true
    fi

    if command -v htpasswd >/dev/null 2>&1; then
        OPEN_DESIGN_HASH=$(htpasswd -nb "$OPEN_DESIGN_USER" "$OPEN_DESIGN_PASSWORD")
        print_success "Hash Basic Auth gerado"
    else
        print_warning "Não foi possível gerar o hash — edite 26.open-design.yaml depois:"
        echo -e "  ${DIM}htpasswd -nb ${OPEN_DESIGN_USER} SUA_SENHA${RESET}"
        OPEN_DESIGN_HASH="${OPEN_DESIGN_USER}:\$HASH_PENDENTE"
    fi

    export OPEN_DESIGN_DOMAIN OPEN_DESIGN_USER OPEN_DESIGN_PASSWORD OPEN_DESIGN_HASH
}

generate_open_design_yaml() {
    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/open-design"
    # Converter $ para $$ no hash para o Traefik YAML (Docker Swarm labels requerem $$)
    local _OD_HASH
    _OD_HASH=$(printf '%s' "${OPEN_DESIGN_HASH:-}" | sed 's/\$/\$\$/g')

    cat <<EOF > 26.open-design.yaml
version: "3.7"

services:

  # ─── Open Design ──────────────────────────────────────────────────────────
  open-design:
    image: docker.io/vanjayak/open-design:latest

    environment:
      OD_DISABLE_API_AUTH: "1"
      OD_BIND_HOST: "0.0.0.0"
      OD_PORT: "7456"
      OPEN_DESIGN_ALLOWED_ORIGINS: "https://${OPEN_DESIGN_DOMAIN}"
      OD_ALLOWED_ORIGINS: "https://${OPEN_DESIGN_DOMAIN}"

    volumes:
      - open_design_data:/app/.od

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
        traefik.http.routers.open-design.rule: "Host(\`${OPEN_DESIGN_DOMAIN}\`)"
        traefik.http.routers.open-design.entrypoints: "websecure"
        traefik.http.routers.open-design.tls.certresolver: "letsencryptresolver"
        traefik.http.routers.open-design.service: "open-design"
        traefik.http.services.open-design.loadbalancer.server.port: "7456"
        traefik.http.routers.open-design.middlewares: "open-design-auth"
        traefik.http.middlewares.open-design-auth.basicauth.users: "${_OD_HASH}"

volumes:
  open_design_data:
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

deploy_open_design() {
    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/open-design"

    print_step "DEPLOY OPEN DESIGN"

    print_info "Criando diretório de dados..."
    mkdir -p "${DATA_DIR}/data"
    chmod 755 "${DATA_DIR}/data"
    print_success "Diretório ${DATA_DIR}/data criado"

    print_info "Deploying Open Design..."
    docker stack deploy --detach=true -c 26.open-design.yaml open_design >/dev/null 2>&1
    print_success "Stack 'open_design' enviada para o Swarm"
    print_info "Open Design iniciando em background."
}

_verify_open_design_running() {
    print_step "VERIFICAÇÃO OPEN DESIGN"

    local HEALTHY=false
    local OD_CONTAINER=""

    for i in {1..8}; do
        OD_CONTAINER=$(docker ps -q -f name=open_design_open-design)
        if [ -n "$OD_CONTAINER" ]; then
            if docker exec "$OD_CONTAINER" \
                wget -qO- http://localhost:7456/ >/dev/null 2>&1; then
                HEALTHY=true
                break
            fi
        fi
        echo -ne "  ${INFO} ${CYAN}Verificando Open Design... (${i}/8)${RESET}\r"
        sleep 5
    done

    echo ""

    if [ "$HEALTHY" = true ]; then
        print_success "Open Design está ${BOLD}rodando e saudável${RESET} ✔"
        docker service ls --filter name=open_design_open-design \
            --format "    {{.Name}}  replicas={{.Replicas}}" 2>/dev/null || true
    else
        print_warning "Open Design ainda não respondeu."
        echo -e "  ${ARROW} Ver logs: ${DIM}docker service logs -f open_design_open-design${RESET}"
        echo -e "  ${ARROW} Status:   ${DIM}docker service ps open_design_open-design${RESET}"
    fi
}

print_open_design_summary() {
    if [ "$ENABLE_OPEN_DESIGN" != true ]; then return; fi

    echo -e ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${GREEN}   ACESSO — OPEN DESIGN${RESET}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${WHITE}URL:${RESET}      https://${OPEN_DESIGN_DOMAIN}"
    echo -e "  ${WHITE}Usuário:${RESET}  ${OPEN_DESIGN_USER}"
    echo -e "  ${WHITE}Senha:${RESET}    ${OPEN_DESIGN_PASSWORD}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${YELLOW}⚠️  Salve a senha do Open Design — não será exibida novamente!${RESET}"
    echo -e ""
}
