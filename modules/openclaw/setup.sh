#!/bin/bash

# =============================================================================
# OpenClaw Module
# Gerencia inputs, geração de YAML, deploy e pós-configuração do OpenClaw
# =============================================================================

setup_openclaw_vars() {
    if [ "$ENABLE_OPENCLAW" != true ]; then return; fi

    print_banner
    print_step "CONFIGURAÇÕES OPENCLAW"

    # Domínio
    confirm_input "${CYAN}🌐 Domínio OpenClaw (ex: openclaw.meudominio.com): ${RESET}" \
        "OpenClaw será:" OPENCLAW_DOMAIN

    # Tokens gerados automaticamente
    OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
    OPENCLAW_HOOKS_TOKEN=$(openssl rand -hex 32)
    print_success "Gateway Token gerado automaticamente"
    print_success "Hooks Token gerado automaticamente"

    # OpenAI — opcional
    echo -e ""
    echo -e "  ${DIM}A chave OpenAI pode ser configurada depois via painel (Settings → Providers).${RESET}"
    echo -ne "${CYAN}🤖 OpenAI API Key (sk-...) — Enter para pular: ${RESET}"; read OPENCLAW_OPENAI_API_KEY < /dev/tty || true
    if [ -z "$OPENCLAW_OPENAI_API_KEY" ]; then
        print_warning "OpenAI API Key não informada — configure depois via openclaw config set"
    else
        print_success "OpenAI API Key informada"
    fi

    # Integrações opcionais
    print_step "INTEGRAÇÕES OPCIONAIS (Enter para pular)"

    echo -ne "${CYAN}📡 Telegram Bot Token: ${RESET}"; read OPENCLAW_TELEGRAM_TOKEN < /dev/tty || true

    echo -ne "${CYAN}🔥 Firecrawl API Key: ${RESET}"; read OPENCLAW_FIRECRAWL_KEY < /dev/tty || true

    echo -ne "${CYAN}📝 Notion API Key: ${RESET}"; read OPENCLAW_NOTION_KEY < /dev/tty || true

    echo -ne "${CYAN}🐙 GitHub Personal Access Token: ${RESET}"; read OPENCLAW_GITHUB_TOKEN < /dev/tty || true

    echo -ne "${CYAN}🗃️  Supabase Access Token: ${RESET}"; read OPENCLAW_SUPABASE_TOKEN < /dev/tty || true

    echo -ne "${CYAN}⚙️  N8N Bearer Token: ${RESET}"; read OPENCLAW_N8N_BEARER_TOKEN < /dev/tty || true

    export OPENCLAW_DOMAIN OPENCLAW_GATEWAY_TOKEN OPENCLAW_HOOKS_TOKEN
    export OPENCLAW_OPENAI_API_KEY OPENCLAW_TELEGRAM_TOKEN OPENCLAW_FIRECRAWL_KEY
    export OPENCLAW_NOTION_KEY OPENCLAW_GITHUB_TOKEN OPENCLAW_SUPABASE_TOKEN
    export OPENCLAW_N8N_BEARER_TOKEN
}

