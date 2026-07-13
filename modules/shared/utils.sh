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

# Salva TODAS as credenciais após coleta de inputs
# Chamado pelo install.sh após save_checkpoint "inputs_collected"
save_credentials() {
    local CRED_FILE="${LOG_DIR}/credentials.env"

    cat <<EOF > "$CRED_FILE"
# ===== CREDENCIAIS SALVAS — $(date '+%Y-%m-%d %H:%M:%S') =====
# Gerado automaticamente pelo instalador. NÃO compartilhe este arquivo.

# Core
TRAEFIK_EMAIL="${TRAEFIK_EMAIL:-}"
PORTAINER_DOMAIN="${PORTAINER_DOMAIN:-}"
RABBITMQ_DOMAIN="${RABBITMQ_DOMAIN:-}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
RABBITMQ_USER="${RABBITMQ_USER:-}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-}"

# N8N
N8N_EDITOR_DOMAIN="${N8N_EDITOR_DOMAIN:-}"
N8N_WEBHOOK_DOMAIN="${N8N_WEBHOOK_DOMAIN:-}"
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-}"

# Evolution
EVOLUTION_DOMAIN="${EVOLUTION_DOMAIN:-}"
EVOLUTION_API_KEY="${EVOLUTION_API_KEY:-}"

# Chatwoot
CHATWOOT_DOMAIN="${CHATWOOT_DOMAIN:-}"
CHATWOOT_ADMIN_EMAIL="${CHATWOOT_ADMIN_EMAIL:-}"
CHATWOOT_RESEND_API_KEY="${CHATWOOT_RESEND_API_KEY:-}"
CHATWOOT_SECRET_KEY="${CHATWOOT_SECRET_KEY:-}"
CHATWOOT_RESEND_CONFIGURED="${CHATWOOT_RESEND_CONFIGURED:-false}"
CHATWOOT_ADMIN_PASSWORD="${CHATWOOT_ADMIN_PASSWORD:-}"

# Módulos opcionais
ENABLE_DIFY="${ENABLE_DIFY:-false}"
ENABLE_OPENCLAW="${ENABLE_OPENCLAW:-false}"
ENABLE_POSTIZ="${ENABLE_POSTIZ:-false}"
ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS:-false}"
ENABLE_GRAFANA="${ENABLE_GRAFANA:-false}"
ENABLE_OPEN_DESIGN="${ENABLE_OPEN_DESIGN:-false}"
ENABLE_METABASE="${ENABLE_METABASE:-false}"
ENABLE_HERMES="${ENABLE_HERMES:-false}"
HERMES_DASHBOARD_ENABLED="${HERMES_DASHBOARD_ENABLED:-false}"

# Dify
DIFY_WEB_DOMAIN="${DIFY_WEB_DOMAIN:-}"
DIFY_API_DOMAIN="${DIFY_API_DOMAIN:-}"
DIFY_SECRET_KEY="${DIFY_SECRET_KEY:-}"
DIFY_INNER_API_KEY="${DIFY_INNER_API_KEY:-}"

# OpenClaw
OPENCLAW_DOMAIN="${OPENCLAW_DOMAIN:-}"
OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"
OPENCLAW_HOOKS_TOKEN="${OPENCLAW_HOOKS_TOKEN:-}"
OPENCLAW_OPENAI_API_KEY="${OPENCLAW_OPENAI_API_KEY:-}"

# Postiz
POSTIZ_DOMAIN="${POSTIZ_DOMAIN:-}"
POSTIZ_TEMPORAL_DOMAIN="${POSTIZ_TEMPORAL_DOMAIN:-}"
POSTIZ_JWT_SECRET="${POSTIZ_JWT_SECRET:-}"
POSTIZ_TEMPORAL_USER="${POSTIZ_TEMPORAL_USER:-}"
POSTIZ_TEMPORAL_PASSWORD="${POSTIZ_TEMPORAL_PASSWORD:-}"
POSTIZ_TEMPORAL_HASH="${POSTIZ_TEMPORAL_HASH:-}"

# Prometheus / Grafana
PROMETHEUS_DOMAIN="${PROMETHEUS_DOMAIN:-}"
PROMETHEUS_USER="${PROMETHEUS_USER:-}"
PROMETHEUS_PASSWORD="${PROMETHEUS_PASSWORD:-}"
GRAFANA_DOMAIN="${GRAFANA_DOMAIN:-}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-}"

