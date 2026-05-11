---
inclusion: auto
---

# Project Structure

## Directory Organization

The project follows a modular, feature-based architecture:

```
/
├── install.sh                    # Main orchestrator script
├── backup_to_s3.sh              # S3 backup script
├── backup_to_vm.sh              # Local backup script
├── restore_from_s3.sh           # S3 restore script
├── restore_from_vm.sh           # Local restore script
├── setup_dify.sh                # Standalone Dify installer
├── modules/                     # Modular installation components
│   ├── core/                    # Core infrastructure
│   │   ├── cloud.sh            # Cloud provider detection
│   │   ├── deploy.sh           # Service deployment
│   │   ├── inputs.sh           # User input collection
│   │   ├── resources.sh        # Resource allocation
│   │   ├── setup.sh            # Swarm initialization
│   │   └── yamls.sh            # YAML generation
│   ├── shared/                  # Shared utilities
│   │   ├── backup.sh           # Backup utilities
│   │   ├── inputs.sh           # Input helpers
│   │   └── utils.sh            # Common functions (logging, UI)
│   ├── dify/                    # Dify-specific setup
│   │   └── setup.sh
│   ├── evolution/               # Evolution API setup
│   │   └── setup.sh
│   └── n8n/                     # N8N setup
│       └── setup.sh
├── infra/                       # Docker Compose templates (cloud)
│   ├── 04.traefik.yaml
│   ├── 05.portainer.yaml
│   ├── 06.postgres.yaml
│   ├── 07.redis.yaml
│   ├── 08.n8n-editor.yaml
│   ├── 09.n8n-workers.yaml
│   ├── 10.n8n-webhooks.yaml
│   ├── 11.rabbitmq.yaml
│   ├── 12.dify-pgvector.yaml
│   ├── 13.dify-sandbox.yaml
│   ├── 14.dify-web.yaml
│   ├── 15.dify-api.yaml
│   ├── 16.dify-worker.yaml
│   ├── 17.dify-plugindaemon.yaml
│   └── 18.evolution_v2.yaml
├── vm/                          # Docker Compose templates (VM)
│   └── (same structure as infra/)
├── tests/                       # Validation scripts
│   ├── validate_setup.sh
│   └── validation.log
├── docs/                        # Documentation
│   └── DOCUMENTATION.md
└── img/                         # Visual assets (cost breakdowns)
```

## Runtime Structure

After installation, the system creates:

```
/opt/infra/<BUSINESS_NAME>/      # Business-specific installation
├── *.yaml                       # Generated Docker Compose files
└── .env files (embedded in YAMLs)

/var/log/<BUSINESS_NAME>/        # Business-specific logs
├── setup_YYYYMMDD.log          # Installation logs
├── detailed.log                # Detailed operation logs
├── checkpoint                  # Recovery checkpoint
└── variables.env               # Saved state variables

/var/log/backup_s3.log          # S3 backup logs (if automated)
```

## Module Loading Order

The `install.sh` script loads modules in this sequence:

1. `shared/utils.sh` - Logging, UI, error handling
2. `shared/inputs.sh` - Input validation helpers
3. `shared/backup.sh` - Backup/restore utilities
4. `core/setup.sh` - Swarm initialization, DNS verification
5. `core/inputs.sh` - Core variable collection
6. `core/cloud.sh` - Cloud provider detection
7. `core/resources.sh` - Resource allocation (High/Low spec)
8. `core/yamls.sh` - YAML file generation
9. `core/deploy.sh` - Service deployment
10. `n8n/setup.sh` - N8N configuration
11. `evolution/setup.sh` - Evolution API configuration
12. `dify/setup.sh` - Dify AI configuration

## Key Conventions

- All modules are sourced, not executed as subshells
- Modules use shared global variables from `utils.sh`
- Checkpoint system allows recovery from failures
- Business name is used for isolation (lowercase alphanumeric only)
- YAML files are generated dynamically based on user input
- Logs are timestamped and business-specific
- Docker volumes use `volume_swarm_*` naming convention
- Docker network uses `network_swarm_public` overlay network
