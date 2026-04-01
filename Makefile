# ossuary — carp.rodeo infrastructure
#
# workflows:
#   first time:  make init-secrets → make gen-env → make gen-tfvars → make init → make plan → make apply → make deploy
#   iterate:     make plan → make apply
#   update:      make plan → make apply → make deploy
#   teardown:    make destroy

INFRA_DIR  := infra
COMPOSE_DIR := compose
SSH_USER   := debian
REMOTE_DIR := /opt/carp-rodeo

# load local config from root .env (S3 creds, SOPS key path)
-include .env
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export SOPS_AGE_KEY_FILE

# populated after first `terraform apply`
SERVER_IP := $(shell cd $(INFRA_DIR) && terraform output -raw matrix_ip 2>/dev/null || echo "unknown")

# ──────────────────────────────────────────────
# terraform
# ──────────────────────────────────────────────

.PHONY: init plan apply destroy output

## first-time terraform setup (S3 backend creds loaded from .env)
init:
	cd $(INFRA_DIR) && terraform init -reconfigure \
		-backend-config="access_key=$(AWS_ACCESS_KEY_ID)" \
		-backend-config="secret_key=$(AWS_SECRET_ACCESS_KEY)"

## preview infrastructure changes (decrypts tfvars automatically)
plan:
	@sops -d $(INFRA_DIR)/terraform.tfvars.enc > $(INFRA_DIR)/terraform.tfvars.plaintext
	cd $(INFRA_DIR) && terraform plan -var-file=terraform.tfvars.plaintext; \
		EXIT=$$?; rm -f terraform.tfvars.plaintext; exit $$EXIT

## apply infrastructure changes (decrypts tfvars automatically)
apply:
	@sops -d $(INFRA_DIR)/terraform.tfvars.enc > $(INFRA_DIR)/terraform.tfvars.plaintext
	cd $(INFRA_DIR) && terraform apply -var-file=terraform.tfvars.plaintext; \
		EXIT=$$?; rm -f terraform.tfvars.plaintext; exit $$EXIT

## tear down all infrastructure (asks for confirmation)
destroy:
	cd $(INFRA_DIR) && terraform destroy

## show terraform outputs (server IP, URLs, SSH command)
output:
	cd $(INFRA_DIR) && terraform output

# ──────────────────────────────────────────────
# secrets (SOPS + age)
# ──────────────────────────────────────────────

.PHONY: init-secrets gen-env gen-tfvars edit-env edit-tfvars decrypt-env decrypt-tfvars rotate-secrets

## one-time: generate age keypair for SOPS encryption
init-secrets:
	@if [ -f ~/.config/sops/age/keys.txt ]; then \
		echo "age key already exists at ~/.config/sops/age/keys.txt"; \
		echo "public key:"; \
		grep 'public key:' ~/.config/sops/age/keys.txt | sed 's/.*: //'; \
		exit 0; \
	fi
	@mkdir -p ~/.config/sops/age
	@age-keygen -o ~/.config/sops/age/keys.txt 2>&1
	@echo ""
	@echo "age keypair generated at ~/.config/sops/age/keys.txt"
	@echo ""
	@echo "NEXT STEPS:"
	@echo "  1. copy the public key above into .sops.yaml (replace age1xxxxx)"
	@echo "  2. back up ~/.config/sops/age/keys.txt somewhere safe"
	@echo "  3. set SOPS_AGE_KEY GitHub secret to the private key line from keys.txt"

