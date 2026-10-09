# Fixture consumer for the library self-tests (.github/workflows/ci.yml). Not a template:
# the verbs check what the self-tests configure (tool versions, make-env, cache paths, install).
IMAGE ?= metrify-workflows-fixture:dev

.PHONY: help install dev format format-check lint typecheck test fix check build docker-build

help:
	@echo "Fixture for metrify-workflows self-tests"

# The other verbs fail without this marker, which proves every workflow runs install first.
install:
	touch .installed

dev format:
	@echo "$@: nothing to do"

format-check typecheck: .installed
	@echo "$@: nothing to do"

lint: .installed
	node --version | grep '^v24\.'

test: .installed
	@test -n "$$FIXTURE_TOKEN" || { echo "FIXTURE_TOKEN is not set: make-env was not exported"; exit 1; }
	@echo "FIXTURE_TOKEN=$$FIXTURE_TOKEN (must show *** in the CI log)"
	mkdir -p .cache
	date >.cache/last-run

fix: format

check: format-check lint typecheck test

build: .installed
	python3 --version | grep '^Python 3\.14'
	go version | grep ' go1\.26'

docker-build: .installed
	docker build -t $(IMAGE) .

.installed:
	@echo "make install did not run first"; exit 1