generate_openclaw_yaml() {
    if [ "$ENABLE_OPENCLAW" != true ]; then return; fi

    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/openclaw"

    cat <<EOF > 21.openclaw.yaml
version: "3.7"

services:
  openclaw_gateway:
    image: ghcr.io/openclaw/openclaw:2026.5.7
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"

    environment:
      NODE_ENV: production
      OPENCLAW_CONFIG: /home/node/.openclaw/openclaw.json
      OPENCLAW_GATEWAY_TOKEN: ${OPENCLAW_GATEWAY_TOKEN}
      OPENCLAW_HOOKS_TOKEN: ${OPENCLAW_HOOKS_TOKEN}
      OPENAI_API_KEY: "${OPENCLAW_OPENAI_API_KEY:-}"
      FIRECRAWL_API_KEY: "${OPENCLAW_FIRECRAWL_KEY:-}"
      NOTION_API_KEY: "${OPENCLAW_NOTION_KEY:-}"
      SUPABASE_ACCESS_TOKEN: "${OPENCLAW_SUPABASE_TOKEN:-}"
      GITHUB_PERSONAL_ACCESS_TOKEN: "${OPENCLAW_GITHUB_TOKEN:-}"
      TELEGRAM_DEFAULT_BOT_TOKEN: "${OPENCLAW_TELEGRAM_TOKEN:-}"
      N8N_BEARER_TOKEN: "${OPENCLAW_N8N_BEARER_TOKEN:-}"
      OPENCLAW_DISABLE_BONJOUR: "1"
      OPENCLAW_GATEWAY_BIND: lan

    volumes:
      - ${DATA_DIR}:/home/node/.openclaw

    tmpfs:
      - /tmp:size=1g

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
          cpus: "${OPENCLAW_REQ_CPU}"
          memory: ${OPENCLAW_REQ_RAM}
        limits:
          cpus: "${OPENCLAW_LIMIT_CPU}"
          memory: ${OPENCLAW_LIMIT_RAM}
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
        traefik.http.routers.openclaw.rule: "Host(\`${OPENCLAW_DOMAIN}\`)"
        traefik.http.routers.openclaw.entrypoints: "websecure"
        traefik.http.routers.openclaw.priority: "1"
        traefik.http.routers.openclaw.tls.certresolver: "letsencryptresolver"
        traefik.http.routers.openclaw.service: "openclaw_gateway"
        traefik.http.services.openclaw_gateway.loadbalancer.server.port: "18789"
        traefik.http.services.openclaw_gateway.loadbalancer.passHostHeader: "true"

    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:18789/healthz >/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF
}

deploy_openclaw() {
    if [ "$ENABLE_OPENCLAW" != true ]; then return; fi

    local DATA_DIR="/opt/infra/${BUSINESS_NAME}/openclaw"

    print_step "DEPLOY OPENCLAW"

    # Criar diretório com permissão correta para uid 1000 (user node da imagem)
    print_info "Criando diretório de dados: ${DATA_DIR}..."
    mkdir -p "${DATA_DIR}"
    chown -R 1000:1000 "${DATA_DIR}"
    chmod 755 "${DATA_DIR}"
    print_success "Diretório ${DATA_DIR} criado (uid 1000)"

    # Deploy da stack
    print_info "Deploying stack openclaw..."
    docker stack deploy --detach=true -c 21.openclaw.yaml openclaw >/dev/null 2>&1
    print_success "Stack 'openclaw' enviada para o Swarm"

    # Aguardar container subir
    print_info "Aguardando container inicializar (60s)..."
    sleep 60

    # Verificar se o container está rodando
    _wait_openclaw_healthy

    # Exibir token e instruir o usuário a acessar o dashboard antes de continuar
    _prompt_user_dashboard_access

    # Configurar via CLI após confirmação do usuário
    configure_openclaw

    # Verificação final de saúde
    _verify_openclaw_running
}

# ---------------------------------------------------------------------------
# Aguarda o container responder no healthcheck com timeout e feedback visual
# ---------------------------------------------------------------------------
_wait_openclaw_healthy() {
    print_step "AGUARDANDO OPENCLAW FICAR SAUDÁVEL"

    local OC_CONTAINER=""
    local MAX_WAIT=20  # 20 tentativas × 6s = 2 minutos

    for i in $(seq 1 $MAX_WAIT); do
        OC_CONTAINER=$(docker ps -q -f name=openclaw_openclaw_gateway)
        if [ -n "$OC_CONTAINER" ]; then
            # Container está up — checar healthcheck endpoint
            if docker exec "$OC_CONTAINER" \
                curl -fsS http://127.0.0.1:18789/healthz >/dev/null 2>&1; then
                print_success "Gateway respondendo em /healthz ✔"
                export _OC_CONTAINER="$OC_CONTAINER"
                return 0
            fi
        fi
        echo -ne "  ${INFO} ${CYAN}Aguardando gateway... (${i}/${MAX_WAIT})${RESET}\r"
        sleep 6
    done

    echo ""
    print_warning "Gateway ainda não respondeu após $((MAX_WAIT * 6))s."
    print_info "Verificando logs para diagnóstico:"
    docker service logs --tail 20 openclaw_openclaw_gateway 2>/dev/null || true

    print_warning "Você pode prosseguir manualmente após o serviço estabilizar."
    echo -e "  ${DIM}Acompanhe com: docker service logs -f openclaw_openclaw_gateway${RESET}"
}

