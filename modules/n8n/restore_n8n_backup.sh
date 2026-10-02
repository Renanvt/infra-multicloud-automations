#!/bin/bash

#################################################
# Script de Restauração de Backup N8N
# Restaura workflows e credenciais do GitHub
#################################################

set -e

# Configurações
RESTORE_ENABLED="${N8N_RESTORE_ENABLED:-false}"
GITHUB_BACKUP_REPO="${N8N_BACKUP_REPO:-}"
GITHUB_USERNAME="${N8N_BACKUP_USERNAME:-}"
GITHUB_TOKEN="${N8N_BACKUP_TOKEN:-}"
N8N_HOME="${N8N_HOME:-/home/node}"
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-}"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções de log
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verifica se restauração está habilitada
check_restore_enabled() {
    if [ "$RESTORE_ENABLED" != "true" ]; then
        log_warning "Restauração de backup não está habilitada (N8N_RESTORE_ENABLED=false)"
        log_info "Iniciando n8n sem restauração de backup..."
        return 1
    fi
    return 0
}

# Valida variáveis obrigatórias
validate_variables() {
    local missing_vars=()
    
    [ -z "$GITHUB_BACKUP_REPO" ] && missing_vars+=("N8N_BACKUP_REPO")
    [ -z "$GITHUB_USERNAME" ] && missing_vars+=("N8N_BACKUP_USERNAME")
    [ -z "$GITHUB_TOKEN" ] && missing_vars+=("N8N_BACKUP_TOKEN")
    [ -z "$N8N_ENCRYPTION_KEY" ] && missing_vars+=("N8N_ENCRYPTION_KEY")
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Variáveis obrigatórias não definidas: ${missing_vars[*]}"
        log_error "Configure as variáveis de ambiente para habilitar a restauração"
        return 1
    fi
    
    return 0
}

# Verifica se já existe backup local (evita restauração duplicada)
check_existing_data() {
    if [ -d "$N8N_HOME/.n8n" ]; then
        local workflow_count=$(find "$N8N_HOME/.n8n" -name "*.json" 2>/dev/null | wc -l)
        if [ "$workflow_count" -gt 0 ]; then
            log_warning "Dados do n8n já existem ($workflow_count arquivos encontrados)"
            log_warning "Pulando restauração para evitar sobrescrever dados existentes"
            return 1
        fi
    fi
    return 0
}

# Clone do repositório de backup
clone_backup_repo() {
    local backup_dir="$N8N_HOME/n8n-backup-temp"
    
    log_info "Clonando repositório de backup..."
    
    # Remove diretório se já existir
    rm -rf "$backup_dir"
    
    # Clone com autenticação
    local repo_url="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${GITHUB_BACKUP_REPO}.git"
    
    if git clone --depth 1 "$repo_url" "$backup_dir" 2>/dev/null; then
        log_success "Repositório clonado com sucesso"
        echo "$backup_dir"
        return 0
    else
        log_error "Falha ao clonar repositório"
        return 1
    fi
}

# Conta arquivos de backup
count_backup_files() {
    local backup_dir="$1"
    local workflows_count=0
    local credentials_count=0
    
    if [ -d "$backup_dir/workflows" ]; then
        workflows_count=$(find "$backup_dir/workflows" -name "*.json" 2>/dev/null | wc -l)
    fi
    
    if [ -d "$backup_dir/credentials" ]; then
        credentials_count=$(find "$backup_dir/credentials" -name "*.json" 2>/dev/null | wc -l)
    fi
    
    echo "$workflows_count $credentials_count"
}

# Prepara diretório do n8n
prepare_n8n_directory() {
    log_info "Preparando diretório do n8n..."
    
    mkdir -p "$N8N_HOME/.n8n"
    
    # Cria arquivo de configuração básico se não existir
    if [ ! -f "$N8N_HOME/.n8n/config" ]; then
        cat > "$N8N_HOME/.n8n/config" <<EOF
{
  "encryptionKey": "$N8N_ENCRYPTION_KEY"
}
EOF
        log_success "Arquivo de configuração criado"
    fi
}

