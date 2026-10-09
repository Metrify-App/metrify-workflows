# Checks of the library itself. Run inside the dev shell: `nix develop --command make <rule>`
# (direnv users: `use flake`). CI runs the same rules through the library's own workflows.
SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-6s\033[0m %s\n", $$1, $$2}'

.PHONY: lint
lint: ## Static analysis of workflows, actions and scripts
	actionlint
	zizmor --offline --config .github/zizmor.yml $(wildcard .github examples tests)
	shellcheck -x $(wildcard scripts/*.sh tests/unit/*.sh tests/act/*.sh)

.PHONY: test
test: ## Unit tests of the scripts
	tests/unit/run.sh

.PHONY: act
act: ## Run ci.yml locally with act; pass act options in ARGS, e.g. ARGS="-j fixture-test"
	tests/act/run.sh $(ARGS)