# ---------------------------------------------------------------------------
# Exibe o token e pausa aguardando o usuário acessar o dashboard
# Isso é necessário porque o primeiro acesso pode pedir device pairing
# ---------------------------------------------------------------------------
_prompt_user_dashboard_access() {
    local OC_CONTAINER="${_OC_CONTAINER:-$(docker ps -q -f name=openclaw_openclaw_gateway)}"

    echo -e ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║   ACESSE O DASHBOARD OPENCLAW AGORA                      ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo -e ""
    echo -e "  ${WHITE}URL:${RESET}           ${BOLD}https://${OPENCLAW_DOMAIN}${RESET}"
    echo -e "  ${WHITE}Gateway Token:${RESET} ${BOLD}${OPENCLAW_GATEWAY_TOKEN}${RESET}"
    echo -e "  ${WHITE}WebSocket URL:${RESET} ${BOLD}wss://${OPENCLAW_DOMAIN}${RESET}"
    echo -e ""
    echo -e "  ${YELLOW}Passos no dashboard:${RESET}"
    echo -e "  ${ARROW} 1. Acesse a URL acima no navegador"
    echo -e "  ${ARROW} 2. Cole o Gateway Token e clique em ${BOLD}Connect${RESET}"
    echo -e "  ${ARROW} 3. Se aparecer ${BOLD}'device pairing required'${RESET}, volte aqui e informe o ID"
    echo -e ""

    # Verificar se há device pairing pendente
    if [ -n "$OC_CONTAINER" ]; then
        local PENDING_DEVICES
        PENDING_DEVICES=$(docker exec -u node "$OC_CONTAINER" \
            node dist/index.js devices list 2>/dev/null | grep -i "pending" || true)

        if [ -n "$PENDING_DEVICES" ]; then
            print_warning "Device pairing pendente detectado:"
            echo -e "${PENDING_DEVICES}"
            echo -e ""
            echo -ne "${CYAN}📱 Informe o Request ID para aprovar (Enter para pular): ${RESET}"; read OPENCLAW_DEVICE_ID < /dev/tty || true

            if [ -n "$OPENCLAW_DEVICE_ID" ]; then
                docker exec -u node "$OC_CONTAINER" \
                    node dist/index.js devices approve "$OPENCLAW_DEVICE_ID" 2>/dev/null || true
                print_success "Device aprovado: ${OPENCLAW_DEVICE_ID}"
            fi
        fi
    fi

    echo -e ""
    echo -ne "${GREEN}✔ Pressione Enter quando estiver conectado ao dashboard e pronto para continuar: ${RESET}"; read _DASHBOARD_CONFIRM < /dev/tty || true
    echo -e ""
}

