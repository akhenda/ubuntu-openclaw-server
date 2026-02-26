SHELL := /bin/bash
export ANSIBLE_HOME := $(CURDIR)/.ansible

.PHONY: deps galaxy lint test-docker test-vagrant run-prod run-vagrant run-shell run-socket-proxy run-traefik run-homepage

deps:
	pip install -r requirements.txt

galaxy:
	ansible-galaxy collection install -r ansible/requirements.yml

lint:
	ansible-lint --project-dir "$(CURDIR)"
	yamllint .

test-docker:
	@set -o pipefail; molecule test -s docker 2>&1 | grep -vE "WARNING  Driver .* does not provide a schema."

test-vagrant:
	@set -o pipefail; molecule test -s vagrant 2>&1 | grep -vE "WARNING  Driver .* does not provide a schema.|\\[WARNING\\]: Found variable using reserved name: connection"

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
