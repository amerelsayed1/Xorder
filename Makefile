# Local production deploy for xorder-cloud (replaces the GitHub Actions run).
# SSH credentials come from Doppler (project xorder, config prd); nothing is stored in the repo.
#
#   make deploy-check      read-only: prove the SSH login works and deploy.sh exists
#   make deploy            deploy to PRODUCTION (asks you to type "deploy" first)
#   make deploy-rollback   roll back to the previous commit (asks you to type "rollback")
#   make deploy-logs       tail the last 50 lines of the server's deploy log
#
# On the server, deploy.sh takes a DB backup first, runs migrate --force, health-checks,
# and rolls back on failure. Run /release-check before `make deploy`.

DOPPLER_PROJECT ?= xorder
DOPPLER_CONFIG  ?= prd
DEPLOY_PATH     ?= /opt/xorder
COMPOSE_FILE    ?= $(DEPLOY_PATH)/docker-compose.cohost.yml

REMOTE = doppler run --project $(DOPPLER_PROJECT) --config $(DOPPLER_CONFIG) -- scripts/deploy/remote.sh

.PHONY: deploy-check deploy deploy-rollback deploy-logs

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
