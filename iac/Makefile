###############################################################################
# Makefile — DevOps Demo IaC
###############################################################################

SHELL    := /usr/bin/env bash
IAC_DIR  := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
SCRIPTS  := $(IAC_DIR)/scripts

# Default target
.DEFAULT_GOAL := help

.PHONY: help apply destroy plan kubeconfig fmt validate bootstrap

help: ## Show this help message
	@echo ""
	@echo "  DevOps Demo — Terraform Makefile"
	@echo ""
	@echo "  Usage: make <target> ENV=<dev|prod>"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-20s\033[0m %s\n",$$1,$$2}'
	@echo ""

bootstrap: ## Create S3 state bucket (S3 native locking, no DynamoDB)
	@terraform -chdir=$(IAC_DIR)/backend init -upgrade
	@terraform -chdir=$(IAC_DIR)/backend apply \
		-var="project=devops-demo" \
		-var="region=us-east-1" \
		-auto-approve

plan: ## Plan the stack (ENV=dev|prod)
	@$(SCRIPTS)/apply.sh $(ENV) --plan-only

apply: ## Apply the stack (ENV=dev|prod)
	@$(SCRIPTS)/apply.sh $(ENV)

apply-auto: ## Apply without confirmation prompt (ENV=dev|prod)
	@$(SCRIPTS)/apply.sh $(ENV) --auto-approve

destroy: ## Destroy the stack (ENV=dev|prod)
	@$(SCRIPTS)/destroy.sh $(ENV)

destroy-auto: ## Destroy without confirmation prompt — USE WITH CARE (ENV=dev|prod)
	@$(SCRIPTS)/destroy.sh $(ENV) --auto-approve

kubeconfig: ## Refresh kubeconfig for the EKS cluster (ENV=dev|prod)
	@$(SCRIPTS)/kubeconfig.sh $(ENV)

fmt: ## Format all Terraform files
	@terraform fmt -recursive $(IAC_DIR)
	@echo "Formatting complete."

validate: ## Validate the stack (ENV=dev|prod)
	@STACK=$(IAC_DIR)/stacks/$(ENV); \
	terraform -chdir=$$STACK init -backend=false -upgrade && \
	terraform -chdir=$$STACK validate

lint: ## Run tflint (requires tflint installed)
	@command -v tflint >/dev/null || { echo "tflint not found — install from https://github.com/terraform-linters/tflint"; exit 1; }
	@tflint --recursive $(IAC_DIR)

output: ## Print stack outputs (ENV=dev|prod)
	@terraform -chdir=$(IAC_DIR)/stacks/$(ENV) output
