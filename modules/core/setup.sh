#!/bin/bash

# ---------------------------------------------------------------------------
# Configura swap memory se a VM tiver 8 GB de RAM ou menos
# Swap = metade da RAM, mínimo 2 GB, máximo 4 GB
# Só cria se não existir swap ativo no sistema
# ---------------------------------------------------------------------------
_setup_swap_if_needed() {
    : "${TOTAL_RAM_MB:=0}"

    # Verificar se já existe swap ativo
    local CURRENT_SWAP
    CURRENT_SWAP=$(free -m | awk '/^Swap:/ {print $2}')

    if [ "${CURRENT_SWAP:-0}" -gt 0 ]; then
        print_info "Swap já configurado (${CURRENT_SWAP}MB) — pulando."
        return
    fi

    if [ "$TOTAL_RAM_MB" -le 8192 ]; then
        print_step "CONFIGURANDO SWAP MEMORY"
        echo -e "  ${YELLOW}VM com ${TOTAL_RAM_MB}MB RAM detectada — criando swap para estabilidade.${RESET}"

        # Calcular tamanho: metade da RAM, entre 2G e 4G
        local SWAP_MB=$(( TOTAL_RAM_MB / 2 ))
        [ "$SWAP_MB" -lt 2048 ] && SWAP_MB=2048
        [ "$SWAP_MB" -gt 4096 ] && SWAP_MB=4096
        local SWAP_GB=$(( SWAP_MB / 1024 ))

        local SWAP_FILE="/swapfile"

        print_info "Criando swap de ${SWAP_GB}G em ${SWAP_FILE}..."

        # Criar o arquivo de swap
        if fallocate -l "${SWAP_GB}G" "$SWAP_FILE" 2>/dev/null || \
           dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_MB" 2>/dev/null; then

            chmod 600 "$SWAP_FILE"
            mkswap "$SWAP_FILE" >/dev/null
            swapon "$SWAP_FILE"
            print_success "Swap de ${SWAP_GB}G ativado"

            # Persistir no fstab para sobreviver a reboots
            if ! grep -q "$SWAP_FILE" /etc/fstab; then
                echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab
                print_success "Swap adicionado ao /etc/fstab (persiste após reboot)"
            fi

            # Ajustar swappiness para uso conservador (só usa swap em último caso)
            sysctl -w vm.swappiness=10 >/dev/null 2>&1
            if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
                echo "vm.swappiness=10" >> /etc/sysctl.conf
            fi

            print_success "vm.swappiness=10 configurado (uso conservador)"
            echo -e "  ${DIM}Swap ativo: $(free -h | awk '/^Swap:/ {print $2}')${RESET}"
        else
            print_warning "Não foi possível criar o arquivo de swap — espaço em disco insuficiente?"
        fi
    else
        print_info "VM com ${TOTAL_RAM_MB}MB RAM — swap não necessário."
    fi
}

setup_swarm_architecture() {
    # ── Swap memory para VMs com ≤ 8 GB de RAM ────────────────────────────
    _setup_swap_if_needed

    # Inicializar Swarm
    if ! docker info | grep -q "Swarm: active"; then
        print_info "Inicializando Docker Swarm..."
        docker swarm init > /dev/null 2>&1 || print_warning "Swarm já iniciado ou erro ao iniciar"
    fi
    
    # Criar rede pública
    if ! docker network ls | grep -q "network_swarm_public"; then
        docker network create --driver overlay --attachable network_swarm_public
        print_success "Rede 'network_swarm_public' criada"
    fi

    # Criar volumes externos necessários
    print_info "Criando volumes persistentes..."
    docker volume create volume_swarm_shared >/dev/null
    docker volume create volume_swarm_certificates >/dev/null
    docker volume create portainer_data >/dev/null
    docker volume create postgres_data >/dev/null
    docker volume create redis_data >/dev/null
    print_success "Volumes criados"

    # Passo 1.1 Configuração Multi-VM (Labeling)
    print_step "CONFIGURAÇÃO DE NÓS (LABELING)"
    echo -e "${YELLOW}Aplicando label 'app=n8n' neste nó (Manager)...${RESET}"
    docker node update --label-add app=n8n $(hostname) >/dev/null 2>&1
    print_success "Label 'app=n8n' aplicada"
}