# ---------------------------------------------------------------------------
# Aplica todas as configurações via CLI openclaw config set
# ---------------------------------------------------------------------------
configure_openclaw() {
    if [ "$ENABLE_OPENCLAW" != true ]; then return; fi

    print_step "APLICANDO CONFIGURAÇÕES VIA CLI"

    local OC_CONTAINER="${_OC_CONTAINER:-$(docker ps -q -f name=openclaw_openclaw_gateway)}"

    if [ -z "$OC_CONTAINER" ]; then
        print_error "Container não encontrado. Pós-configuração manual necessária."
        _print_openclaw_manual_steps
        return
    fi

    # Helper: executa o CLI openclaw dentro do container
    oc_exec() {
        docker exec -u node "$OC_CONTAINER" node dist/index.js "$@" 2>/dev/null
    }

    # 1. Gateway mode
    print_info "Configurando gateway.mode = local..."
    if oc_exec config set gateway.mode local; then
        print_success "gateway.mode = local ✔"
    else
        print_warning "Falha ao configurar gateway.mode (tente manualmente)"
    fi

    # 2. Allowed Origins + trustedProxies inicial (vazio, vai ser atualizado abaixo)
    print_info "Configurando CORS — allowed origins para https://${OPENCLAW_DOMAIN}..."
    oc_exec config set --batch-json "[
        {\"path\":\"gateway.controlUi.allowedOrigins\",
         \"value\":[
           \"http://localhost:18789\",
           \"http://127.0.0.1:18789\",
           \"https://${OPENCLAW_DOMAIN}\"
         ]
        }
    ]" 2>/dev/null && print_success "allowedOrigins configurado ✔" || \
        print_warning "Falha ao configurar allowedOrigins"

    # 3. Descobrir IP do Traefik nos logs e configurar trustedProxies
    print_info "Detectando IP do Traefik para trustedProxies..."
    local TRAEFIK_IP
    TRAEFIK_IP=$(docker service logs openclaw_openclaw_gateway 2>/dev/null \
        | grep -oP '(?<=peer=)\d+\.\d+\.\d+\.\d+' | head -1)

    if [ -n "$TRAEFIK_IP" ]; then
        oc_exec config set --batch-json \
            "[{\"path\":\"gateway.trustedProxies\",\"value\":[\"${TRAEFIK_IP}\"]}]" \
            2>/dev/null && print_success "trustedProxies = ${TRAEFIK_IP} ✔" || \
            print_warning "Falha ao configurar trustedProxies"
    else
        print_warning "IP do Traefik não detectado nos logs ainda."
        echo -e "  ${DIM}Execute depois: docker service logs openclaw_openclaw_gateway | grep 'peer='${RESET}"
        echo -e "  ${DIM}Depois: openclaw config set --batch-json '[{\"path\":\"gateway.trustedProxies\",\"value\":[\"IP\"]}]'${RESET}"
    fi

    # 4. OpenAI API Key (só se foi informada)
    if [ -n "$OPENCLAW_OPENAI_API_KEY" ]; then
        print_info "Configurando OpenAI API Key..."
        oc_exec config set agents.main.auth.openai.apiKey "${OPENCLAW_OPENAI_API_KEY}" \
            2>/dev/null && print_success "OpenAI API Key configurada ✔" || \
            print_warning "Falha ao configurar OpenAI API Key"
    else
        print_warning "OpenAI API Key não informada — configure depois:"
        echo -e "  ${DIM}openclaw config set agents.main.auth.openai.apiKey sk-...${RESET}"
    fi

    # 5. Telegram command owner (se token foi informado)
    if [ -n "$OPENCLAW_TELEGRAM_TOKEN" ]; then
        print_info "Telegram configurado — informe seu Telegram ID numérico para ser o command owner."
        echo -ne "${CYAN}📱 Telegram ID (ex: 123456789) — Enter para pular: ${RESET}"
        read OPENCLAW_TELEGRAM_OWNER_ID < /dev/tty || true

        if [ -n "$OPENCLAW_TELEGRAM_OWNER_ID" ]; then
            oc_exec config set commands.ownerAllowFrom \
                "[\"telegram:${OPENCLAW_TELEGRAM_OWNER_ID}\"]" 2>/dev/null && \
                print_success "command owner = telegram:${OPENCLAW_TELEGRAM_OWNER_ID} ✔" || \
                print_warning "Falha ao configurar command owner"
        fi
    fi

    # 6. Doctor — limpar skills incompatíveis com container
    print_info "Executando 'openclaw doctor --fix' (remove skills sem binários no container)..."
    oc_exec doctor --fix 2>/dev/null && print_success "Doctor OK ✔" || \
        print_warning "Doctor retornou aviso (verifique logs)"

    # 7. Alias CLI no servidor
    print_info "Criando alias 'openclaw' em /root/.bashrc..."
    if ! grep -q "alias openclaw=" /root/.bashrc 2>/dev/null; then
        # shellcheck disable=SC2016
        echo 'alias openclaw="docker exec -it $(docker ps --filter name=openclaw_openclaw_gateway -q) node dist/index.js"' \
            >> /root/.bashrc
        print_success "Alias adicionado — execute: source ~/.bashrc"
    else
        print_info "Alias já existe em /root/.bashrc"
    fi

    # 8. Reiniciar para aplicar todas as configs de uma vez
    print_info "Reiniciando serviço para aplicar configurações..."
    docker service update --force openclaw_openclaw_gateway >/dev/null 2>&1
    print_success "Serviço reiniciado ✔"

    print_success "Pós-configuração concluída!"
}

