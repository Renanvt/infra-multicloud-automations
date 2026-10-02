#!/bin/bash

#################################################
# N8N Docker Entrypoint com Restauração
#################################################

set -e

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  N8N Container Starting...${NC}"
echo -e "${BLUE}=========================================${NC}"

# Se o script de restauração existir e estiver habilitado, executa
if [ -f "/usr/local/bin/restore_n8n_backup.sh" ] && [ "$N8N_RESTORE_ENABLED" = "true" ]; then
    echo -e "${GREEN}Executando restauração de backup...${NC}"
    bash /usr/local/bin/restore_n8n_backup.sh || {
        echo "AVISO: Restauração de backup falhou, mas continuando inicialização..."
    }
fi

# Executa o comando original do n8n
echo -e "${GREEN}Iniciando n8n...${NC}"
exec n8n "$@"
