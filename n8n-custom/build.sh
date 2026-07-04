#!/bin/bash
# =============================================================================
# build.sh — Constrói a imagem customizada do n8n com FFmpeg e ferramentas extras
# Caminho esperado no servidor: /opt/alobexpress/n8n-custom/build.sh
# =============================================================================

set -e

N8N_VERSION="2.0.2"
IMAGE_NAME="alobexpress/n8n-custom"
IMAGE_TAG="${IMAGE_NAME}:${N8N_VERSION}"
DOCKERFILE_DIR="/opt/alobexpress/n8n-custom"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║   BUILD — n8n Custom Image (FFmpeg + Extras)     ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
echo -e ""

# ----------------------------------------------------------------------------
# 1. Criar pasta e copiar Dockerfile (caso execute de outro diretório)
# ----------------------------------------------------------------------------
echo -e "${CYAN}▶ Criando diretório ${DOCKERFILE_DIR}...${RESET}"
mkdir -p "${DOCKERFILE_DIR}"
chmod 755 "${DOCKERFILE_DIR}"

# Copia o Dockerfile para o destino, caso o script seja executado de outro lugar
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${SCRIPT_DIR}" != "${DOCKERFILE_DIR}" ]; then
    cp "${SCRIPT_DIR}/Dockerfile" "${DOCKERFILE_DIR}/Dockerfile"
    echo -e "${GREEN}✔ Dockerfile copiado para ${DOCKERFILE_DIR}${RESET}"
fi

# ----------------------------------------------------------------------------
# 2. Build da imagem
# ----------------------------------------------------------------------------
echo -e ""
echo -e "${CYAN}▶ Iniciando build da imagem ${BOLD}${IMAGE_TAG}${RESET}${CYAN}...${RESET}"
echo -e "${YELLOW}  (pode levar alguns minutos — inclui download do ffmpeg e npm install do n8n-nodes-postiz)${RESET}"
echo -e ""

if docker build -t "${IMAGE_TAG}" "${DOCKERFILE_DIR}"; then
    echo -e ""
    echo -e "${GREEN}${BOLD}✔ Imagem '${IMAGE_TAG}' criada com sucesso!${RESET}"
else
    echo -e "${RED}${BOLD}✘ Falha no build da imagem. Verifique os logs acima.${RESET}"
    exit 1
fi

# ----------------------------------------------------------------------------
# 3. Verificar FFmpeg dentro da imagem recém-criada
# ----------------------------------------------------------------------------
echo -e ""
echo -e "${CYAN}▶ Verificando FFmpeg na imagem...${RESET}"
FFMPEG_VERSION=$(docker run --rm "${IMAGE_TAG}" ffmpeg -version 2>&1 | head -1)
if echo "${FFMPEG_VERSION}" | grep -q "ffmpeg version"; then
    echo -e "${GREEN}✔ FFmpeg OK: ${FFMPEG_VERSION}${RESET}"
else
    echo -e "${RED}✘ FFmpeg não encontrado na imagem. Verifique o Dockerfile.${RESET}"
    exit 1
fi

# ----------------------------------------------------------------------------
# 4. Atualizar os serviços no Swarm (se já estiverem rodando)
# ----------------------------------------------------------------------------
echo -e ""
echo -e "${CYAN}▶ Verificando serviços n8n no Swarm...${RESET}"

update_service() {
    local SERVICE="$1"
    if docker service inspect "${SERVICE}" >/dev/null 2>&1; then
        echo -e "${CYAN}  → Atualizando ${SERVICE}...${RESET}"
        docker service update --image "${IMAGE_TAG}" "${SERVICE}" >/dev/null 2>&1
        echo -e "${GREEN}  ✔ ${SERVICE} atualizado${RESET}"
    else
        echo -e "${YELLOW}  ⚠ Serviço '${SERVICE}' não encontrado (será aplicado no próximo deploy)${RESET}"
    fi
}

update_service "n8n_editor_n8n_editor"
update_service "n8n_worker_n8n_worker"
update_service "n8n_webhook_n8n_webhook"

echo -e ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║   Build concluído com sucesso!                   ║${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo -e ""
echo -e "${YELLOW}Para atualizar para uma nova versão do n8n:${RESET}"
echo -e "  1. Edite N8N_VERSION no topo deste script"
echo -e "  2. Edite FROM no Dockerfile"
echo -e "  3. Execute novamente: ${BOLD}bash /opt/alobexpress/n8n-custom/build.sh${RESET}"
echo -e ""
