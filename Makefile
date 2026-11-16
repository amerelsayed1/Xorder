# Local production deploy for xorder-cloud (replaces the GitHub Actions run).
# SSH credentials come from Doppler (project xorder, config prd); nothing is stored in the repo.
#
#   make deploy-check      read-only: prove the SSH login works and deploy.sh exists
#   make deploy            deploy to PRODUCTION (asks you to type "deploy" first)
#   make deploy-rollback   roll back to the previous commit (asks you to type "rollback")
#   make deploy-logs       tail the last 50 lines of the server's deploy log
#   make dev | dev-api     local stack / API only, secrets from Doppler
#   make test-cloud | test-vue   cloud API tests (Doppler) / Vue unit tests
#
# On the server, deploy.sh takes a DB backup first, runs migrate --force, health-checks,
# and rolls back on failure. Run /release-check before `make deploy`.

DOPPLER_PROJECT ?= xorder
DOPPLER_CONFIG  ?= prd
DEPLOY_PATH     ?= /opt/xorder
COMPOSE_FILE    ?= $(DEPLOY_PATH)/docker-compose.cohost.yml

REMOTE = doppler run --project $(DOPPLER_PROJECT) --config $(DOPPLER_CONFIG) -- scripts/deploy/remote.sh

.PHONY: deploy-check deploy deploy-rollback deploy-logs test-cloud test-vue dev dev-api

# Cloud API tests (SQLite in-memory). Uses the same Doppler config as deploys ($(DOPPLER_CONFIG),
# currently prd), so local runs see production APP_KEY/JWT_SECRET. Tests use SQLite, not prod data.
# Extra args: make test-cloud ARGS="--filter OrderingModeTest"
test-cloud:
	cd apps/xorder-cloud/apps/api && doppler run --project $(DOPPLER_PROJECT) --config $(DOPPLER_CONFIG) -- php artisan test $(ARGS)

# Vue unit tests (Vitest). No secrets needed, so no Doppler.
test-vue:
	cd apps/xorder-cloud && pnpm test

# Local dev stack (API :8100 + three Vue apps) with secrets from Doppler instead of a hand-made
# .env. Doppler values are real environment variables, so they win over apps/api/.env.
# DB stays SQLite (dev.sh writes DB_CONNECTION=sqlite into .env; Doppler does not set it).
dev:
	cd apps/xorder-cloud && doppler run --project $(DOPPLER_PROJECT) --config $(DOPPLER_CONFIG) -- ./scripts/dev.sh

# API only, on :8100.
dev-api:
	cd apps/xorder-cloud/apps/api && doppler run --project $(DOPPLER_PROJECT) --config $(DOPPLER_CONFIG) -- php artisan serve --port=8100

deploy-check:
	$(REMOTE) "cd '$(DEPLOY_PATH)' && ls -l deploy.sh && git log -1 --format='server HEAD: %h %s' && git remote -v | head -1"

deploy:
	@echo "This deploys to PRODUCTION (https://xorder.io) and runs migrate --force."
	@echo "Local HEAD: $$(git rev-parse --short HEAD)  branch: $$(git rev-parse --abbrev-ref HEAD)"
	@echo "Note: the server pulls from ITS OWN git remote, not from this machine."
	@read -r -p 'Type "deploy" to continue: ' a && [ "$$a" = "deploy" ] || { echo "Aborted."; exit 1; }
	$(REMOTE) "cd '$(DEPLOY_PATH)' && export XORDER_COMPOSE_FILE='$(COMPOSE_FILE)' && ./deploy.sh --ci"

deploy-rollback:
	@read -r -p 'Type "rollback" to roll production back one commit: ' a && [ "$$a" = "rollback" ] || { echo "Aborted."; exit 1; }
	$(REMOTE) "cd '$(DEPLOY_PATH)' && export XORDER_COMPOSE_FILE='$(COMPOSE_FILE)' && ./deploy.sh --rollback --ci"

deploy-logs:
	$(REMOTE) "tail -n 50 '$(DEPLOY_PATH)/logs/deploy.log'"
