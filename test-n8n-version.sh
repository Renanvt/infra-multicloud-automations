#!/bin/bash
# =============================================================================
# test-n8n-version.sh — Testa versões do n8n de forma segura e incremental
# =============================================================================

set -e

VERSION="${1:-2.41.6}"
SERVICE_NAME="n8n_editor_n8n_editor"
IMAGE="n8nio/n8n:${VERSION}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║   N8N VERSION TESTER — Teste Seguro de Versões        ║${RESET}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════╝${RESET}"
echo -e ""

# Verificar se serviço existe
if ! docker service inspect "${SERVICE_NAME}" >/dev/null 2>&1; then
    echo -e "${RED}✘ Serviço '${SERVICE_NAME}' não encontrado!${RESET}"
    echo -e "${YELLOW}  Execute: docker stack deploy -c /opt/infra/alobexpress/08.n8n-editor.yaml n8n_editor${RESET}"
    exit 1
fi

# Obter versão atual
CURRENT_IMAGE=$(docker service inspect "${SERVICE_NAME}" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' | cut -d':' -f2 | cut -d'@' -f1)
echo -e "${CYAN}▶ Versão atual:${RESET} ${BOLD}${CURRENT_IMAGE}${RESET}"
echo -e "${CYAN}▶ Testando versão:${RESET} ${BOLD}${VERSION}${RESET}"
echo -e ""

# Confirmar com usuário
echo -e "${YELLOW}Deseja atualizar para ${VERSION}? (sim/não)${RESET}"
read -r CONFIRM
if [[ ! "${CONFIRM}" =~ ^(sim|s|yes|y)$ ]]; then
    echo -e "${RED}✘ Teste cancelado pelo usuário.${RESET}"
    exit 0
fi

echo -e ""
echo -e "${CYAN}▶ Atualizando serviço para ${VERSION}...${RESET}"
docker service update --image "${IMAGE}" "${SERVICE_NAME}"

echo -e ""
echo -e "${CYAN}▶ Aguardando serviço convergir...${RESET}"
sleep 5

# Verificar status do serviço
REPLICAS=$(docker service ps "${SERVICE_NAME}" --filter "desired-state=running" --format "{{.CurrentState}}" | head -1)
echo -e "${GREEN}✔ Status: ${REPLICAS}${RESET}"

echo -e ""
echo -e "${BOLD}${YELLOW}╔═══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${YELLOW}║   TESTE MANUAL NECESSÁRIO                              ║${RESET}"
echo -e "${BOLD}${YELLOW}╚═══════════════════════════════════════════════════════╝${RESET}"
echo -e ""
echo -e "${YELLOW}1. Aguarde ~30 segundos para o container inicializar${RESET}"
echo -e "${YELLOW}2. Limpe cache do navegador (Ctrl+Shift+Delete)${RESET}"
echo -e "${YELLOW}3. Acesse: ${BOLD}https://editorn8n.alobexpress.com.br${RESET}"
echo -e ""
echo -e "${CYAN}Verificações:${RESET}"
echo -e "  ${BOLD}✓${RESET} Frontend carrega SEM redirecionar para ${BOLD}/%7B%7BBASE_PATH%7D%7D/${RESET}"
echo -e "  ${BOLD}✓${RESET} Consegue fazer login"
echo -e "  ${BOLD}✓${RESET} Workflows aparecem corretamente"
echo -e ""
echo -e "${BOLD}Resultado do teste (funcionou/falhou):${RESET} "
read -r TEST_RESULT

if [[ "${TEST_RESULT}" =~ ^(funcionou|f|ok|sim|s)$ ]]; then
    echo -e ""
    echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}║   ✓ VERSÃO ${VERSION} FUNCIONA!                          ║${RESET}"
    echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════╝${RESET}"
    echo -e ""
    echo -e "${CYAN}Próximos passos:${RESET}"
    echo -e "  1. Atualizar Dockerfile para usar esta versão"
    echo -e "  2. Fazer build da imagem custom"
    echo -e "  3. Atualizar workers e webhooks"
    echo -e ""
    echo -e "${YELLOW}Comandos:${RESET}"
    echo -e "  ${BOLD}# Atualizar Dockerfile${RESET}"
    echo -e "  sed -i 's/FROM n8nio\/n8n:.*/FROM n8nio\/n8n:${VERSION} AS base/' /opt/alobexpress/n8n-custom/Dockerfile"
    echo -e ""
    echo -e "  ${BOLD}# Build imagem custom${RESET}"
    echo -e "  cd /opt/alobexpress/n8n-custom"
    echo -e "  docker build --no-cache --pull -t alobexpress/n8n-custom:${VERSION} ."
    echo -e ""
    echo -e "  ${BOLD}# Atualizar serviços${RESET}"
    echo -e "  docker service update --image alobexpress/n8n-custom:${VERSION} n8n_editor_n8n_editor"
    echo -e "  docker service update --image alobexpress/n8n-custom:${VERSION} n8n_workers_n8n_workers"
    echo -e "  docker service update --image alobexpress/n8n-custom:${VERSION} n8n_webhooks_n8n_webhooks"
    echo -e ""
else
    echo -e ""
    echo -e "${RED}${BOLD}╔═══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}${BOLD}║   ✘ VERSÃO ${VERSION} NÃO FUNCIONA (bug BASE_PATH)       ║${RESET}"
    echo -e "${RED}${BOLD}╚═══════════════════════════════════════════════════════╝${RESET}"
    echo -e ""
    echo -e "${YELLOW}Deseja voltar para ${CURRENT_IMAGE}? (sim/não)${RESET}"
    read -r ROLLBACK
    if [[ "${ROLLBACK}" =~ ^(sim|s|yes|y)$ ]]; then
        echo -e "${CYAN}▶ Revertendo para ${CURRENT_IMAGE}...${RESET}"
        docker service update --image "n8nio/n8n:${CURRENT_IMAGE}" "${SERVICE_NAME}"
        echo -e "${GREEN}✔ Revertido com sucesso!${RESET}"
    fi
    echo -e ""
    echo -e "${CYAN}Testar versão anterior? Exemplo:${RESET}"
    echo -e "  ${BOLD}bash test-n8n-version.sh 2.30.0${RESET}"
    echo -e "  ${BOLD}bash test-n8n-version.sh 2.20.0${RESET}"
    echo -e "  ${BOLD}bash test-n8n-version.sh 1.100.0${RESET}"
    echo -e ""
fi

echo -e ""
echo -e "${CYAN}Ver logs do serviço:${RESET}"
echo -e "  ${BOLD}docker service logs --tail 50 -f ${SERVICE_NAME}${RESET}"
echo -e ""
