#!/bin/bash

install_docker() {
    if ! command -v docker &> /dev/null; then
        print_info "Instalando Docker..."
        {
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
            systemctl enable docker
            systemctl start docker
            rm -f get-docker.sh
        } > /tmp/docker_install.log 2>&1 &
        spinner $!
        print_success "Docker Instalado"
    else
        print_success "Docker já está instalado"
    fi
}

# Detecta se é Debian ou Ubuntu e retorna "debian" ou "ubuntu"
_detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID:-debian}"
    else
        echo "debian"
    fi
}

# Instala awscli de forma compatível:
# - Ubuntu 24.04+: pip3 (o pacote apt está desatualizado)
# - Debian / Ubuntu < 24.04: apt
_install_awscli() {
    if command -v aws &>/dev/null; then
        print_info "AWS CLI já instalado"
        return
    fi

    . /etc/os-release 2>/dev/null || true
    local DISTRO="${ID:-debian}"
    local VERSION_NUM="${VERSION_ID:-0}"

    # Ubuntu 24+ → instalar via pip para ter versão atual
    if [[ "$DISTRO" == "ubuntu" ]] && \
       [[ "$(echo "$VERSION_NUM >= 24.04" | bc -l 2>/dev/null || echo 0)" == "1" ]]; then
        print_info "Ubuntu 24+ detectado — instalando AWS CLI via pip3..."
        apt-get install -y python3-pip python3-venv >/dev/null 2>&1
        pip3 install awscli --break-system-packages >/dev/null 2>&1 || \
            pip3 install awscli >/dev/null 2>&1
    else
        apt-get install -y awscli >/dev/null 2>&1
    fi
}

setup_aws() {
    print_step "INICIANDO SETUP AWS (DOCKER SWARM)"
    
    check_root

    echo -e "${YELLOW}⚠️  Você escolheu o setup AWS (Swarm Architecture)${RESET}"
    read -p "$(echo -e ${BOLD}${GREEN}"Confirmar instalação AWS? (s/n): "${RESET})" CONFIRM_AWS < /dev/tty
    if [[ ! "$CONFIRM_AWS" =~ ^(s|S|sim|SIM)$ ]]; then return 1; fi

    IS_AWS=true
    CLOUD_PROVIDER="aws"

    read -p "$(echo -e ${CYAN}"🗝️  Access Key: "${RESET})" AWS_ACCESS_KEY_ID < /dev/tty
    read -p "$(echo -e ${CYAN}"🔒 AWS_SECRET_ACCESS_KEY: "${RESET})" AWS_SECRET_ACCESS_KEY < /dev/tty
    echo ""
    read -p "$(echo -e ${CYAN}"🌍 Região AWS (ex: us-east-1): "${RESET})" S3_REGION < /dev/tty
    read -p "$(echo -e ${CYAN}"🪣 Nome do Bucket S3: "${RESET})" S3_BUCKET_NAME < /dev/tty
    echo ""

    print_step "PREPARANDO AMBIENTE AWS"
    {
        apt-get update -y
        apt-get upgrade -y
        apt-get install -y unzip curl bc python3 python3-pip
    } > /tmp/aws_setup.log 2>&1 &
    spinner $!

    install_docker
    _install_awscli

    print_info "Configurando AWS CLI..."
    mkdir -p /root/.aws
    cat > /root/.aws/credentials <<EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
    cat > /root/.aws/config <<EOF
[default]
region = $S3_REGION
output = json
EOF

    setup_swarm_architecture
}

setup_gcp() {
    print_step "INICIANDO SETUP GOOGLE CLOUD (DOCKER SWARM)"
    
    check_root

    echo -e "${YELLOW}⚠️  Você escolheu o setup Google Cloud (Swarm Architecture)${RESET}"
    read -p "$(echo -e ${BOLD}${GREEN}"Confirmar instalação GCP? (s/n): "${RESET})" CONFIRM_GCP < /dev/tty
    if [[ ! "$CONFIRM_GCP" =~ ^(s|S|sim|SIM)$ ]]; then return 1; fi

    CLOUD_PROVIDER="gcp"

    print_banner
    print_step "PREPARANDO AMBIENTE GCP"
    print_warning "Esse processo pode demorar de 5 a 15 minutos, NÃO CANCELE!"
    {
        apt-get update -y
        apt-get upgrade -y
        apt-get install -y git curl gnupg lsb-release bc python3
    } > /tmp/gcp_update.log 2>&1 &
    spinner $!

    install_docker

    setup_swarm_architecture
}