# Importa workflows usando n8n CLI
import_workflows() {
    local backup_dir="$1"
    local workflows_dir="$backup_dir/workflows"
    
    if [ ! -d "$workflows_dir" ]; then
        log_warning "Diretório de workflows não encontrado"
        return 0
    fi
    
    local workflow_count=$(find "$workflows_dir" -name "*.json" 2>/dev/null | wc -l)
    
    if [ "$workflow_count" -eq 0 ]; then
        log_warning "Nenhum workflow encontrado para importar"
        return 0
    fi
    
    log_info "Importando $workflow_count workflows..."
    
    # Importa cada workflow individualmente
    local imported=0
    local failed=0
    
    for workflow_file in "$workflows_dir"/*.json; do
        if [ -f "$workflow_file" ]; then
            local workflow_name=$(basename "$workflow_file" .json)
            
            if n8n import:workflow --input="$workflow_file" --separate 2>/dev/null; then
                log_success "✓ Importado: $workflow_name"
                ((imported++))
            else
                log_error "✗ Falha ao importar: $workflow_name"
                ((failed++))
            fi
        fi
    done
    
    log_success "Workflows importados: $imported/$workflow_count (falhas: $failed)"
    return 0
}

# Importa credenciais usando n8n CLI
import_credentials() {
    local backup_dir="$1"
    local credentials_dir="$backup_dir/credentials"
    
    if [ ! -d "$credentials_dir" ]; then
        log_warning "Diretório de credenciais não encontrado"
        return 0
    fi
    
    local credential_count=$(find "$credentials_dir" -name "*.json" 2>/dev/null | wc -l)
    
    if [ "$credential_count" -eq 0 ]; then
        log_warning "Nenhuma credencial encontrada para importar"
        return 0
    fi
    
    log_info "Importando $credential_count credenciais..."
    
    # Importa cada credencial individualmente
    local imported=0
    local failed=0
    
    for credential_file in "$credentials_dir"/*.json; do
        if [ -f "$credential_file" ]; then
            local credential_name=$(basename "$credential_file" .json)
            
            if n8n import:credentials --input="$credential_file" --separate 2>/dev/null; then
                log_success "✓ Importado: $credential_name"
                ((imported++))
            else
                log_error "✗ Falha ao importar: $credential_name"
                ((failed++))
            fi
        fi
    done
    
    log_success "Credenciais importadas: $imported/$credential_count (falhas: $failed)"
    return 0
}

# Limpa arquivos temporários
cleanup() {
    local backup_dir="$1"
    
    if [ -d "$backup_dir" ]; then
        log_info "Limpando arquivos temporários..."
        rm -rf "$backup_dir"
        log_success "Limpeza concluída"
    fi
}

# Cria flag de restauração concluída
mark_restore_completed() {
    local flag_file="$N8N_HOME/.n8n/.restore_completed"
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$flag_file"
    log_success "Restauração marcada como concluída"
}

# Verifica se restauração já foi executada
is_restore_completed() {
    local flag_file="$N8N_HOME/.n8n/.restore_completed"
    
    if [ -f "$flag_file" ]; then
        local restore_date=$(cat "$flag_file")
        log_info "Restauração já foi executada em: $restore_date"
        return 0
    fi
    
    return 1
}

#################################################
# FUNÇÃO PRINCIPAL
#################################################
main() {
    log_info "=========================================="
    log_info "  N8N BACKUP RESTORE SCRIPT"
    log_info "=========================================="
    
    # Verifica se restauração já foi executada
    if is_restore_completed; then
        log_warning "Pulando restauração (já executada anteriormente)"
        return 0
    fi
    
    # Verifica se restauração está habilitada
    if ! check_restore_enabled; then
        return 0
    fi
    
    # Valida variáveis
    if ! validate_variables; then
        log_error "Restauração cancelada devido a variáveis faltando"
        return 1
    fi
    
    # Verifica dados existentes
    if ! check_existing_data; then
        return 0
    fi
    
    # Clone do repositório
    backup_dir=$(clone_backup_repo)
    if [ $? -ne 0 ]; then
        log_error "Falha ao clonar repositório de backup"
        return 1
    fi
    
    # Conta arquivos de backup
    read workflows_count credentials_count <<< $(count_backup_files "$backup_dir")
    log_info "Backup encontrado: $workflows_count workflows, $credentials_count credenciais"
    
    if [ "$workflows_count" -eq 0 ] && [ "$credentials_count" -eq 0 ]; then
        log_warning "Nenhum dado encontrado no backup"
        cleanup "$backup_dir"
        return 0
    fi
    
    # Prepara diretório do n8n
    prepare_n8n_directory
    
    # Importa workflows
    if [ "$workflows_count" -gt 0 ]; then
        import_workflows "$backup_dir"
    fi
    
    # Importa credenciais
    if [ "$credentials_count" -gt 0 ]; then
        import_credentials "$backup_dir"
    fi
    
    # Marca restauração como concluída
    mark_restore_completed
    
    # Limpa arquivos temporários
    cleanup "$backup_dir"
    
    log_success "=========================================="
    log_success "  RESTAURAÇÃO CONCLUÍDA COM SUCESSO!"
    log_success "=========================================="
    
    return 0
}

# Executa função principal
main

exit $?
