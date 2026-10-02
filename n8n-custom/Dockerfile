FROM n8nio/n8n:2.0.2

USER root

# Ferramentas de mídia e utilitários do sistema
# ffmpeg        — processamento de áudio/vídeo
# imagemagick   — manipulação de imagens
# ghostscript   — leitura e conversão de PDFs
# python3       — scripts Python nos nodes Code
# py3-pip       — gerenciador de pacotes Python
# git           — clone de repositório de backup
RUN apk add --no-cache \
    ffmpeg \
    imagemagick \
    ghostscript \
    python3 \
    py3-pip \
    git \
    bash

# Copia o script de restauração de backup
COPY restore_n8n_backup.sh /usr/local/bin/restore_n8n_backup.sh
RUN chmod +x /usr/local/bin/restore_n8n_backup.sh

# Copia o entrypoint customizado
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Instala o community node do Postiz
# ATENÇÃO: o n8n recria /home/node/.n8n ao iniciar — este node será reinstalado
# automaticamente via N8N_REINSTALL_MISSING_PACKAGES=true ou pelo script de deploy.
USER node
WORKDIR /home/node/.n8n/nodes
RUN npm install n8n-nodes-postiz

USER node
WORKDIR /

# Define o entrypoint customizado
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
