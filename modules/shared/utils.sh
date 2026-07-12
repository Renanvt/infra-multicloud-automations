#!/bin/bash

# ===== CORES ANSI =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Ícones
CHECK="${GREEN}✓${RESET}"
CROSS="${RED}✗${RESET}"
ARROW="${CYAN}→${RESET}"
WARN="${YELLOW}⚠${RESET}"
INFO="${BLUE}ℹ${RESET}"
ROCKET="${MAGENTA}🚀${RESET}"

# ===== VARIÁVEIS GLOBAIS =====
INSTALL_DIR="/opt/infra"
LOG_DIR="/var/log/infra_setup"
CHECKPOINT_FILE="/var/log/infra_setup/checkpoint"
BUSINESS_NAME=""

# ===== FUNÇÕES DE LOG E RESILIÊNCIA =====
setup_logging() {
    mkdir -p "$LOG_DIR"
    # Redireciona stdout e stderr para log, mas mantém no terminal (tee)
    # Executado apenas se não estivermos já dentro de uma subshell de log
    if [ -z "$LOGGING_ACTIVE" ]; then
        export LOGGING_ACTIVE=true
        exec > >(tee -a "${LOG_DIR}/setup_$(date +%Y%m%d).log") 2>&1
    fi
}

log_message() {
    local LEVEL=$1
    local MSG=$2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$LEVEL] $MSG" >> "${LOG_DIR}/detailed.log"
}

save_checkpoint() {
    local STEP_NAME="$1"
    echo "$STEP_NAME" > "$CHECKPOINT_FILE"
    
    # Salvar variáveis de estado críticas para recuperação
    cat <<EOF > "${LOG_DIR}/variables.env"
BUSINESS_NAME="${BUSINESS_NAME}"
CLOUD_OPTION="${CLOUD_OPTION}"
EOF
    
    log_message "INFO" "Checkpoint salvo: $STEP_NAME"
}

check_recovery() {
    if [ -f "$CHECKPOINT_FILE" ]; then
        LAST_POINT=$(cat "$CHECKPOINT_FILE")
        
        # Carregar variáveis de estado se existirem
        if [ -f "${LOG_DIR}/variables.env" ]; then
             source "${LOG_DIR}/variables.env"
        fi

        print_warning "Recuperação de falha detectada. Último passo concluído: $LAST_POINT"
        log_message "WARN" "Sistema recuperado após falha em: $LAST_POINT"
        echo -e "${YELLOW}O script foi interrompido anteriormente. Tentando retomar...${RESET}"
        sleep 2
    fi
}

# Tratamento de Erros
handle_error() {
    local LINE=$1
    local CMD=$2
    log_message "ERROR" "Falha na linha $LINE: $CMD"
}

# Tratamento de Interrupção (Ctrl+C)
handle_sigint() {
    echo ""
    echo -e "${YELLOW}⚠️  Interrupção detectada (Ctrl+C).${RESET}"
    # Usa || true para evitar que o set -e mate o script se o read falhar
    read -p "$(echo -e ${RED}"Você deseja realmente sair? (s/n): "${RESET})" CONFIRM_EXIT < /dev/tty || true
    if [[ "$CONFIRM_EXIT" =~ ^(s|S|sim|SIM)$ ]]; then
        print_error "Instalação cancelada pelo usuário."
        exit 1
    else
        echo -e "${GREEN}Continuando...${RESET}"
    fi
}

# ===== FUNÇÕES DE UI =====
detect_hardware() {
    # Detecta RAM Total em MB
    if [ -r /proc/meminfo ]; then
        TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        TOTAL_RAM_MB=$(echo "$TOTAL_RAM_KB / 1024" | bc)
    else
        TOTAL_RAM_MB=$(free -m | grep Mem | awk '{print $2}')
    fi

    # Detecta vCPUs
    TOTAL_CPU_CORES=$(nproc)

    # Fallback caso falhe
    if [ -z "$TOTAL_RAM_MB" ]; then TOTAL_RAM_MB=0; fi
    if [ -z "$TOTAL_CPU_CORES" ]; then TOTAL_CPU_CORES=1; fi

    export TOTAL_RAM_MB
    export TOTAL_CPU_CORES
}

print_banner() {
    clear
    echo -e "${CYAN}  _   _    ___    _   _         ____    ___   _____  __   __    +   _   _ _____ ____  __  __ _____ ____  ${RESET}"
    echo -e "${CYAN} | \ | |  ( _ )  | \ | |   +   |  _ \  |_ _| |  ___| \ \ / /   +  | | | | ____|  _ \|  \/  | ____/ ___| ${RESET}"
    echo -e "${CYAN} |  \| |  / _ \  |  \| |       | | | |  | |  | |_     \ V /       | |_| |  _| | |_) | |\/| |  _| \___ \ ${RESET}"
    echo -e "${CYAN} | |\  | | (_) | | |\  |   +   | |_| |  | |  |  _|     | |        |  _  | |___|  _ <| |  | | |___ ___) |${RESET}"
    echo -e "${CYAN} |_| \_|  \___/  |_| \_|       |____/  |___| |_|       |_|        |_| |_|_____|_| \_\_|  |_|_____|____/ ${RESET}"
    echo -e "${CYAN}                                                                                                          ${RESET}"
    echo -e "${CYAN}                    N8N + EVOLUTION + DIFY + HERMES + DOCKER SWARM - v2.0                                ${RESET}"
    echo ""
}

print_step() {
    echo -e "\n${BOLD}${BLUE}▶${RESET} ${BOLD}$1${RESET}"
}

print_success() {
    echo -e "  ${CHECK} ${GREEN}$1${RESET}"
}

print_error() {
    echo -e "  ${CROSS} ${RED}$1${RESET}"
}

print_warning() {
    echo -e "  ${WARN} ${YELLOW}$1${RESET}"
}

print_info() {
    echo -e "  ${INFO} ${CYAN}$1${RESET}"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [${CYAN}%c${RESET}] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then 
       echo -e "${RED}Este script precisa ser executado como root (sudo su)${RESET}"
       exit 1
    fi

    # Garantir dependências básicas — compatível com Debian 12/13 e Ubuntu 22.04/24.04
    local MISSING=()
    for cmd in curl sudo git openssl bc; do
        command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
    done
    # lsb-release pode não estar presente no Debian 13 minimal
    dpkg -l lsb-release &>/dev/null 2>&1 || MISSING+=("lsb-release")

    if [ ${#MISSING[@]} -gt 0 ]; then
        echo -e "${YELLOW}Instalando dependências básicas: ${MISSING[*]}...${RESET}"
        apt-get update -y >/dev/null 2>&1
        apt-get install -y "${MISSING[@]}"
    fi
}
