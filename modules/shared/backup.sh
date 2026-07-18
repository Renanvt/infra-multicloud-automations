#!/bin/bash

setup_auto_backup() {
    print_step "CONFIGURANDO BACKUP AUTOMÁTICO"
    
    # Pergunta se deseja configurar
    echo -ne "${CYAN}Deseja configurar backup automático? (s/n): ${RESET}"; read SETUP_BACKUP_OPT < /dev/tty || true
    if [[ ! "$SETUP_BACKUP_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
        print_info "Backup automático ignorado."
        return
    fi

    echo -e "${YELLOW}Escolha o destino do backup:${RESET}"
    echo -e "  1) VM Local (Pasta local)"
    echo -e "  2) S3 (AWS, DigitalOcean Spaces, MinIO, etc)"
    echo -ne "${CYAN}Opção (1 ou 2): ${RESET}"; read BACKUP_TYPE < /dev/tty || true

    if [[ "$BACKUP_TYPE" == "1" ]]; then
        # === BACKUP LOCAL ===
        local B_ROOT_DIR=""
        local B_RETENTION=""

        confirm_input "${CYAN}📂 Diretório de Backup (Padrão: /opt/infra/backups): ${RESET}" "Diretório:" B_ROOT_DIR
        [ -z "$B_ROOT_DIR" ] && B_ROOT_DIR="/opt/infra/backups"

        confirm_input "${CYAN}📅 Retenção em dias (Padrão: 7): ${RESET}" "Dias:" B_RETENTION
        [ -z "$B_RETENTION" ] && B_RETENTION="7"

        # Baixar script backup_to_vm.sh
        local BACKUP_SCRIPT_PATH="$INSTALL_DIR/backup_to_vm.sh"
        mkdir -p "$INSTALL_DIR"
        mkdir -p "$B_ROOT_DIR"

        print_info "Baixando script de backup local..."
        if curl -sL "https://setup.alobexpress.com.br/backup_to_vm.sh" -o "$BACKUP_SCRIPT_PATH"; then
            print_success "Script baixado com sucesso em $BACKUP_SCRIPT_PATH"
        else
            # Fallback
            if [ -n "$REPO_BASE_URL" ]; then
                 curl -sL "$REPO_BASE_URL/backup_to_vm.sh" -o "$BACKUP_SCRIPT_PATH"
            fi
        fi

        chmod +x "$BACKUP_SCRIPT_PATH"
        
        # Configurar Cron
        local CRON_CMD="0 3 * * * BACKUP_ROOT_DIR=$B_ROOT_DIR RETENTION_DAYS=$B_RETENTION $BACKUP_SCRIPT_PATH >> /var/log/backup_vm.log 2>&1"
        (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_PATH"; echo "$CRON_CMD") | crontab -
        
        print_success "Cron job configurado para rodar diariamente às 03:00am"
        print_info "Para executar o backup manualmente agora, rode: ${BOLD}bash $BACKUP_SCRIPT_PATH${RESET}"
        log_message "INFO" "Backup local configurado em $B_ROOT_DIR (Retenção: $B_RETENTION dias)"
        save_checkpoint "backup_vm_configured"

    else
        # === BACKUP S3 ===
        # Coleta de Credenciais (Reutilização)
        local B_BUCKET=""
        local B_REGION=""
        local B_ACCESS=""
        local B_SECRET=""
        local B_ENDPOINT=""

        # Tenta reutilizar do Evolution ou Dify
        if [ -n "$EVO_S3_BUCKET" ]; then
            echo -e "${YELLOW}Detectamos credenciais S3 do Evolution.${RESET}"
            read -p "Reutilizar para backup? (s/n): " REUSE_EVO < /dev/tty || true
            if [[ "$REUSE_EVO" =~ ^(s|S|sim|SIM)$ ]]; then
                B_BUCKET="$EVO_S3_BUCKET"
                B_REGION="$EVO_S3_REGION"
                B_ACCESS="$EVO_S3_ACCESS_KEY"
                B_SECRET="$EVO_S3_SECRET_KEY"
                B_ENDPOINT="$EVO_S3_ENDPOINT"
            fi
        fi

        # Se não reutilizou, pergunta
        if [ -z "$B_BUCKET" ]; then
            confirm_input "${CYAN}🪣 Nome do Bucket de Backup: ${RESET}" "Bucket:" B_BUCKET
            confirm_input "${CYAN}🌍 Região S3: ${RESET}" "Região:" B_REGION
            
            # Sanitização da Região (Remove s3., .amazonaws.com e trata east-1)
            B_REGION=$(echo "$B_REGION" | sed -E 's/^(https?:\/\/)?(s3\.)?//' | sed -E 's/\.amazonaws\.com$//')
            if [[ "$B_REGION" == "east-1" ]]; then B_REGION="us-east-1"; fi

            confirm_input "${CYAN}🗝️ Access Key ID: ${RESET}" "Access Key:" B_ACCESS
            confirm_input "${CYAN}🔒 Secret Access Key: ${RESET}" "Secret Key:" B_SECRET
            # Endpoint opcional
        echo -ne "${CYAN}🔗 Endpoint S3 Custom (Enter para AWS padrão): ${RESET}"; read B_ENDPOINT < /dev/tty || true
        fi

        # Baixar o script backup_to_s3.sh
        local BACKUP_SCRIPT_PATH="$INSTALL_DIR/backup_to_s3.sh"
        mkdir -p "$INSTALL_DIR"

        print_info "Baixando script de backup S3..."
        
        # Tenta copiar do diretório de scripts se disponível (Instalação Git) ou baixa do repo oficial (Instalação Curl)
        if [ -f "$SCRIPT_DIR/backup_to_s3.sh" ]; then
             cp "$SCRIPT_DIR/backup_to_s3.sh" "$BACKUP_SCRIPT_PATH"
        elif [ -n "$REPO_BASE_URL" ]; then
             curl -sL "$REPO_BASE_URL/backup_to_s3.sh" -o "$BACKUP_SCRIPT_PATH"
        else
             # Fallback para URL antiga se REPO_BASE_URL não estiver definido
             curl -sL "https://setup.alobexpress.com.br/backup_to_s3.sh" -o "$BACKUP_SCRIPT_PATH"
        fi

        if [ -f "$BACKUP_SCRIPT_PATH" ]; then
            print_success "Script baixado com sucesso em $BACKUP_SCRIPT_PATH"
        else
            print_error "Falha ao baixar o script de backup."
            return
        fi

        chmod +x "$BACKUP_SCRIPT_PATH"
        print_success "Script de backup criado em $BACKUP_SCRIPT_PATH"

        # Configurar Cron
        # Executa todo dia às 03:00am
        local CRON_BUSINESS_NAME="${BUSINESS_NAME:-alobexpress}"
        local CRON_CLOUD_PROVIDER="${CLOUD_PROVIDER:-aws}"
        local CRON_INSTANCE_NAME=$(hostname)
        local CRON_CMD="0 3 * * * BUSINESS_NAME=$CRON_BUSINESS_NAME CLOUD_PROVIDER=$CRON_CLOUD_PROVIDER INSTANCE_NAME=$CRON_INSTANCE_NAME S3_BUCKET=$B_BUCKET S3_REGION=$B_REGION S3_ACCESS_KEY=$B_ACCESS S3_SECRET_KEY=$B_SECRET S3_ENDPOINT=$B_ENDPOINT $BACKUP_SCRIPT_PATH >> /var/log/backup_s3.log 2>&1"
        
        # Remove job anterior se existir e adiciona novo
        (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_PATH"; echo "$CRON_CMD") | crontab -
        
        print_success "Cron job configurado para rodar diariamente às 03:00am"
        print_info "Para executar o backup manualmente agora, rode: ${BOLD}bash $BACKUP_SCRIPT_PATH${RESET}"
        log_message "INFO" "Backup automático configurado para bucket $B_BUCKET"
        save_checkpoint "backup_s3_configured"
    fi
}

select_arrow_menu() {
    local -n options_ref=$1
    local default_idx=${2:-0}
    local selected=$default_idx
    local key

    if ! [ -t 0 ] && ! [ -r /dev/tty ]; then
        MENU_SELECTION=0
        return 0
    fi

    tput civis 2>/dev/null || true

    while true; do
        echo -e "${CYAN}Use as setas ${BOLD}↑/↓${RESET}${CYAN} para navegar e ${BOLD}ENTER${RESET}${CYAN} para confirmar:${RESET}"
        for i in "${!options_ref[@]}"; do
            if [ $i -eq $selected ]; then
                echo -e "${GREEN}${BOLD}➜ ${options_ref[$i]}${RESET}"
            else
                echo -e "  ${options_ref[$i]}"
            fi
        done

        if ! read -rsn1 key < /dev/tty; then
            sleep 1
            continue
        fi

        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key < /dev/tty || true
            if [[ "$key" == "[A" ]]; then
                selected=$((selected - 1))
                if [ $selected -lt 0 ]; then selected=$((${#options_ref[@]} - 1)); fi
            elif [[ "$key" == "[B" ]]; then
                selected=$((selected + 1))
                if [ $selected -ge ${#options_ref[@]} ]; then selected=0; fi
            fi
        elif [[ "$key" == "" ]]; then
            break
        fi

        tput cuu $((${#options_ref[@]} + 1)) 2>/dev/null || true
        tput ed 2>/dev/null || true
    done

    tput cnorm 2>/dev/null || true
    echo ""

    MENU_SELECTION=$selected
    return 0
}

download_script() {
    local url="$1"
    local dest="$2"

    mkdir -p "$(dirname "$dest")"
    rm -f "$dest"

    if ! curl -sL "$url" -o "$dest"; then
        echo -e "${RED}Falha ao baixar: $url${RESET}"
        return 1
    fi

    if [ ! -s "$dest" ]; then
        echo -e "${RED}Arquivo baixado está vazio: $dest${RESET}"
        return 1
    fi

    chmod +x "$dest" || true
    return 0
}

run_backup_restore_menu() {
    print_step "BACKUP & RESTORE"

    echo -ne "${CYAN}Deseja fazer um backup inicial? (s/n): ${RESET}"; read DO_INITIAL_BACKUP < /dev/tty || true

    if [[ "$DO_INITIAL_BACKUP" =~ ^(s|S|sim|SIM)$ ]]; then
        echo -e "${GREEN}Iniciando Backup Inicial...${RESET}"

        local bucket_candidates=()
        local chosen_bucket=""

        if [ -n "$S3_BUCKET_NAME" ]; then bucket_candidates+=("$S3_BUCKET_NAME"); fi
        if [ -n "$EVO_S3_BUCKET" ]; then
            local exists=false
            for b in "${bucket_candidates[@]}"; do
                if [ "$b" == "$EVO_S3_BUCKET" ]; then exists=true; break; fi
            done
            if [ "$exists" = false ]; then bucket_candidates+=("$EVO_S3_BUCKET"); fi
        fi
        if [ -n "$DIFY_S3_BUCKET" ]; then
            local exists=false
            for b in "${bucket_candidates[@]}"; do
                if [ "$b" == "$DIFY_S3_BUCKET" ]; then exists=true; break; fi
            done
            if [ "$exists" = false ]; then bucket_candidates+=("$DIFY_S3_BUCKET"); fi
        fi

        if [ ${#bucket_candidates[@]} -eq 1 ]; then
            echo -e "${YELLOW}Bucket ${bucket_candidates[0]} detectado.${RESET}"
            read -p "Deseja fazer o backup nesse bucket? (s/n): " CONFIRM_BUCKET < /dev/tty || true
            if [[ "$CONFIRM_BUCKET" =~ ^(s|S|sim|SIM)$ ]]; then
                chosen_bucket="${bucket_candidates[0]}"
            fi
        elif [ ${#bucket_candidates[@]} -gt 1 ]; then
            echo -e "${CYAN}Selecione o bucket para backup:${RESET}"
            select_arrow_menu bucket_candidates 0
            chosen_bucket="${bucket_candidates[$MENU_SELECTION]}"
        fi

        if [ -z "$chosen_bucket" ]; then
            while [ -z "$chosen_bucket" ]; do
                read -p "Digite o nome do Bucket S3 para Backup: " chosen_bucket < /dev/tty || true
            done
        fi

        local region=""
        local access=""
        local secret=""
        local endpoint=""

        if [ -n "$chosen_bucket" ] && [ "$chosen_bucket" == "$EVO_S3_BUCKET" ]; then
            region="$EVO_S3_REGION"
            access="$EVO_S3_ACCESS_KEY"
            secret="$EVO_S3_SECRET_KEY"
            endpoint="$EVO_S3_ENDPOINT"
        elif [ -n "$chosen_bucket" ] && [ "$chosen_bucket" == "$DIFY_S3_BUCKET" ]; then
            region="$DIFY_S3_REGION"
            access="$DIFY_S3_ACCESS_KEY"
            secret="$DIFY_S3_SECRET_KEY"
            endpoint="$DIFY_S3_ENDPOINT"
        else
            region="$S3_REGION"
            access="$AWS_ACCESS_KEY_ID"
            secret="$AWS_SECRET_ACCESS_KEY"
        fi

        if [ -z "$region" ]; then
            while [ -z "$region" ]; do
                read -p "Região S3 (ex: us-east-1): " region < /dev/tty || true
            done
        fi
        region=$(echo "$region" | sed -E 's/^(https?:\/\/)?(s3\.)?//' | sed -E 's/\.amazonaws\.com$//')
        if [[ "$region" == "east-1" ]]; then region="us-east-1"; fi

        if [ -z "$access" ]; then
            while [ -z "$access" ]; do
                read -p "AWS Access Key ID: " access < /dev/tty || true
            done
        fi
        if [ -z "$secret" ]; then
            while [ -z "$secret" ]; do
                read -s -p "AWS Secret Access Key: " secret < /dev/tty || true
                echo ""
            done
        fi

        if [ -n "$endpoint" ] && [[ ! "$endpoint" =~ ^https?:// ]]; then
            endpoint="https://$endpoint"
        fi

        export BUSINESS_NAME="${BUSINESS_NAME:-unnamed}"
        export CLOUD_PROVIDER="${CLOUD_PROVIDER:-aws}"
        export INSTANCE_NAME="${INSTANCE_NAME:-$(hostname)}"
        export S3_BUCKET="$chosen_bucket"
        export S3_REGION="$region"
        export S3_ACCESS_KEY="$access"
        export S3_SECRET_KEY="$secret"
        export S3_ENDPOINT="$endpoint"

        local S3_BIN="$INSTALL_DIR/backup_to_s3"
        if ! download_script "https://setup.alobexpress.com.br/backup_to_s3.sh" "$S3_BIN"; then
            echo -e "${RED}Não foi possível iniciar o backup S3.${RESET}"
            return
        fi

        if ! grep -q "=== Backup para S3 ===" "$S3_BIN" 2>/dev/null; then
            echo -e "${RED}Script de backup S3 inválido (conteúdo inesperado).${RESET}"
            return
        fi

        bash "$S3_BIN"

        local VM_BIN="$INSTALL_DIR/backup_to_vm"
        if ! download_script "https://setup.alobexpress.com.br/backup_to_vm.sh" "$VM_BIN"; then
            echo -e "${RED}Não foi possível iniciar o backup na VM.${RESET}"
            return
        fi

        if ! grep -q "=== Backup Local" "$VM_BIN" 2>/dev/null; then
            echo -e "${RED}Script de backup VM inválido (conteúdo inesperado).${RESET}"
            return
        fi

        bash "$VM_BIN"
        return
    fi

    echo -ne "${CYAN}Deseja restaurar dados de outra VM? (fluxos n8n, fluxos Dify, configurações evolution, certificados ssl, dados do portainer) (s/n): ${RESET}"; read RESTORE_OTHER_VM < /dev/tty || true
    if [[ ! "$RESTORE_OTHER_VM" =~ ^(s|S|sim|SIM)$ ]]; then
        print_info "Backup inicial e restauração ignorados."
        return
    fi

    read -p "Você tem o backup da VM no S3? (s/n): " HAS_S3_BACKUP < /dev/tty || true
    if [[ "$HAS_S3_BACKUP" =~ ^(s|S|sim|SIM)$ ]]; then
        local RESTORE_S3_BIN="$INSTALL_DIR/restore_from_s3"
        if ! download_script "https://setup.alobexpress.com.br/restore_from_s3.sh" "$RESTORE_S3_BIN"; then
            echo -e "${RED}Não foi possível iniciar a restauração do S3.${RESET}"
            return
        fi
        bash "$RESTORE_S3_BIN"
    else
        local RESTORE_VM_BIN="$INSTALL_DIR/restore_from_vm"
        if ! download_script "https://setup.alobexpress.com.br/restore_from_vm.sh" "$RESTORE_VM_BIN"; then
            echo -e "${RED}Não foi possível iniciar a restauração local (VM).${RESET}"
            return
        fi
        bash "$RESTORE_VM_BIN"
    fi
}