setup_digitalocean() {
    print_step "INICIANDO SETUP DIGITALOCEAN (DOCKER SWARM)"

    check_root

    echo -e "${YELLOW}⚠️  Você escolheu o setup DigitalOcean (Droplet / Swarm Architecture)${RESET}"
    read -p "$(echo -e ${BOLD}${GREEN}"Confirmar instalação DigitalOcean? (s/n): "${RESET})" CONFIRM_DO < /dev/tty
    if [[ ! "$CONFIRM_DO" =~ ^(s|S|sim|SIM)$ ]]; then return 1; fi

    CLOUD_PROVIDER="digitalocean"

    print_banner
    print_step "PREPARANDO AMBIENTE DIGITALOCEAN"
    print_warning "Esse processo pode demorar de 5 a 15 minutos, NÃO CANCELE!"
    {
        apt-get update -y
        apt-get upgrade -y
        apt-get install -y git curl gnupg lsb-release bc python3
    } > /tmp/do_update.log 2>&1 &
    spinner $!

    install_docker

    setup_swarm_architecture
}

select_cloud_provider() {
    local default_idx=${1:-0}
    local options=(
        "AWS (Single Node / Docker Swarm)"
        "Google Cloud (Multi Node / Docker Swarm)"
        "DigitalOcean - Droplet (Docker Swarm)"
    )
    local selected=$default_idx
    local key

    # Esconde cursor
    tput civis

    while true; do
        # Desenha menu
        echo -e "${CYAN}Use as setas ${BOLD}↑/↓${RESET}${CYAN} para navegar e ${BOLD}ENTER${RESET}${CYAN} para confirmar:${RESET}"
        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                echo -e "${GREEN}${BOLD}➜ ${options[$i]}${RESET}"
            else
                echo -e "  ${options[$i]}"
            fi
        done

        # Captura input explicitamente do TTY para evitar erros de redirecionamento
        if ! read -rsn1 key < /dev/tty; then
             sleep 1
             continue
        fi
        
        # Tratamento de teclas especiais (escape sequences para setas)
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key < /dev/tty || true
            if [[ "$key" == "[A" ]]; then # Seta Cima
                selected=$((selected - 1))
                if [ $selected -lt 0 ]; then selected=$((${#options[@]} - 1)); fi
            elif [[ "$key" == "[B" ]]; then # Seta Baixo
                selected=$((selected + 1))
                if [ $selected -ge ${#options[@]} ]; then selected=0; fi
            fi
        elif [[ "$key" == "" ]]; then # Enter
            break
        fi
        
        tput cuu $((${#options[@]} + 1)) || true
        tput ed || true
    done

    # Restaura cursor
    tput cnorm
    
    echo ""
    # Define variável global com a seleção
    MENU_SELECTION=$selected
    return 0
}

run_cloud_setup() {
    while true; do
        DEFAULT_INDEX=0
        if [[ -n "$CLOUD_OPTION" ]] && [[ "$CLOUD_OPTION" -ge 1 ]] && [[ "$CLOUD_OPTION" -le 2 ]]; then
            DEFAULT_INDEX=$(($CLOUD_OPTION - 1))
        fi

        select_cloud_provider $DEFAULT_INDEX
        CLOUD_OPTION=$(($MENU_SELECTION + 1))
        
        print_success "Opção selecionada: $CLOUD_OPTION"
        
        SETUP_STATUS=0
        case $CLOUD_OPTION in
            1)
                setup_aws
                SETUP_STATUS=$?
                ;;
            2)
                setup_gcp
                SETUP_STATUS=$?
                ;;
            3)
                setup_digitalocean
                SETUP_STATUS=$?
                ;;
            *)
                print_error "Opção inválida!"
                exit 1
                ;;
        esac

        if [ $SETUP_STATUS -eq 1 ]; then
            print_warning "Instalação cancelada pelo usuário. Retornando ao menu..."
            CLOUD_OPTION=""
            sleep 1
        else
            break
        fi
    done
}
