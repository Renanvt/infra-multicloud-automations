#!/bin/bash

# ==============================================================================
#  TRAE AI - INFRASTRUCTURE SETUP
#  Modularized version of the original setup script
# ==============================================================================

# Quando rodando via curl|bash, redirecionar stdin para /dev/tty
# para evitar que o pipe do script seja consumido por funções com 'read'
if [ ! -t 0 ] && [ -e /dev/tty ]; then
    exec </dev/tty
fi

# Directory where the script is running
if [ -z "${BASH_SOURCE[0]}" ]; then
    # Running via pipe/curl - Use a temporary directory
    SCRIPT_DIR="/tmp/infra-installer-$(date +%s)"
    mkdir -p "$SCRIPT_DIR"
    echo "Running in installer mode. Downloading modules to $SCRIPT_DIR..."
else
    # Running from local file
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Repository Base URL (Adjust branch if needed)
REPO_BASE_URL="https://raw.githubusercontent.com/Renanvt/infra-cloud-aws-google/main"

# Function to ensure module exists and source it
ensure_module() {
    local module_path="$1"
    local local_file="$SCRIPT_DIR/$module_path"

    # Sempre baixar módulos frescos quando rodando em modo installer (curl | bash)
    # Em modo local (arquivo no disco), só baixa se não existir
    local FORCE_DOWNLOAD=false
    if [ -z "${BASH_SOURCE[0]}" ] || [[ "$SCRIPT_DIR" == /tmp/infra-installer-* ]]; then
        FORCE_DOWNLOAD=true
    fi

    if [ "$FORCE_DOWNLOAD" = true ] || [ ! -f "$local_file" ]; then
        mkdir -p "$(dirname "$local_file")"
        
        if command -v curl >/dev/null 2>&1; then
            HTTP_CODE=$(curl -sL -w "%{http_code}" "$REPO_BASE_URL/$module_path" -o "$local_file")
            if [ "$HTTP_CODE" -ne 200 ]; then
                echo "Error: Falha ao baixar $module_path (HTTP $HTTP_CODE)"
                rm -f "$local_file"
                exit 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "$local_file" "$REPO_BASE_URL/$module_path"
        else
            echo "Erro: curl ou wget não encontrados. Não foi possível baixar os módulos."
            exit 1
        fi
    fi

    source "$local_file"
}

# Load Modules (Order Matters)
MODULES=(
    "modules/shared/utils.sh"
    "modules/shared/inputs.sh"
    "modules/shared/backup.sh"
    "modules/core/setup.sh"
    "modules/core/inputs.sh"
    "modules/core/cloud.sh"
    "modules/core/resources.sh"
    "modules/core/yamls.sh"
    "modules/core/deploy.sh"
    "modules/n8n/setup.sh"
    "modules/evolution/setup.sh"
    "modules/dify/setup.sh"
    "modules/chatwoot/setup.sh"
    "modules/openclaw/setup.sh"
    "modules/postiz/setup.sh"
    "modules/prometheus/setup.sh"
    "modules/grafana/setup.sh"
    "modules/open-design/setup.sh"
    "modules/metabase/setup.sh"
    "modules/hermes/setup.sh"
)

for module in "${MODULES[@]}"; do
    ensure_module "$module"
done

# ==============================================================================
#  MAIN EXECUTION
# ==============================================================================

# 1. Initial Logging & Permissions
setup_logging
print_banner
check_root
detect_hardware

# 2. Business Configuration
print_step "CONFIGURAÇÃO DO NEGÓCIO"
while true; do
    echo -e "${CYAN}Informe o nome do seu negócio (ex: minhaempresa).${RESET}"
    echo -e "${DIM}Isso será usado para personalizar pastas, logs e backups.${RESET}"
    echo -e "${YELLOW}⚠️  Atenção: Use apenas letras minúsculas e números, tudo junto (sem espaços).${RESET}"
    read -p "$(echo -e ${GREEN}"Nome do Negócio: "${RESET})" INPUT_BUSINESS_NAME < /dev/tty || continue

    if [[ -z "$INPUT_BUSINESS_NAME" ]]; then
        print_error "Nome do negócio não pode ser vazio!"
        continue
    fi

    # Verificar se contém apenas letras minúsculas e números
    if [[ ! "$INPUT_BUSINESS_NAME" =~ ^[a-z0-9]+$ ]]; then
        print_error "Formato inválido! Use apenas letras minúsculas e números, sem espaços ou caracteres especiais."
        echo -e "Exemplo correto: ${BOLD}minhaempresa${RESET}"
        echo -e "Exemplo incorreto: ${RED}Minha Empresa${RESET}"
        continue
    fi
    
    BUSINESS_NAME="$INPUT_BUSINESS_NAME"
    break
