#!/bin/bash

##########################
#
# Instala o Docker CE
# Compatível com: Debian 12/13 e Ubuntu 22.04/24.04 (x64/arm64)
#
##########################

set -e

# Detectar distribuição
. /etc/os-release
DISTRO_ID="${ID}"          # debian | ubuntu
DISTRO_CODENAME="${VERSION_CODENAME}"  # bookworm | trixie | jammy | noble
DISTRO_ARCH="$(dpkg --print-architecture)"  # amd64 | arm64

echo "Distribuição detectada: ${DISTRO_ID} ${VERSION_ID} (${DISTRO_CODENAME}) [${DISTRO_ARCH}]"

# Validar distro suportada
case "$DISTRO_ID" in
    debian|ubuntu) ;;
    *)
        echo "ERRO: Distribuição '${DISTRO_ID}' não suportada. Use Debian 12/13 ou Ubuntu 22.04/24.04."
        exit 1
        ;;
esac

# Instalar dependências base
apt-get update -y
apt-get install -y \
    sudo gnupg2 wget ca-certificates apt-transport-https \
    curl gnupg nano htop lsb-release

# Criar diretório de keyrings
install -m 0755 -d /etc/apt/keyrings

# Baixar GPG key do repositório Docker para a distro correta
curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Adicionar repositório Docker para a distro e codename corretos
echo \
    "deb [arch=${DISTRO_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${DISTRO_ID} \
${DISTRO_CODENAME} stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y

# Instalar Docker CE e plugins
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Habilitar e iniciar Docker
systemctl enable docker.service
systemctl enable containerd.service
systemctl start docker.service

echo ""
echo "Docker instalado com sucesso:"
docker --version
docker compose version
