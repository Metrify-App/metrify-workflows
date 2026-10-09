# Fixture consumer for the library self-tests (.github/workflows/ci.yml). Not a template:
# the rules check what the self-tests configure (tool versions, make-env, cache paths).
IMAGE ?= metrify-workflows-fixture:dev

.PHONY: lint test build docker-build

lint:
	node --version | grep '^v24\.'

test:
	@test -n "$$FIXTURE_TOKEN" || { echo "FIXTURE_TOKEN is not set: make-env was not exported"; exit 1; }
	@echo "FIXTURE_TOKEN=$$FIXTURE_TOKEN (must show *** in the CI log)"
	mkdir -p .cache
	date >.cache/last-run

build:
	python3 --version | grep '^Python 3\.14'
	go version | grep ' go1\.26'

docker-build:
	docker build -t $(IMAGE) .
