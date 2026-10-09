# The library follows the Metrify make verbs it enforces (docs/contract.md). Run inside the dev
# shell: `nix develop --command make <verb>` (direnv users: `use flake`). CI runs `make check`
# through the library's own check.yml.
SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

.PHONY: help install dev format format-check lint typecheck test fix check act

help: ## Show this help
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

install: ## Install dependencies (the Nix dev shell provides every tool)
	@echo "install: nothing to do"

dev: ## Run the project locally (a library: see `make act`)
	@echo "dev: nothing to do"

format: ## Format the code
	@echo "format: nothing to do"

format-check: ## Check formatting
	@echo "format-check: nothing to do"

lint: ## Static analysis of workflows, actions and scripts
	actionlint
	zizmor --offline --config .github/zizmor.yml $(wildcard .github examples tests)
	shellcheck -x $(wildcard scripts/*.sh tests/unit/*.sh tests/act/*.sh)

typecheck: ## Type check
	@echo "typecheck: nothing to do"

test: ## Unit tests of the scripts
	tests/unit/run.sh

fix: format ## Format and apply autofixable lint
	@echo "fix: no autofix lint configured"

check: format-check lint typecheck test ## Everything the CI runs

act: ## Run ci.yml locally with act; pass act options in ARGS, e.g. ARGS="-j fixture-test"
	tests/act/run.sh $(ARGS)
