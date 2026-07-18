#!/bin/bash

# =============================================================================
# Open Design Module
# Editor de design self-hosted com Basic Auth via Traefik
# Inclui build customizada com Node.js + Codex (OpenAI)
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

    # OpenAI API Key para o Codex
    echo -e ""
    echo -ne "${CYAN}🤖 OpenAI API Key para o Open Design (sk-... ou Enter para pular): ${RESET}"
    read OPEN_DESIGN_OPENAI_KEY < /dev/tty || true
    if [ -n "$OPEN_DESIGN_OPENAI_KEY" ]; then
        print_success "OpenAI API Key configurada"
    else
        OPEN_DESIGN_OPENAI_KEY=""
        print_info "OpenAI API Key não configurada — pode ser adicionada depois no YAML"
    fi

    export OPEN_DESIGN_DOMAIN OPEN_DESIGN_USER OPEN_DESIGN_PASSWORD OPEN_DESIGN_HASH
    export OPEN_DESIGN_OPENAI_KEY
}

# Detecta o gerenciador de pacotes da imagem base (apk = Alpine, apt = Debian)
_detect_open_design_pkg_manager() {
    docker run --rm --entrypoint sh docker.io/vanjayak/open-design:latest \
        -c "command -v apk >/dev/null 2>&1 && echo apk || echo apt" 2>/dev/null || echo "apk"
}

_build_open_design_image() {
    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/open-design"
    local IMAGE_TAG="${BUSINESS_NAME}/open-design-custom:latest"

    print_step "BUILD — IMAGEM CUSTOMIZADA DO OPEN DESIGN (Node.js + Codex)"

    print_info "Detectando sistema de pacotes da imagem base..."
    local PKG_MGR
    PKG_MGR=$(_detect_open_design_pkg_manager)
    print_info "Gerenciador de pacotes detectado: ${PKG_MGR}"

    mkdir -p "${DATA_DIR}"

    if [ "$PKG_MGR" = "apk" ]; then
        # Alpine
        cat > "${DATA_DIR}/Dockerfile" <<'DOCKERFILE'
FROM docker.io/vanjayak/open-design:latest
USER root
RUN apk add --no-cache nodejs npm && \
    npm install -g @openai/codex
USER node
DOCKERFILE
    else
        # Debian/Ubuntu
        cat > "${DATA_DIR}/Dockerfile" <<'DOCKERFILE'
FROM docker.io/vanjayak/open-design:latest
USER root
RUN apt-get update && apt-get install -y nodejs npm && \
    npm install -g @openai/codex
USER node
DOCKERFILE
    fi

    print_success "Dockerfile criado (${PKG_MGR})"

    print_info "Iniciando build de '${IMAGE_TAG}' (pode levar alguns minutos)..."
    if docker build -t "${IMAGE_TAG}" "${DATA_DIR}"; then
        print_success "Imagem '${IMAGE_TAG}' criada com sucesso!"
        OPEN_DESIGN_IMAGE="${IMAGE_TAG}"
    else
        print_warning "Falha no build da imagem customizada — usando imagem padrão"
        OPEN_DESIGN_IMAGE="docker.io/vanjayak/open-design:latest"
    fi

    export OPEN_DESIGN_IMAGE
}

generate_open_design_yaml() {
    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/open-design"
    # Usar imagem customizada se disponível, senão a padrão
    local IMAGE="${OPEN_DESIGN_IMAGE:-docker.io/vanjayak/open-design:latest}"
    # Converter $ para $$ no hash para o Traefik YAML
    local _OD_HASH
    _OD_HASH=$(printf '%s' "${OPEN_DESIGN_HASH:-}" | sed 's/\$/\$\$/g')

    cat <<EOF > 26.open-design.yaml
version: "3.7"

services:

  # ─── Open Design ──────────────────────────────────────────────────────────
  open-design:
    image: ${IMAGE}

    environment:
      OD_DISABLE_API_AUTH: "1"
      OD_BIND_HOST: "0.0.0.0"
      OD_PORT: "7456"
      OPEN_DESIGN_ALLOWED_ORIGINS: "https://${OPEN_DESIGN_DOMAIN}"
      OD_ALLOWED_ORIGINS: "https://${OPEN_DESIGN_DOMAIN}"
      OD_API_TOKEN: ""
      OPENAI_API_KEY: "${OPEN_DESIGN_OPENAI_KEY:-}"

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

    # Criar diretórios e ajustar permissões
    print_info "Criando diretório de dados..."
    mkdir -p "${DATA_DIR}/data"
    chmod -R 777 "${DATA_DIR}"
    chown -R 1000:1000 "${DATA_DIR}"
    print_success "Diretório ${DATA_DIR} criado com permissões corretas"

    # Build da imagem customizada
    _build_open_design_image

    # Regenerar YAML com a imagem correta (pós-build)
    generate_open_design_yaml

    print_info "Deploying Open Design..."
    docker stack deploy --detach=true -c 26.open-design.yaml open_design >/dev/null 2>&1
    print_success "Stack 'open_design' enviada para o Swarm"
    print_info "Open Design iniciando em background."
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
