# Changelog

## 1.0.0 (2026-10-09)


### Features

* **check:** add check, format-check and typecheck workflows ([8d496a1](https://github.com/Metrify-App/metrify-workflows/commit/8d496a1063db3054763a6c86617a9d5e5a8339cc))
* **docker:** build with make docker-build and push to GHCR ([d9ccefe](https://github.com/Metrify-App/metrify-workflows/commit/d9ccefe8f4813e104c391636b65433a1e4e67682))
* **lint,test,build:** add public make-rule workflows ([c3dc7b1](https://github.com/Metrify-App/metrify-workflows/commit/c3dc7b1f52e651d0fa7e1b2bf97283d366f1bc26))
* **run-make:** run make install before every verb ([a3ac1d4](https://github.com/Metrify-App/metrify-workflows/commit/a3ac1d471bafe195daf923a76ebb2c62e497b10c))
* **scripts:** compute GHCR image name and tags ([b80a3b3](https://github.com/Metrify-App/metrify-workflows/commit/b80a3b3cb16a16c4459095e13551a07f8a72d63a))
* **scripts:** list the standard make verbs a Makefile lacks ([ddefa72](https://github.com/Metrify-App/metrify-workflows/commit/ddefa72eb7cddf522324e83d18308997cf8a08b6))
* **scripts:** run a make rule and check the built image ([a1de7c5](https://github.com/Metrify-App/metrify-workflows/commit/a1de7c53e6725613eb0f3b72040ecca58380df26))
* **scripts:** validate, mask and export make-env lines ([0a3fadf](https://github.com/Metrify-App/metrify-workflows/commit/0a3fadf7f895521dc9d0294084122afe01ec814b))
* **setup-env,run-make:** add internal composite actions ([1342461](https://github.com/Metrify-App/metrify-workflows/commit/1342461b63cd97d8d63b7acb722b70ae44fe5d02))


### Bug Fixes

* **check:** check the standard verbs after make install and make-env ([1a5cbb5](https://github.com/Metrify-App/metrify-workflows/commit/1a5cbb5b70dd8c62e843ab96c21364faebbac8b3))
* **docker:** never fail after a push when Docker reports no digest ([8505e3b](https://github.com/Metrify-App/metrify-workflows/commit/8505e3bc1c7897882fca00a5f0848e2cccd17aaf))
* **docker:** serialize runs per ref so latest never goes back ([d2e3389](https://github.com/Metrify-App/metrify-workflows/commit/d2e3389ae927d00678b05987c46f39569c7850fc))
* **run-make:** explain that install is mandatory when it is missing ([4c3fdc9](https://github.com/Metrify-App/metrify-workflows/commit/4c3fdc9c21c4b165b5eea6008405add7ac5d665f))
* **scripts:** count only real rules and report unreadable Makefiles ([d9b9f3f](https://github.com/Metrify-App/metrify-workflows/commit/d9b9f3f70ad5995873d9a6693b6b5bf835e87e2a))
* **scripts:** keep USE_NIX out of the environment of make rules ([e6bd640](https://github.com/Metrify-App/metrify-workflows/commit/e6bd640b9b71e7cd14ad4dd050ba8307c097ac69))
* **setup-env:** install Nix with nix-quick-install-action ([3759c87](https://github.com/Metrify-App/metrify-workflows/commit/3759c878f2a7746e18cbe9b689437e0fde36de76))

## Changelog
