# Example consumer Makefile for Metrify-App/metrify-workflows (Node.js service), following the
# Metrify make verbs (metrify-template STANDARD.md). Replace the commands with your stack's.
IMAGE ?= example-service:dev

.DEFAULT_GOAL := help
.PHONY: help install dev format format-check lint typecheck test fix check docker-build

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*##/ {printf "    %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Install dependencies
	npm ci --no-fund --no-audit

dev: ## Run the project locally
	npm run dev

format: ## Format the code
	npx prettier --write .

format-check: ## Check formatting
	npx prettier --check .

lint: ## Lint
	npx eslint .

typecheck: ## Type check
	npx tsc --noEmit

test: ## Run the tests
	npm test

fix: format ## Format and apply autofixable lint
	npx eslint --fix .

check: format-check lint typecheck test ## Everything the CI runs

# Optional verb: only for a repo that ships an image. Must tag $(IMAGE) and never push.
docker-build: ## Build the Docker image
	docker build -t $(IMAGE) .
