SHELL := /bin/bash
export ANSIBLE_HOME := $(CURDIR)/.ansible
OPENCLAW_UI_PORT ?= 3000
CONFIG_FILE ?= config/.env

.PHONY: deps check-config run-install test-scripts galaxy lint test-docker test-vagrant test-vagrant-integration run-prod run-vagrant run-shell run-socket-proxy run-traefik run-homepage local-openclaw-up local-openclaw-tunnel local-openclaw-down

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

galaxy:
	ansible-galaxy collection install -r ansible/requirements.yml

lint:
	ansible-lint --project-dir "$(CURDIR)"
	yamllint .

test-docker:
	@set -o pipefail; molecule test -s docker 2>&1 | grep -vE "WARNING  Driver .* does not provide a schema."

test-vagrant:
	@set -o pipefail; molecule test -s vagrant 2>&1 | grep -vE "WARNING  Driver .* does not provide a schema.|\\[WARNING\\]: Found variable using reserved name: connection"

test-vagrant-integration:
	@set -o pipefail; molecule test -s vagrant-integration 2>&1 | grep -vE "WARNING  Driver .* does not provide a schema.|\\[WARNING\\]: Found variable using reserved name: connection"

run-prod:
	ansible-playbook -i ansible/inventories/prod/hosts.ini ansible/playbooks/site.yml

run-vagrant:
	ansible-playbook -i ansible/inventories/vagrant/hosts.ini ansible/playbooks/site.yml

run-shell:
	ansible-playbook -i ansible/inventories/prod/hosts.ini ansible/playbooks/oh_my_zsh.yml

run-socket-proxy:
	ansible-playbook -i ansible/inventories/prod/hosts.ini ansible/playbooks/socket_proxy.yml

run-traefik:
	ansible-playbook -i ansible/inventories/prod/hosts.ini ansible/playbooks/traefik.yml

run-homepage:
	ansible-playbook -i ansible/inventories/prod/hosts.ini ansible/playbooks/homepage.yml

local-openclaw-up:
	-molecule destroy -s vagrant-integration
	molecule create -s vagrant-integration
	molecule converge -s vagrant-integration -- -e @$(CURDIR)/molecule/vagrant-integration/local-openclaw.vars

local-openclaw-tunnel:
	@set -euo pipefail; \
	vagrant_dir="$$(find .ansible/tmp -type f -path "*vagrant-integration/Vagrantfile" -print -quit | xargs -I{} dirname "{}")"; \
	if [ -z "$$vagrant_dir" ]; then \
		echo "No vagrant-integration VM found. Run 'make local-openclaw-up' first."; \
		exit 1; \
	fi; \
	echo "Opening tunnel http://127.0.0.1:$(OPENCLAW_UI_PORT) -> VM localhost:$(OPENCLAW_UI_PORT)"; \
	echo "Press Ctrl+C to close the tunnel."; \
	(cd "$$vagrant_dir" && vagrant ssh -- -N -L $(OPENCLAW_UI_PORT):127.0.0.1:$(OPENCLAW_UI_PORT))

local-openclaw-down:
	molecule destroy -s vagrant-integration
