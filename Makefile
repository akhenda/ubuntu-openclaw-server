SHELL := /bin/bash
.DEFAULT_GOAL := help

CONFIG_FILE ?= config/.env
OPENCLAW_UI_PORT ?= 3000

.PHONY: \
	help \
	deps check-config run-install test-scripts \
	legacy-lint legacy-test-docker legacy-test-vagrant legacy-test-vagrant-integration \
	lint test-docker test-vagrant test-vagrant-integration \
	run-prod run-vagrant run-shell run-socket-proxy run-traefik run-homepage \
	local-openclaw-up local-openclaw-tunnel local-openclaw-down

help:
	@echo "Active Bash Toolkit Targets:"
	@echo "  make deps                         Install Python dependencies"
	@echo "  make check-config                 Validate config file (CONFIG_FILE=...)"
	@echo "  make run-install                  Run full Bash installer"
	@echo "  make test-scripts                 Run Bash phase test suite"
	@echo ""
	@echo "Legacy Targets (require old ansible/ layout):"
	@echo "  make legacy-lint"
	@echo "  make legacy-test-docker"
	@echo "  make legacy-test-vagrant"
	@echo "  make legacy-test-vagrant-integration"

deps:
	pip install -r requirements.txt

check-config:
	bash scripts/install.sh --check-config --config $(CONFIG_FILE) --print-config

run-install:
	bash scripts/install.sh --config $(CONFIG_FILE) --print-config

test-scripts:
	bash tests/test_packages_phase.sh
	bash tests/test_user_phase.sh
	bash tests/test_ssh_phase.sh
	bash tests/test_firewall_phase.sh
	bash tests/test_edge_phase.sh
	bash tests/test_dns_phase.sh
	bash tests/test_openclaw_phase.sh
	bash tests/test_apps_phase.sh
	bash tests/test_report_phase.sh
	bash tests/test_verify_phase.sh

legacy-lint:
	@test -d ansible || { echo "Legacy target unavailable: ansible/ directory not found."; exit 2; }
	ansible-lint --project-dir "$(CURDIR)"
	yamllint .

legacy-test-docker:
	@test -d ansible || { echo "Legacy target unavailable: ansible/ directory not found."; exit 2; }
	@test -d molecule || { echo "Legacy target unavailable: molecule/ directory not found."; exit 2; }
	@set -o pipefail; molecule test -s docker 2>&1 | grep -vE "WARNING  Driver .* does not provide a schema."

legacy-test-vagrant:
	@test -d ansible || { echo "Legacy target unavailable: ansible/ directory not found."; exit 2; }
	@test -d molecule || { echo "Legacy target unavailable: molecule/ directory not found."; exit 2; }
	@set -o pipefail; molecule test -s vagrant 2>&1 | grep -vE "WARNING  Driver .* does not provide a schema.|\\[WARNING\\]: Found variable using reserved name: connection"

legacy-test-vagrant-integration:
	@test -d ansible || { echo "Legacy target unavailable: ansible/ directory not found."; exit 2; }
	@test -d molecule || { echo "Legacy target unavailable: molecule/ directory not found."; exit 2; }
	@set -o pipefail; molecule test -s vagrant-integration 2>&1 | grep -vE "WARNING  Driver .* does not provide a schema.|\\[WARNING\\]: Found variable using reserved name: connection"

lint: legacy-lint

test-docker: legacy-test-docker

test-vagrant: legacy-test-vagrant

test-vagrant-integration: legacy-test-vagrant-integration

run-prod run-vagrant run-shell run-socket-proxy run-traefik run-homepage local-openclaw-up local-openclaw-tunnel local-openclaw-down:
	@echo "Deprecated legacy target '$@'."
	@echo "Use 'make run-install CONFIG_FILE=...'."
	@echo "If you need old Ansible workflows, restore ansible/ content and use legacy-* targets."
	@exit 2