## generate compose/.env with random secrets, encrypted with SOPS
gen-env:
	@if [ -f $(COMPOSE_DIR)/.env ]; then \
		echo "error: $(COMPOSE_DIR)/.env already exists. run 'make edit-env' to modify."; \
		exit 1; \
	fi
	@command -v sops >/dev/null || { echo "error: sops not found. brew install sops"; exit 1; }
	@echo "generating $(COMPOSE_DIR)/.env with random secrets..."
	@( \
		echo "# generated $$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
		echo ""; \
		echo "POSTGRES_PASSWORD=$$(openssl rand -base64 32)"; \
		echo ""; \
		ENC_KEY=$$(openssl rand -base64 32); \
		echo "RAUTHY_ENC_KEYS=key01/$$ENC_KEY"; \
		echo "RAUTHY_ENC_KEY_ACTIVE=key01"; \
		echo ""; \
		echo "RAUTHY_HQL_SECRET_RAFT=$$(openssl rand -hex 16)"; \
		echo "RAUTHY_HQL_SECRET_API=$$(openssl rand -hex 16)"; \
		echo ""; \
		echo "SYNAPSE_OIDC_CLIENT_SECRET=$$(openssl rand -base64 32)"; \
		echo ""; \
		BOOT_PASS=$$(openssl rand -base64 24); \
		echo "RAUTHY_BOOTSTRAP_PASSWORD=$$BOOT_PASS"; \
		echo ""; \
		echo "ADMIN_EMAIL=admin@carp.rodeo"; \
		echo ""; \
		echo "SMTP_URL=smtp.resend.com"; \
		echo "SMTP_PORT=465"; \
		echo "SMTP_USERNAME=resend"; \
		echo "SMTP_PASSWORD=re_xxxxx"; \
		echo "SMTP_FROM=carp.rodeo <auth@carp.rodeo>"; \
		echo ""; \
		echo "S3_ACCESS_KEY=change-me"; \
		echo "S3_SECRET_KEY=change-me"; \
		echo "S3_ENDPOINT=https://s3.us-east-va.perf.cloud.ovh.us"; \
		echo "S3_REGION=us-east-1"; \
		echo "S3_MEDIA_BUCKET=carp-rodeo-synapse-media"; \
		echo "S3_BACKUP_BUCKET=carp-rodeo-rauthy-backups"; \
		echo "S3_PICTURES_BUCKET=carp-rodeo-rauthy-pictures"; \
	) > $(COMPOSE_DIR)/.env
	@echo ""
	@echo "bootstrap password: $$(grep RAUTHY_BOOTSTRAP_PASSWORD $(COMPOSE_DIR)/.env | cut -d= -f2)"
	@echo "save it — you need it for the first Rauthy admin login."
	@echo ""
	@echo "fill in SMTP_PASSWORD (Resend API key) and S3 credentials, then run:"
	@echo "  make edit-env    # opens decrypted .env in $$EDITOR"
	@echo ""
	@echo "encrypting with SOPS..."
	@sops -e -i $(COMPOSE_DIR)/.env
	@echo "done. $(COMPOSE_DIR)/.env is now encrypted and safe to commit."

## generate infra/terraform.tfvars.enc from the example, encrypted with SOPS
gen-tfvars:
	@if [ -f $(INFRA_DIR)/terraform.tfvars.enc ]; then \
		echo "error: $(INFRA_DIR)/terraform.tfvars.enc already exists. run 'make edit-tfvars' to modify."; \
		exit 1; \
	fi
	@command -v sops >/dev/null || { echo "error: sops not found. brew install sops"; exit 1; }
	@cp $(INFRA_DIR)/terraform.tfvars.example $(INFRA_DIR)/terraform.tfvars.enc
	@echo "encrypting $(INFRA_DIR)/terraform.tfvars.enc with SOPS..."
	@sops -e -i $(INFRA_DIR)/terraform.tfvars.enc
	@echo "done. run 'make edit-tfvars' to fill in your credentials."

## edit compose/.env (decrypts in $$EDITOR, re-encrypts on save)
edit-env:
	sops $(COMPOSE_DIR)/.env

## edit terraform.tfvars.enc (decrypts in $$EDITOR, re-encrypts on save)
edit-tfvars:
	sops $(INFRA_DIR)/terraform.tfvars.enc

## decrypt compose/.env to stdout (for debugging, never redirect to a file)
decrypt-env:
	@sops -d $(COMPOSE_DIR)/.env

## decrypt terraform.tfvars.enc to stdout
decrypt-tfvars:
	@sops -d $(INFRA_DIR)/terraform.tfvars.enc

# ──────────────────────────────────────────────
# remote deployment
# ──────────────────────────────────────────────

.PHONY: ssh deploy deploy-compose deploy-env logs

## SSH into the server
ssh:
	ssh $(SSH_USER)@$(SERVER_IP)

## full deploy: generate configs from templates, sync compose stack + secrets, restart services
deploy: generate-configs deploy-compose deploy-env cleanup-generated
	ssh $(SSH_USER)@$(SERVER_IP) "cd $(REMOTE_DIR) && docker compose pull && docker compose up -d --build"

