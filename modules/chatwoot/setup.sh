#!/bin/bash

setup_chatwoot_vars() {
    print_banner
    print_step "CONFIGURAÇÕES CHATWOOT"
    
    # Domínio
    confirm_input "${CYAN}🌐 Domínio Chatwoot (ex: chatwoot.meudominio.com): ${RESET}" "Chatwoot será:" CHATWOOT_DOMAIN
    
    # Email Admin
    confirm_input "${CYAN}📧 Email do Administrador Chatwoot: ${RESET}" "Email Admin:" CHATWOOT_ADMIN_EMAIL

    # Resend — perguntar se quer configurar agora
    echo -e ""
    print_step "CONFIGURAÇÃO DE EMAIL (RESEND)"
    echo -e "  ${WHITE}O Chatwoot usa o Resend para enviar emails:${RESET}"
    echo -e "  ${DIM}  • Confirmação de conta e reset de senha${RESET}"
    echo -e "  ${DIM}  • Notificações de conversas para agentes${RESET}"
    echo -e "  ${DIM}  • Emails transacionais em geral${RESET}"
    echo -e ""
    echo -e "  ${YELLOW}Para usar o Resend você precisa:${RESET}"
    echo -e "  ${ARROW} 1. Criar conta gratuita em ${BOLD}https://resend.com${RESET}"
    echo -e "  ${ARROW} 2. Adicionar seu domínio em ${BOLD}https://resend.com/domains${RESET}"
    echo -e "  ${ARROW} 3. Configurar os registros DNS (DKIM, SPF, DMARC) no seu DNS"
    echo -e "  ${ARROW} 4. Gerar uma API Key em ${BOLD}https://resend.com/api-keys${RESET}"
    echo -e ""
    echo -e "  ${DIM}Você pode pular agora e configurar depois editando 19.chatwoot.yaml${RESET}"
    echo -e ""

    read -p "$(echo -e "${CYAN}📧 Deseja configurar o Resend agora? (s/n): ${RESET}")" _RESEND_OPT < /dev/tty || true

    if [[ "$_RESEND_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
        echo -e ""
        echo -e "  ${YELLOW}⚠️  Certifique-se de que os registros DNS já estão configurados no Resend${RESET}"
        echo -e "  ${DIM}  antes de continuar, caso contrário os emails não serão entregues.${RESET}"
        echo -e ""
        confirm_input "${CYAN}🔑 API Key do Resend (começa com re_): ${RESET}" "Resend Key:" CHATWOOT_RESEND_API_KEY
        CHATWOOT_RESEND_CONFIGURED=true
        print_success "Resend configurado"
    else
        CHATWOOT_RESEND_API_KEY="CONFIGURE_DEPOIS"
        CHATWOOT_RESEND_CONFIGURED=false
        print_warning "Resend não configurado — edite SMTP_PASSWORD em 19.chatwoot.yaml depois"
    fi

    export CHATWOOT_RESEND_CONFIGURED
    
    # Gerar SECRET_KEY_BASE
    print_info "Gerando SECRET_KEY_BASE..."
    CHATWOOT_SECRET_KEY=$(openssl rand -hex 64)
    print_success "SECRET_KEY_BASE gerado com sucesso!"
    
    export CHATWOOT_DOMAIN CHATWOOT_ADMIN_EMAIL CHATWOOT_RESEND_API_KEY CHATWOOT_SECRET_KEY
}

generate_chatwoot_yaml() {
    # Criar diretório de storage
    CHATWOOT_STORAGE_DIR="/opt/infra/${BUSINESS_NAME}/chatwoot/storage"
    print_info "Criando diretório de storage: $CHATWOOT_STORAGE_DIR"
    mkdir -p "$CHATWOOT_STORAGE_DIR"
    
    # Definir permissões corretas (UID 1000 é o usuário padrão do container Chatwoot)
    print_info "Configurando permissões do diretório..."
    chown -R 1000:1000 "$CHATWOOT_STORAGE_DIR"
    print_success "Permissões configuradas (1000:1000)"
    
    # 19.chatwoot.yaml
    cat <<EOF > 19.chatwoot.yaml
version: "3.7"

services:

  # ─── Rails (API + Frontend) ───────────────────────────────────────────────
  chatwoot_rails:
    image: chatwoot/chatwoot:v3.8.0
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    entrypoint: docker/entrypoints/rails.sh
    command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]

    environment:
      NODE_ENV: production
      RAILS_ENV: production
      INSTALLATION_ENV: docker

      # ── Banco de Dados (aponta para serviço postgres existente) ───────────
      POSTGRES_HOST: postgres_postgres
      POSTGRES_PORT: "5432"
      POSTGRES_DB: chatwoot_production
      POSTGRES_USERNAME: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}

      # ── Redis (aponta para serviço redis existente) ───────────────────────
      REDIS_URL: "redis://:${REDIS_PASSWORD}@redis_redis:6379"

      # ── Segurança ─────────────────────────────────────────────────────────
      SECRET_KEY_BASE: ${CHATWOOT_SECRET_KEY}

      # ── App ───────────────────────────────────────────────────────────────
      FRONTEND_URL: https://${CHATWOOT_DOMAIN}

      # ── Email (SMTP via Resend) ────────────────────────────────────────────
      MAILER_SENDER_EMAIL: ${CHATWOOT_ADMIN_EMAIL}
      SMTP_ADDRESS: smtp.resend.com
      SMTP_PORT: "587"
      SMTP_USERNAME: resend
      SMTP_PASSWORD: ${CHATWOOT_RESEND_API_KEY}
      SMTP_AUTHENTICATION: plain
      SMTP_ENABLE_STARTTLS_AUTO: "true"
      SMTP_SSL: "false"

      # ── Storage ───────────────────────────────────────────────────────────
      ACTIVE_STORAGE_SERVICE: local
      ENABLE_ACCOUNT_SIGNUP: "false"
      RAILS_LOG_TO_STDOUT: "true"

    volumes:
      - chatwoot_storage:/app/storage

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
          memory: 2048M

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
        traefik.http.routers.chatwoot.rule: "Host(\`${CHATWOOT_DOMAIN}\`)"
        traefik.http.routers.chatwoot.entrypoints: "websecure"
        traefik.http.routers.chatwoot.priority: "1"
        traefik.http.routers.chatwoot.tls.certresolver: "letsencryptresolver"
        traefik.http.routers.chatwoot.service: "chatwoot_rails"
        traefik.http.services.chatwoot_rails.loadbalancer.server.port: "3000"
        traefik.http.services.chatwoot_rails.loadbalancer.passHostHeader: "true"
        traefik.http.middlewares.chatwoot-ws.headers.customrequestheaders.Upgrade: websocket
        traefik.http.middlewares.chatwoot-ws.headers.customrequestheaders.Connection: Upgrade
        traefik.http.routers.chatwoot.middlewares: chatwoot-ws

    # healthcheck desabilitado durante primeiro deploy
    # Reabilite após rodar db:chatwoot_prepare e criar a Account
    # healthcheck:
    #   test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:3000/auth/sign_in >/dev/null || exit 1"]
    #   interval: 30s
    #   timeout: 10s
    #   retries: 5
    #   start_period: 120s

  # ─── Sidekiq (Background Jobs) ────────────────────────────────────────────
  chatwoot_sidekiq:
    image: chatwoot/chatwoot:v3.8.0
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]

    environment:
      NODE_ENV: production
      RAILS_ENV: production
      INSTALLATION_ENV: docker

      POSTGRES_HOST: postgres_postgres
      POSTGRES_PORT: "5432"
      POSTGRES_DB: chatwoot_production
      POSTGRES_USERNAME: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}

      REDIS_URL: "redis://:${REDIS_PASSWORD}@redis_redis:6379"

      SECRET_KEY_BASE: ${CHATWOOT_SECRET_KEY}

      FRONTEND_URL: https://${CHATWOOT_DOMAIN}

      MAILER_SENDER_EMAIL: ${CHATWOOT_ADMIN_EMAIL}
      SMTP_ADDRESS: smtp.resend.com
      SMTP_PORT: "587"
      SMTP_USERNAME: resend
      SMTP_PASSWORD: ${CHATWOOT_RESEND_API_KEY}
      SMTP_AUTHENTICATION: plain
      SMTP_ENABLE_STARTTLS_AUTO: "true"
      SMTP_SSL: "false"

      ACTIVE_STORAGE_SERVICE: local
      RAILS_LOG_TO_STDOUT: "true"

    volumes:
      - chatwoot_storage:/app/storage

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

      update_config:
        parallelism: 1
        delay: 30s
        order: stop-first
        failure_action: rollback

      labels:
        traefik.enable: "false"

volumes:
  chatwoot_storage:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${CHATWOOT_STORAGE_DIR}

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    print_success "Arquivo 19.chatwoot.yaml gerado com sucesso!"
}
