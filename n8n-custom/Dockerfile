FROM n8nio/n8n:2.0.2

USER root

# Ferramentas de mídia e utilitários do sistema
# ffmpeg        — processamento de áudio/vídeo
# imagemagick   — manipulação de imagens
# ghostscript   — leitura e conversão de PDFs
# python3       — scripts Python nos nodes Code
# py3-pip       — gerenciador de pacotes Python
RUN apk add --no-cache \
    ffmpeg \
    imagemagick \
    ghostscript \
    python3 \
    py3-pip

# Instala o community node do Postiz
# ATENÇÃO: o n8n recria /home/node/.n8n ao iniciar — este node será reinstalado
# automaticamente via N8N_REINSTALL_MISSING_PACKAGES=true ou pelo script de deploy.
USER node
WORKDIR /home/node/.n8n/nodes
RUN npm install n8n-nodes-postiz

USER node
WORKDIR /
