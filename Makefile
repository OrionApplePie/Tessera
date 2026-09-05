.DEFAULT_GOAL := help
SHELL := /bin/bash
# pipefail нужен, чтобы падение swift build не терялось в пайпе с tee/xcbeautify.
.SHELLFLAGS := -eu -o pipefail -c

SOURCES := Sources Tests
CONFIG ?= debug
BUILD_LOG := build.log

# С полным Xcode всё лежит на путях поиска по умолчанию и обе переменные ниже
# остаются пустыми: каталог Library/Developer/Frameworks есть только в Command
# Line Tools. CLT же кладут Testing.framework и sourcekitdInProc в стороне, и без
# подсказки swift test не собирается, а swiftlint падает на dlopen.
DEVELOPER_ROOT := $(shell xcode-select -p)
CLT_FRAMEWORKS := $(DEVELOPER_ROOT)/Library/Developer/Frameworks
ifneq ($(wildcard $(CLT_FRAMEWORKS)/Testing.framework),)
# Оверлея _Testing_Foundation в CLT нет, поэтому его поиск отключён: иначе
# import Testing рядом с import Foundation не компилируется.
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) \
	-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
	-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)
LINT_ENV := TOOLCHAIN_DIR=$(DEVELOPER_ROOT)
endif

.PHONY: help
help: ## Показать этот список
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build: ## Собрать (CONFIG=debug|release)
	swift build -c $(CONFIG)

# Без подкоманды бинарь печатает help и выходит: приложение поднимает только
# `run`. RUN_ARGS='windows' — прогнать другую команду тем же способом.
RUN_ARGS ?= run

.PHONY: run
run: ## Запустить локально (RUN_ARGS='windows' — другая команда)
	swift run Tessera $(RUN_ARGS)

.PHONY: test
test: ## Прогнать все тесты
	swift test $(TEST_FLAGS)

.PHONY: test-one
test-one: ## Один тест: FILTER='ClientTests/testRetry' make test-one
	@test -n "$(FILTER)" || { echo "Задай FILTER, например FILTER='ClientTests/testRetry'"; exit 2; }
	swift test $(TEST_FLAGS) --filter '$(FILTER)'

.PHONY: format
format: ## Отформатировать код на месте
	swift format --recursive --in-place $(SOURCES)

.PHONY: format-check
format-check: ## Проверить форматирование, ничего не меняя
	swift format lint --recursive --strict $(SOURCES)

.PHONY: lint
lint: ## SwiftLint, строгий режим
	$(LINT_ENV) swiftlint --strict

.PHONY: formula
formula: ## brew style для формулы. Пропускается там, где нет Homebrew.
	@if command -v brew >/dev/null 2>&1; then \
		brew style Formula/tessera.rb; \
	else \
		echo "formula: brew не найден, пропускаю"; \
	fi

.PHONY: analyze
analyze: ## SwiftLint analyzer: мёртвый код, лишние импорты. Требует полной пересборки.
	swift package clean
	swift build 2>&1 | tee $(BUILD_LOG)
	$(LINT_ENV) swiftlint analyze --strict --compiler-log-path $(BUILD_LOG)

.PHONY: check
check: format-check lint formula build test ## Всё сразу. Обязательно перед завершением работы.
	@echo "check: ok"

.PHONY: clean
clean: ## Удалить артефакты сборки
	swift package clean
	rm -rf .build $(BUILD_LOG)

.PHONY: setup
setup: ## Поставить инструменты разработки
	brew install swiftlint xcbeautify lefthook gitleaks
	lefthook install