# ---------------------------------------------------------------------------
# Verificação final: confirma que o openclaw está respondendo após restart
# ---------------------------------------------------------------------------
_verify_openclaw_running() {
    print_step "VERIFICAÇÃO FINAL — OPENCLAW"

    print_info "Aguardando serviço estabilizar após restart (30s)..."
    sleep 30

    local OC_CONTAINER=""
    local HEALTHY=false

    for i in {1..10}; do
        OC_CONTAINER=$(docker ps -q -f name=openclaw_openclaw_gateway)
        if [ -n "$OC_CONTAINER" ]; then
            if docker exec "$OC_CONTAINER" \
                curl -fsS http://127.0.0.1:18789/healthz >/dev/null 2>&1; then
                HEALTHY=true
                break
            fi
        fi
        echo -ne "  ${INFO} ${CYAN}Verificando... (${i}/10)${RESET}\r"
        sleep 6
    done

    echo ""

    if [ "$HEALTHY" = true ]; then
        print_success "OpenClaw está ${BOLD}rodando e saudável${RESET} ✔"
        echo -e ""
        echo -e "  ${ARROW} Status do serviço:"
        docker service ls --filter name=openclaw_openclaw_gateway \
            --format "    {{.Name}}  replicas={{.Replicas}}  image={{.Image}}" 2>/dev/null || true
        echo -e ""
        echo -e "  ${ARROW} Últimas linhas do log:"
        docker service logs --tail 5 openclaw_openclaw_gateway 2>/dev/null \
            | sed 's/^/    /' || true
    else
        print_error "OpenClaw não respondeu ao healthcheck após restart."
        echo -e ""
        echo -e "  ${YELLOW}Diagnóstico:${RESET}"
        echo -e "  ${ARROW} Ver logs:    ${DIM}docker service logs -f openclaw_openclaw_gateway${RESET}"
        echo -e "  ${ARROW} Ver tarefas: ${DIM}docker service ps openclaw_openclaw_gateway${RESET}"
        echo -e "  ${ARROW} Forçar restart: ${DIM}docker service update --force openclaw_openclaw_gateway${RESET}"
        echo -e ""
        echo -e "  ${YELLOW}Erros comuns e soluções:${RESET}"
        echo -e "  ${ARROW} ${DIM}JSON5: invalid character${RESET} → config corrompida:"
        echo -e "       ${DIM}cp /opt/infra/${BUSINESS_NAME}/openclaw/openclaw.json.last-good /opt/infra/${BUSINESS_NAME}/openclaw/openclaw.json${RESET}"
        echo -e "  ${ARROW} ${DIM}Proxy headers from untrusted address${RESET} → trustedProxies não configurado:"
        echo -e "       ${DIM}openclaw config set --batch-json '[{\"path\":\"gateway.trustedProxies\",\"value\":[\"IP_TRAEFIK\"]}]'${RESET}"
        echo -e "  ${ARROW} ${DIM}gateway.mode is unset${RESET} → ${DIM}openclaw config set gateway.mode local${RESET}"
        echo -e "  ${ARROW} ${DIM}Permissão negada no volume${RESET} → ${DIM}chown -R 1000:1000 /opt/infra/${BUSINESS_NAME}/openclaw${RESET}"
    fi
}

