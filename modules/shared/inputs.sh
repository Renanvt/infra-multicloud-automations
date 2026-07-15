#!/bin/bash

confirm_input() {
    local prompt_text="$1"
    local confirm_text="$2"
    local var_name="$3"
    local input_val=""
    
    while true; do
        echo -ne "$prompt_text"
        read input_val < /dev/tty || continue
        
        input_val=$(echo "$input_val" | xargs)
        input_val="${input_val//\`/}"
        case "$input_val" in
            \"*\")
                input_val="${input_val#\"}"
                input_val="${input_val%\"}"
                ;;
            \'*\')
                input_val="${input_val#\'}"
                input_val="${input_val%\'}"
                ;;
        esac

        # Se a variável de destino já tem valor e o input é vazio, mantém o valor antigo
        if [ -z "$input_val" ] && [ -n "${!var_name}" ]; then
            input_val="${!var_name}"
        fi

        # Confirmação
        echo -e "${YELLOW}$confirm_text ${BOLD}$input_val${RESET}"
        echo -ne "Está correto? (Enter para Sim, 'n' para alterar): "
        read CONFIRM < /dev/tty || continue
        if [[ -z "$CONFIRM" || "$CONFIRM" =~ ^(s|S|sim|SIM)$ ]]; then
            eval "$var_name=\"$input_val\""
            break
        fi
        echo -e "${DIM}Reinserindo valor...${RESET}"
    done
}

# Helper para perguntas s/n — substitui read -p "$(echo -e ...)"
# Uso: ask_yn "Mensagem" VAR
ask_yn() {
    local prompt="$1"
    local var_name="$2"
    echo -ne "$prompt"
    read "$var_name" < /dev/tty || eval "$var_name=''"
}
