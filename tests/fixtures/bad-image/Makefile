# Fixture consumer whose docker-build ignores $(IMAGE): ci.yml checks the contract error.
.PHONY: install docker-build

install:
	@echo "install: nothing to do"

docker-build:
	docker build -t metrify-workflows-bad-image:dev .
