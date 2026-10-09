# Checks of the library itself. Run inside the dev shell: `nix develop --command make <rule>`
# (direnv users: `use flake`). CI runs the same rules through the library's own workflows.
SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-6s\033[0m %s\n", $$1, $$2}'

.PHONY: lint
lint: ## Static analysis of scripts
	shellcheck -x $(wildcard scripts/*.sh tests/unit/*.sh)

.PHONY: test
test: ## Unit tests of the scripts
	tests/unit/run.sh
