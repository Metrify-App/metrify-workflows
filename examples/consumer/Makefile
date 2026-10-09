# Example consumer Makefile for Metrify-App/metrify-workflows (Node.js service).
# Copy it, then replace the commands with your stack's. Contract: docs/contract.md.
IMAGE ?= example-service:dev

.PHONY: install lint test build docker-build

install:
	npm ci

lint: install
	npm run lint

test: install
	npm test

build: install
	npm run build

docker-build:
	docker build -t $(IMAGE) .
