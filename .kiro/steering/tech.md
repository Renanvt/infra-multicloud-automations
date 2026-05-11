---
inclusion: auto
---

# Technical Stack

## Core Technologies

- **Container Orchestration**: Docker Swarm
- **Reverse Proxy**: Traefik v3
- **Databases**: PostgreSQL 16, Redis 7, PgVector (for Dify)
- **Message Queue**: RabbitMQ
- **Shell**: Bash (POSIX-compliant scripts)

## Application Stack

- **N8N**: Node.js-based workflow automation (Editor, Worker, Webhook services)
- **Evolution API**: WhatsApp integration service
- **Dify**: Python-based LLM platform (API, Web, Worker, Sandbox, Plugin Daemon)
- **Portainer CE**: Container management UI

## Cloud Integration

- **AWS Services**: EC2, S3, IAM
- **GCP Services**: Compute Engine, Cloud Storage
- **DNS**: Cloudflare (recommended)

## Build System

The project uses a modular bash-based installation system with the following structure:

- `install.sh`: Main orchestrator
- `modules/core/`: Core infrastructure setup
- `modules/shared/`: Shared utilities (logging, input, backup)
- `modules/{service}/`: Service-specific configuration

## Common Commands

### Installation
```bash
# Quick install (recommended)
curl -sL https://raw.githubusercontent.com/Renanvt/infra-cloud-aws-google/main/install.sh | sudo bash

# Manual install
git clone https://github.com/Renanvt/infra-cloud-aws-google.git infra-alob
cd infra-alob
chmod +x install.sh
sudo ./install.sh
```

### Service Management
```bash
# List all services
docker service ls

# View service logs
docker service logs -f SERVICE_NAME

# Restart a service
docker service update --force SERVICE_NAME

# List containers
docker ps -a

# View container logs
docker logs --tail 100 -f CONTAINER_NAME
```

### Stack Operations
```bash
# Deploy a stack
docker stack deploy -c FILE.yaml STACK_NAME

# Remove a stack
docker stack rm STACK_NAME

# List stacks
docker stack ls
```

### Backup & Restore
```bash
# Backup to S3
./backup_to_s3.sh

# Backup to local VM
./backup_to_vm.sh

# Restore from S3
./restore_from_s3.sh
```

### Maintenance
```bash
# View resource usage
docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Clean up unused resources (safe)
docker system prune -a

# View disk usage
docker system df
df -h
```

## Environment Variables

Configuration is stored in `/opt/infra/<BUSINESS_NAME>/` with generated `.yaml` files containing environment variables for each service.

## Dependencies

- curl or wget
- git
- openssl
- Docker Engine
- bc (for calculations)