## generate templated configs from .env (clients.json, etc)
generate-configs:
	@if [ ! -f $(COMPOSE_DIR)/.env ]; then \
		echo "error: $(COMPOSE_DIR)/.env not found. run 'make gen-env' first."; \
		exit 1; \
	fi
	@echo "generating templated configs..."
	@SYNAPSE_OIDC_CLIENT_SECRET=$$(sops -d $(COMPOSE_DIR)/.env | grep '^SYNAPSE_OIDC_CLIENT_SECRET=' | cut -d= -f2) \
		envsubst '$$SYNAPSE_OIDC_CLIENT_SECRET' < $(COMPOSE_DIR)/rauthy/bootstrap/clients.json.template > $(COMPOSE_DIR)/rauthy/bootstrap/clients.json

## cleanup generated files after deploy
cleanup-generated:
	@rm -f $(COMPOSE_DIR)/rauthy/bootstrap/clients.json

## sync compose directory to server (configs, Caddyfile, Dockerfiles)
deploy-compose:
	rsync -avz --delete \
		--exclude '.env' \
		--exclude '.env.example' \
		$(COMPOSE_DIR)/ $(SSH_USER)@$(SERVER_IP):$(REMOTE_DIR)/

## decrypt .env and sync to server
deploy-env:
	@if [ ! -f $(COMPOSE_DIR)/.env ]; then \
		echo "error: $(COMPOSE_DIR)/.env not found. run 'make gen-env' first."; \
		exit 1; \
	fi
	@sops -d $(COMPOSE_DIR)/.env > $(COMPOSE_DIR)/.env.plaintext
	@ssh $(SSH_USER)@$(SERVER_IP) "sudo mkdir -p $(REMOTE_DIR) && sudo chown $(SSH_USER):$(SSH_USER) $(REMOTE_DIR)"
	@scp $(COMPOSE_DIR)/.env.plaintext $(SSH_USER)@$(SERVER_IP):$(REMOTE_DIR)/.env
	@rm -f $(COMPOSE_DIR)/.env.plaintext
	@echo "decrypted .env synced to server and local plaintext removed."

## tail logs on the remote server
logs:
	ssh $(SSH_USER)@$(SERVER_IP) "cd $(REMOTE_DIR) && docker compose logs -f --tail=100"

# ──────────────────────────────────────────────
# utilities
# ──────────────────────────────────────────────

.PHONY: check-dns federation-test

## check that DNS records resolve correctly
check-dns:
	@echo "--- A records ---"
	@dig +short carp.rodeo A
	@dig +short auth.carp.rodeo A
	@dig +short synapse.carp.rodeo A
	@echo "--- TXT records ---"
	@dig +short carp.rodeo TXT
	@dig +short _dmarc.carp.rodeo TXT
	@echo "--- well-known ---"
	@curl -sS https://carp.rodeo/.well-known/matrix/server 2>/dev/null || echo "(not reachable yet)"
	@echo ""
	@curl -sS https://carp.rodeo/.well-known/matrix/client 2>/dev/null || echo "(not reachable yet)"
	@echo ""

## test Matrix federation using federation tester
federation-test:
	@echo "checking federation for carp.rodeo..."
	@curl -sS "https://federationtester.matrix.org/api/report?server_name=carp.rodeo" | python3 -m json.tool | head -30

## show help
help:
	@echo "ossuary — carp.rodeo infrastructure"
	@echo ""
	@echo "first-time setup:"
	@echo "  make init-secrets   generate age keypair for SOPS"
	@echo "  make gen-env        generate compose/.env (encrypted)"
	@echo "  make gen-tfvars     generate terraform.tfvars (encrypted)"
	@echo "  make init           terraform init (with S3 backend)"
	@echo ""
	@echo "terraform:"
	@echo "  make plan           preview changes (auto-decrypts tfvars)"
	@echo "  make apply          apply changes (auto-decrypts tfvars)"
	@echo "  make destroy        tear down all infrastructure"
	@echo "  make output         show terraform outputs"
	@echo ""
	@echo "secrets:"
	@echo "  make edit-env       edit compose/.env (SOPS decrypt/re-encrypt)"
	@echo "  make edit-tfvars    edit terraform.tfvars (SOPS decrypt/re-encrypt)"
	@echo "  make decrypt-env    print decrypted .env to stdout"
	@echo "  make decrypt-tfvars print decrypted tfvars to stdout"
	@echo ""
	@echo "deployment:"
	@echo "  make ssh            SSH into the server"
	@echo "  make deploy         full deploy (sync + decrypt + restart)"
	@echo "  make deploy-compose sync configs only"
	@echo "  make deploy-env     decrypt + sync .env only"
	@echo "  make logs           tail remote logs"
	@echo ""
	@echo "utilities:"
	@echo "  make check-dns       verify DNS records"
	@echo "  make federation-test test Matrix federation"