verify_dns() {
    # Aviso DNS Cloudflare
    print_banner
    print_step "PASSO 1: VERIFICAÇÃO DE DNS (CLOUDFLARE)"
    echo -e "${YELLOW}Antes de continuar, certifique-se de que os apontamentos DNS foram feitos:${RESET}"
    echo -e "Exemplo de configuração (substitua '${BOLD}meu-dominio.com.br${RESET}' pelo seu):"
    echo -e ""
    echo -e "   ${BOLD}1. Registro A (Principal):${RESET}"
    echo -e "      Nome: ${CYAN}automations${RESET} → IP: ${BOLD}IP_VM${RESET}"
    echo -e ""
    echo -e "   ${BOLD}2. Registros CNAME (Apontando para 'automations.meu-dominio.com.br'):${RESET}"
    echo -e "      - ${CYAN}painel${RESET}  (Portainer)"
    echo -e "      - ${CYAN}n8neditor${RESET}        (N8N Editor)"
    echo -e "      - ${CYAN}n8nwebhook${RESET}          (N8N Webhook)"
    echo -e "      - ${CYAN}rabbit${RESET}         (RabbitMQ)"
    echo -e "      - ${CYAN}evolutionapi${RESET}     (Evolution API)"
    echo -e "      - ${CYAN}difyapi${RESET}       (Dify API - Opcional)"
    echo -e "      - ${CYAN}difyeditor${RESET}       (Dify Web - Opcional)"
    echo -e "      - ${CYAN}openclaw${RESET}      (OpenClaw - Opcional)"
    echo -e "      - ${CYAN}postiz${RESET}        (Postiz - Opcional)"
    echo -e "      - ${CYAN}postiz-temporal${RESET} (Postiz Temporal UI - Opcional)"
    echo -e "      - ${CYAN}prometheus${RESET}    (Prometheus - Opcional)"
    echo -e "      - ${CYAN}grafana${RESET}       (Grafana - Opcional)"
    echo -e "      - ${CYAN}design${RESET}        (Open Design - Opcional)"
    echo -e "      - ${CYAN}metabase${RESET}      (Metabase - Opcional)"
    echo -e ""
    echo -e "${DIM}Sugestão: Você pode usar outros prefixos como 'portainer', 'n8n', 'api', etc.${RESET}"
    echo -e "4. Use 'DNS Only' (Nuvem Cinza) no Cloudflare inicialmente para gerar SSL"
    echo -e ""
    echo -e "${BOLD}${YELLOW}📱 POSTIZ — API Keys de Redes Sociais:${RESET}"
    echo -e "   ${YELLOW}Se for instalar o Postiz, você precisará de App IDs / Client IDs de cada${RESET}"
    echo -e "   ${YELLOW}rede social que deseja conectar. Obtenha-os nos portais de desenvolvedores:${RESET}"
    echo -e "   ${ARROW} Meta (Facebook/Instagram): ${DIM}developers.facebook.com${RESET}"
    echo -e "   ${ARROW} Google (YouTube):          ${DIM}console.cloud.google.com${RESET}"
    echo -e "   ${ARROW} X (Twitter):               ${DIM}developer.x.com${RESET}"
    echo -e "   ${ARROW} LinkedIn:                  ${DIM}developer.linkedin.com${RESET}"
    echo -e "   ${ARROW} TikTok:                    ${DIM}developers.tiktok.com${RESET}"
    echo -e "   ${DIM}Você pode pular qualquer rede agora e configurar depois no painel do Postiz.${RESET}"
    read -p "$(echo -e ${BOLD}${GREEN}"Os DNS estão configurados corretamente? (s/n): "${RESET})" DNS_CONFIRM < /dev/tty
    if [[ ! "$DNS_CONFIRM" =~ ^(s|S|sim|SIM)$ ]]; then 
        print_error "Configure o DNS e execute novamente."
        exit 0
    fi
    print_banner
}
