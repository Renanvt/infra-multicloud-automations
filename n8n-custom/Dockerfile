FROM n8nio/n8n:2.40.0 AS base

# Instala ferramentas extras a partir do Alpine (a imagem base do n8n remove o apk)
FROM alpine:3.21 AS tools
RUN apk add --no-cache ffmpeg python3 git

# Imagem final
FROM base
USER root

# Copia binários do Alpine para a imagem do n8n
# ffmpeg  — processamento de áudio/vídeo
# git     — clone de repositório de backup
# python3 — scripts Python nos nodes Code
COPY --from=tools /usr/bin/ffmpeg  /usr/bin/ffmpeg
COPY --from=tools /usr/bin/git     /usr/bin/git
COPY --from=tools /usr/bin/python3 /usr/bin/python3
COPY --from=tools /usr/lib/python3.12 /usr/lib/python3.12
ENV PYTHON=/usr/bin/python3

# n8n-nodes-postiz é instalado automaticamente via N8N_REINSTALL_MISSING_PACKAGES=true

USER node
WORKDIR /