done

print_success "Negócio configurado como: ${BOLD}$BUSINESS_NAME${RESET}"

# 3. Setup Directories
INSTALL_DIR="/opt/infra/${BUSINESS_NAME}"
LOG_DIR="/var/log/${BUSINESS_NAME}"
mkdir -p "$LOG_DIR"
CHECKPOINT_FILE="${LOG_DIR}/checkpoint"

# Update logging to business directory (if possible/needed)
# setup_logging # Calling again, though it might be skipped if LOGGING_ACTIVE is true

# Flags de módulos opcionais — inicializados como false antes do check_recovery,
# para que check_recovery possa sobrescrevê-los corretamente na restauração
ENABLE_DIFY=false
ENABLE_OPENCLAW=false
ENABLE_POSTIZ=false
ENABLE_PROMETHEUS=false
ENABLE_GRAFANA=false
ENABLE_OPEN_DESIGN=false
ENABLE_METABASE=false
ENABLE_HERMES=false
export ENABLE_DIFY ENABLE_OPENCLAW ENABLE_POSTIZ ENABLE_PROMETHEUS ENABLE_GRAFANA ENABLE_OPEN_DESIGN ENABLE_METABASE ENABLE_HERMES

check_recovery

log_message "INFO" "Iniciando setup para o negócio: $BUSINESS_NAME"

print_step "PREPARANDO DIRETÓRIO DE INSTALAÇÃO"
if [ ! -d "$INSTALL_DIR" ]; then
    print_info "Criando diretório: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
print_success "Diretório de trabalho definido: $(pwd)"
echo ""

# 4. Cloud Selection & Setup (Swarm Init + Docker)
print_step "SELEÇÃO DE NUVEM"
run_cloud_setup

# 4.1 Garantia de Swarm — roda sempre, independente de ser primeira execução ou rerun
# Se o Docker já estiver instalado e o Swarm não inicializado, corrige aqui
if command -v docker >/dev/null 2>&1; then
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        print_info "Swarm não está ativo — inicializando..."
        docker swarm init >/dev/null 2>&1 && print_success "Docker Swarm inicializado" \
            || print_warning "Falha ao inicializar Swarm (pode já estar em progresso)"
    fi
    if ! docker network ls 2>/dev/null | grep -q "network_swarm_public"; then
        docker network create --driver overlay --attachable network_swarm_public >/dev/null 2>&1 \
            && print_success "Rede 'network_swarm_public' criada" \
            || print_info "Rede 'network_swarm_public' já existe"
    fi
    docker node update --label-add app=n8n "$(hostname)" >/dev/null 2>&1 || true
fi

# 5. DNS Verification
verify_dns

# 6. Service Configuration (Inputs)
# Se credenciais foram restauradas do checkpoint anterior, pula toda a coleta
if [ "${CREDENTIALS_RESTORED:-false}" = true ]; then
    print_step "CONFIGURAÇÃO RESTAURADA"
    print_success "Credenciais da instalação anterior carregadas — pulando fase de configuração"
    echo -e "  ${DIM}Domínios, senhas e chaves mantidos da execução anterior.${RESET}"