# ---------------------------------------------------------------------------
# Passos manuais — exibido quando o container não é encontrado
# ---------------------------------------------------------------------------
_print_openclaw_manual_steps() {
    echo -e ""
    echo -e "${BOLD}${YELLOW}═══ Passos manuais pós-deploy do OpenClaw ═══${RESET}"
    echo -e "  1. Criar alias:"
    echo -e "     ${DIM}echo 'alias openclaw=\"docker exec -it \$(docker ps --filter name=openclaw_openclaw_gateway -q) node dist/index.js\"' >> ~/.bashrc && source ~/.bashrc${RESET}"
    echo -e "  2. Gateway mode:"
    echo -e "     ${DIM}openclaw config set gateway.mode local${RESET}"
    echo -e "  3. Allowed origins:"
    echo -e "     ${DIM}openclaw config set --batch-json '[{\"path\":\"gateway.controlUi.allowedOrigins\",\"value\":[\"https://${OPENCLAW_DOMAIN}\"]}]'${RESET}"
    echo -e "  4. Trusted proxies (substitua IP_TRAEFIK):"
    echo -e "     ${DIM}docker service logs openclaw_openclaw_gateway | grep 'peer='${RESET}"
    echo -e "     ${DIM}openclaw config set --batch-json '[{\"path\":\"gateway.trustedProxies\",\"value\":[\"IP_TRAEFIK\"]}]'${RESET}"
    echo -e "  5. OpenAI API Key:"
    echo -e "     ${DIM}openclaw config set agents.main.auth.openai.apiKey sk-...${RESET}"
    echo -e "  6. Doctor:"
    echo -e "     ${DIM}openclaw doctor --fix${RESET}"
    echo -e "  7. Restart:"
    echo -e "     ${DIM}docker service update --force openclaw_openclaw_gateway${RESET}"
    echo -e ""
}

# ---------------------------------------------------------------------------
# Resumo final — chamado em print_summary no deploy.sh
# ---------------------------------------------------------------------------
print_openclaw_summary() {
    if [ "$ENABLE_OPENCLAW" != true ]; then return; fi

    echo -e ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${GREEN}   CREDENCIAIS DE ACESSO — OPENCLAW${RESET}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${WHITE}URL Dashboard:${RESET}  https://${OPENCLAW_DOMAIN}"
    echo -e "  ${WHITE}WebSocket:${RESET}      wss://${OPENCLAW_DOMAIN}"
    echo -e "  ${WHITE}Gateway Token:${RESET}  ${OPENCLAW_GATEWAY_TOKEN}"
    echo -e "  ${WHITE}Hooks Token:${RESET}    ${OPENCLAW_HOOKS_TOKEN}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "  ${YELLOW}⚠️  SALVE ESTES TOKENS — não serão exibidos novamente!${RESET}"
    echo -e ""
    echo -e "${BOLD}${CYAN}📋 PRÓXIMOS PASSOS — OPENCLAW:${RESET}"
    echo -e "  ${ARROW} 1. Acesse https://${OPENCLAW_DOMAIN} e conecte com o Gateway Token"
    echo -e "  ${ARROW} 2. Confirme WebSocket URL: ${BOLD}wss://${OPENCLAW_DOMAIN}${RESET}"
    echo -e "  ${ARROW} 3. Se pedir device pairing:"
    echo -e "       ${DIM}openclaw devices approve SEU_REQUEST_ID${RESET}"
    echo -e "  ${ARROW} 4. Para ver token a qualquer momento:"
    echo -e "       ${DIM}docker exec -it \$(docker ps --filter name=openclaw_openclaw_gateway -q) printenv OPENCLAW_GATEWAY_TOKEN${RESET}"
    echo -e "  ${ARROW} 5. Verificar config atual:"
    echo -e "       ${DIM}openclaw config get${RESET}"
    echo -e ""
}
