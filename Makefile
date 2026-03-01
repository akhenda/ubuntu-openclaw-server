SHELL := /bin/bash
.DEFAULT_GOAL := help

CONFIG_FILE ?= config/.env
OPENCLAW_UI_PORT ?= 3000
VENV_PYTHON := .venv/bin/python
VENV_BIN := .venv/bin
PIP ?= python3 -m pip
YAMLLINT ?= yamllint
MOLECULE ?= molecule
MOLECULE_ENV ?=

ifneq ("$(wildcard $(VENV_PYTHON))","")
PIP := $(VENV_PYTHON) -m pip
YAMLLINT := $(VENV_PYTHON) -m yamllint
MOLECULE := $(VENV_PYTHON) -m molecule
MOLECULE_ENV := PATH="$(abspath $(VENV_BIN)):$$PATH"
endif

.PHONY: \
	help \
	deps deps-dev deps-test deps-lint check-config run-install test-scripts \
	lint test-docker test-vagrant \
	run-prod run-vagrant run-shell run-socket-proxy run-traefik run-homepage \
	local-openclaw-up local-openclaw-tunnel local-openclaw-down

help:
	@echo "Active Bash Toolkit Targets:"
	@echo "  make deps                         Install full dev dependencies (alias: deps-dev)"
	@echo "  make deps-dev                     Install full dev dependencies"
	@echo "  make deps-test                    Install test dependencies (Molecule stack)"
	@echo "  make deps-lint                    Install lint dependencies"
	@echo "  make lint                         Lint Bash toolkit files (bash -n + yamllint)"
	@echo "  make test-docker                  Run Molecule docker scenario (Bash installer dry-run)"
	@echo "  make test-vagrant                 Run Molecule vagrant scenario (Bash installer live)"
	@echo "  make check-config                 Validate config file (CONFIG_FILE=...)"
	@echo "  make run-install                  Run full Bash installer"
	@echo "  make test-scripts                 Run Bash phase test suite"

deps: deps-dev

deps-dev:
	$(PIP) install -r requirements-dev.txt

deps-test:
	$(PIP) install -r requirements-test.txt

deps-lint:
	$(PIP) install -r requirements-lint.txt

check-config:
	bash scripts/install.sh --check-config --config $(CONFIG_FILE) --print-config

run-install:
	bash scripts/install.sh --config $(CONFIG_FILE) --print-config

test-scripts:
	bash tests/test_packages_phase.sh
	bash tests/test_system_phase.sh
	bash tests/test_user_phase.sh
	bash tests/test_ssh_phase.sh
	bash tests/test_firewall_phase.sh
	bash tests/test_tailscale_phase.sh
	bash tests/test_socket_proxy_phase.sh
	bash tests/test_edge_phase.sh
	bash tests/test_edge_socket_proxy_contract.sh
	bash tests/test_dns_phase.sh
	bash tests/test_openclaw_phase.sh
	bash tests/test_apps_phase.sh
	bash tests/test_apps_hub_phase.sh
	bash tests/test_systemd_phase.sh
	bash tests/test_motd_phase.sh
	bash tests/test_oh_my_zsh_phase.sh
	bash tests/test_report_phase.sh
	bash tests/test_verify_phase.sh

lint:
	bash -n scripts/install.sh scripts/lib/*.sh tests/*.sh
	$(YAMLLINT) .

test-docker:
	$(MOLECULE_ENV) $(MOLECULE) test -s docker

test-vagrant:
	$(MOLECULE_ENV) $(MOLECULE) test -s vagrant

run-prod run-vagrant run-shell run-socket-proxy run-traefik run-homepage local-openclaw-up local-openclaw-tunnel local-openclaw-down:
	@echo "Deprecated legacy target '$@'."
	@echo "Use 'make run-install CONFIG_FILE=...'."
	@exit 2
