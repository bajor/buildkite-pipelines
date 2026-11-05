SCRIPTS := hooks/command bin/run-local bin/install-pre-push-hook $(wildcard lib/*.sh checks/*.sh)

.PHONY: test lint

test: lint
	bats tests

lint:
	shellcheck -x $(SCRIPTS)
