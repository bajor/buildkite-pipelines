SCRIPTS := hooks/command $(wildcard lib/*.sh checks/*.sh)

.PHONY: test lint

test: lint
	bats tests

lint:
	shellcheck $(SCRIPTS)