# Open Design
OPEN_DESIGN_DOMAIN="${OPEN_DESIGN_DOMAIN:-}"
OPEN_DESIGN_USER="${OPEN_DESIGN_USER:-}"
OPEN_DESIGN_PASSWORD="${OPEN_DESIGN_PASSWORD:-}"

# Metabase
METABASE_DOMAIN="${METABASE_DOMAIN:-}"

# Hermes
HERMES_DOMAIN="${HERMES_DOMAIN:-}"
HERMES_DASHBOARD_DOMAIN="${HERMES_DASHBOARD_DOMAIN:-}"
EOF

    chmod 600 "$CRED_FILE"
    log_message "INFO" "Credenciais salvas em $CRED_FILE"
}

check_recovery() {
    if [ ! -f "$CHECKPOINT_FILE" ]; then return; fi

    LAST_POINT=$(cat "$CHECKPOINT_FILE")

    # Carregar variáveis de estado básicas
    if [ -f "${LOG_DIR}/variables.env" ]; then
        source "${LOG_DIR}/variables.env"
    fi

    # Traduzir checkpoint para linguagem humana
    local LAST_POINT_LABEL
    case "$LAST_POINT" in
        inputs_collected) LAST_POINT_LABEL="todas as configurações foram coletadas (senhas, domínios, chaves)" ;;
        docker_installed) LAST_POINT_LABEL="Docker foi instalado com sucesso" ;;
        swarm_initialized) LAST_POINT_LABEL="Docker Swarm foi inicializado" ;;
        yamls_generated)  LAST_POINT_LABEL="todos os arquivos YAML foram gerados" ;;
        deploy_started)   LAST_POINT_LABEL="deploy dos serviços foi iniciado" ;;
        *)                LAST_POINT_LABEL="$LAST_POINT" ;;
    esac

    echo -e ""
    echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${YELLOW}║   ⚠️  EXECUÇÃO ANTERIOR DETECTADA                        ║${RESET}"
    echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo -e ""
    echo -e "  ${WHITE}Último passo concluído:${RESET} ${BOLD}${GREEN}${LAST_POINT_LABEL}${RESET}"
    echo -e ""

    # Se temos credenciais salvas, oferecer para reutilizá-las
    local CRED_FILE="${LOG_DIR}/credentials.env"
    if [ "$LAST_POINT" = "inputs_collected" ] && [ -f "$CRED_FILE" ]; then
        echo -e "  ${WHITE}Credenciais da instalação anterior:${RESET}"
        echo -e ""

        # Mostrar credenciais relevantes (sem exibir senhas completas — trunca no meio)
        _show_masked() {
            local LABEL="$1"
            local VALUE="$2"
            if [ -z "$VALUE" ] || [ "$VALUE" = '""' ] || [ "$VALUE" = "" ]; then return; fi
            # Remove aspas
            VALUE="${VALUE//\"/}"
            # Mascarar: mostra 4 chars + *** + 4 chars finais se > 10 chars
            local LEN="${#VALUE}"
            if [ "$LEN" -gt 10 ]; then
                echo -e "    ${DIM}${LABEL}:${RESET} ${VALUE:0:4}***${VALUE: -4}"
            else
                echo -e "    ${DIM}${LABEL}:${RESET} ${VALUE}"
            fi
        }

        # Ler e exibir credenciais
        while IFS='=' read -r KEY RAW_VAL; do
            [[ "$KEY" =~ ^#.*$ || -z "$KEY" ]] && continue
            RAW_VAL="${RAW_VAL//\"/}"
            case "$KEY" in
                TRAEFIK_EMAIL)        _show_masked "Email SSL (Traefik)"    "$RAW_VAL" ;;
                PORTAINER_DOMAIN)     _show_masked "Portainer"              "$RAW_VAL" ;;
                POSTGRES_PASSWORD)    _show_masked "Senha Postgres"         "$RAW_VAL" ;;
                REDIS_PASSWORD)       _show_masked "Senha Redis"            "$RAW_VAL" ;;
                N8N_EDITOR_DOMAIN)    _show_masked "N8N Editor"             "$RAW_VAL" ;;
                N8N_ENCRYPTION_KEY)   _show_masked "N8N Encryption Key"     "$RAW_VAL" ;;
                EVOLUTION_DOMAIN)     _show_masked "Evolution API"          "$RAW_VAL" ;;
                EVOLUTION_API_KEY)    _show_masked "Evolution API Key"      "$RAW_VAL" ;;
                CHATWOOT_DOMAIN)      _show_masked "Chatwoot"               "$RAW_VAL" ;;
                CHATWOOT_ADMIN_EMAIL) _show_masked "Chatwoot Email"         "$RAW_VAL" ;;
            esac
        done < "$CRED_FILE"

        echo -e ""
        echo -e "  ${WHITE}Deseja manter as credenciais da instalação anterior?${RESET}"
        echo -e ""
        echo -e "  ${CYAN}[1] Manter credenciais${RESET}  — continua com as mesmas senhas e domínios"
        echo -e "  ${CYAN}[2] Criar novas${RESET}          — descarta tudo e reconfigura do zero"
        echo -e ""

        local CRED_CHOICE=""
        while true; do
            read -p "$(echo -e "${GREEN}Opção (1/2): ${RESET}")" CRED_CHOICE < /dev/tty || true
            case "$CRED_CHOICE" in
                1)
                    print_info "Carregando credenciais anteriores..."
                    source "$CRED_FILE"
                    export CREDENTIALS_RESTORED=true

                    # Reativar flags de módulos opcionais baseado nos domínios configurados
                    # (as flags podem ter sido salvas como false se save_credentials rodou cedo demais)
                    [ -n "$POSTIZ_DOMAIN" ]        && ENABLE_POSTIZ=true
                    [ -n "$PROMETHEUS_DOMAIN" ]    && ENABLE_PROMETHEUS=true && ENABLE_GRAFANA=true
                    [ -n "$GRAFANA_DOMAIN" ]       && ENABLE_GRAFANA=true
                    [ -n "$OPEN_DESIGN_DOMAIN" ]   && ENABLE_OPEN_DESIGN=true
                    [ -n "$METABASE_DOMAIN" ]      && ENABLE_METABASE=true
                    [ -n "$HERMES_DOMAIN" ]        && ENABLE_HERMES=true
                    [ -n "$OPENCLAW_DOMAIN" ]      && ENABLE_OPENCLAW=true
                    [ -n "$DIFY_WEB_DOMAIN" ]      && ENABLE_DIFY=true
                    # HERMES_DASHBOARD_ENABLED baseado no domínio do dashboard
                    [ -n "$HERMES_DASHBOARD_DOMAIN" ] && HERMES_DASHBOARD_ENABLED=true || HERMES_DASHBOARD_ENABLED=false

                    # Exportar tudo
                    export ENABLE_DIFY ENABLE_OPENCLAW ENABLE_POSTIZ
                    export ENABLE_PROMETHEUS ENABLE_GRAFANA ENABLE_OPEN_DESIGN
                    export ENABLE_METABASE ENABLE_HERMES HERMES_DASHBOARD_ENABLED
                    print_success "Credenciais restauradas — etapa de configuração será pulada"
                    break
                    ;;
                2)
                    print_info "Descartando credenciais anteriores..."
                    rm -f "$CHECKPOINT_FILE" "$CRED_FILE" "${LOG_DIR}/variables.env"
                    export CREDENTIALS_RESTORED=false
                    print_success "Iniciando configuração do zero"
                    break
                    ;;
                *)
                    print_error "Opção inválida. Digite 1 ou 2."
                    ;;
            esac
        done
    else
        echo -e "  ${DIM}O script será retomado a partir do ponto onde parou.${RESET}"
        echo -e "  ${DIM}Para começar do zero: rm ${CHECKPOINT_FILE}${RESET}"
        sleep 3
    fi

    echo -e ""
    log_message "WARN" "Recovery detectado em: $LAST_POINT"
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
    echo -e "${CYAN}  _   _    ___    _   _         ____    ___   _____  __   __       _   _ _____ ____  __  __ _____ ____  ${RESET}"
    echo -e "${CYAN} | \ | |  ( _ )  | \ | |   +   |  _ \  |_ _| |  ___| \ \ / /   +  | | | | ____|  _ \|  \/  | ____/ ___| ${RESET}"
    echo -e "${CYAN} |  \| |  / _ \  |  \| |       | | | |  | |  | |_     \ V /       | |_| |  _| | |_) | |\/| |  _| \___ \ ${RESET}"
    echo -e "${CYAN} | |\  | | (_) | | |\  |   +   | |_| |  | |  |  _|     | |     +  |  _  | |___|  _ <| |  | | |___ ___) |${RESET}"
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
