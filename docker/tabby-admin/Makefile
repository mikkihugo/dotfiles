# Tabby Admin Stack Makefile
# Portable admin infrastructure in Docker

.PHONY: help build up down logs backup restore tunnel status clean auto-deploy

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build all containers
	docker-compose build
	docker-compose --profile build run tabby-builder

up: ## Start admin stack
	@echo "🚀 Starting Tabby Admin Stack..."
	docker-compose up -d
	@sleep 5
	@make status

down: ## Stop admin stack
	docker-compose down

logs: ## Show logs
	docker-compose logs -f

backup: ## Manual backup
	docker-compose exec backup /backup.sh

restore: ## Restore from backup
	@read -p "Backup file: " backup_file; \
	docker-compose exec backup /restore.sh $$backup_file

tunnel: ## Setup Cloudflare tunnel
	@echo "🌐 Configuring Cloudflare tunnel..."
	./scripts/setup-tunnel.sh

status: ## Show stack status
	@echo "📊 Tabby Admin Stack Status:"
	@echo ""
	@docker-compose ps
	@echo ""
	@echo "🔗 Access URLs:"
	@echo "  Local:"
	@echo "    - Admin UI:     http://localhost:8080"
	@echo "    - Warpgate:     http://localhost:8888"
	@echo "    - Tabby Web:    http://localhost:9090"
	@echo "    - Gitea:        http://localhost:3000"
	@echo "    - Gateway SSH:  ssh -p 2222 localhost"
	@if [ -f .tunnel-urls ]; then \
		echo "  Public (via Cloudflare):"; \
		cat .tunnel-urls; \
	fi

clean: ## Clean everything
	docker-compose down -v
	rm -rf backups/*

auto-deploy: ## Setup automatic deployment
	./scripts/auto-deploy.sh

# Development commands
dev-build: ## Build with cache mount
	DOCKER_BUILDKIT=1 docker-compose build

dev-shell: ## Shell into admin container
	docker-compose exec admin-ui /bin/sh

dev-db: ## Access database
	docker-compose exec tabby-web sqlite3 /data/tabby.db

# One-command setup
install: ## Complete installation with auto-deploy
	@echo "🚀 Installing Tabby Admin Stack..."
	@make build
	@make up
	@make auto-deploy
	@echo "✅ Installation complete!"

unlock: ## Unlock with Google account
	./scripts/simple-unlock.sh

quick-start: ## Quick start with Google unlock
	@./scripts/simple-unlock.sh