else
    setup_core_vars
    setup_n8n_vars
    setup_evolution_vars
    setup_dify_vars      # Menu: escolhe Dify, OpenClaw ou nenhum
    setup_openclaw_vars  # Coleta inputs do OpenClaw (skip se ENABLE_OPENCLAW != true)
    setup_chatwoot_vars

    # Postiz — pergunta separada, independente do menu Dify/OpenClaw
    read -p "$(echo -e "${CYAN}📱 Deseja instalar o Postiz (gerenciador de redes sociais)? (s/n): ${RESET}")" _POSTIZ_OPT < /dev/tty || true
    if [[ "$_POSTIZ_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
        ENABLE_POSTIZ=true
        export ENABLE_POSTIZ
        setup_postiz_vars
    fi

    # Prometheus — monitoramento (instala Grafana e Node Exporter automaticamente)
    read -p "$(echo -e "${CYAN}📊 Deseja instalar o Prometheus + Grafana + Node Exporter (monitoramento)? (s/n): ${RESET}")" _PROM_OPT < /dev/tty || true
    if [[ "$_PROM_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
        ENABLE_PROMETHEUS=true
        ENABLE_GRAFANA=true
        export ENABLE_PROMETHEUS ENABLE_GRAFANA
        setup_prometheus_vars  # coleta vars do Prometheus e do Grafana juntos
    fi

    # Open Design — editor de design self-hosted
    read -p "$(echo -e "${CYAN}🎨 Deseja instalar o Open Design (editor de design)? (s/n): ${RESET}")" _OD_OPT < /dev/tty || true
    if [[ "$_OD_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
        ENABLE_OPEN_DESIGN=true
        export ENABLE_OPEN_DESIGN
        setup_open_design_vars
    fi

    # Metabase — BI e análise de dados
    read -p "$(echo -e "${CYAN}📊 Deseja instalar o Metabase (BI / análise de dados)? (s/n): ${RESET}")" _MB_OPT < /dev/tty || true
    if [[ "$_MB_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
        ENABLE_METABASE=true
        export ENABLE_METABASE
        setup_metabase_vars
    fi

    # Hermes Agent — comportamento depende da RAM disponível
    : "${TOTAL_RAM_MB:=0}"
    read -p "$(echo -e "${CYAN}🤖 Deseja instalar o Hermes Agent (gateway IA)? (s/n): ${RESET}")" _HERMES_OPT < /dev/tty || true
    if [[ "$_HERMES_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
        ENABLE_HERMES=true
        # Em VMs com <= 8GB RAM instala sem Dashboard para economizar memória
        if [ "$TOTAL_RAM_MB" -le 8192 ]; then
            HERMES_DASHBOARD_ENABLED=false
            print_info "VM com ${TOTAL_RAM_MB}MB RAM — Hermes será instalado no modo Gateway-only (sem Dashboard)."
        else
            HERMES_DASHBOARD_ENABLED=true
        fi
        export ENABLE_HERMES HERMES_DASHBOARD_ENABLED
        setup_hermes_vars
    fi
fi

# 7. Resource Definition
print_banner
define_resources

# 8. Checkpoint
save_checkpoint "inputs_collected"
# Nota: save_credentials é chamado após o deploy para gravar flags corretas

# 9. YAML Generation
generate_core_yamls
generate_n8n_yamls
generate_evolution_yaml
generate_dify_yamls
generate_openclaw_yaml  # Gera 21.openclaw.yaml (skip se ENABLE_OPENCLAW != true)
generate_chatwoot_yaml

if [ "$ENABLE_POSTIZ" = true ]; then
    generate_postiz_yaml
fi

if [ "$ENABLE_PROMETHEUS" = true ]; then
    generate_prometheus_yaml
    generate_node_exporter_yaml
fi

if [ "$ENABLE_GRAFANA" = true ]; then
    generate_grafana_yaml
fi

if [ "$ENABLE_OPEN_DESIGN" = true ]; then
    generate_open_design_yaml
fi

if [ "$ENABLE_METABASE" = true ]; then
    generate_metabase_yaml
fi

if [ "$ENABLE_HERMES" = true ]; then
    generate_hermes_yaml
fi

print_success "Arquivos YAML gerados com sucesso!"

# Salvar credenciais agora — flags já estão com valores definitivos
save_credentials

# 10. Service Deployment
deploy_services || true

# 11. Final Summary — sempre executa, isolado em subshell para nao ser afetado por erros anteriores
( print_summary ) || true

# 12. Backup Setup (usa read — pode abortar em curl|bash, mas summary já foi exibido)
setup_auto_backup || true
run_backup_restore_menu || true
