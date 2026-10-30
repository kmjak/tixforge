# make check: everything CI checks, on this machine. Run it before a PR.
# Tools: shellcheck, shfmt, actionlint, zizmor, jq (brew install shellcheck
# shfmt actionlint zizmor jq). The versions CI uses are in
# .github/workflows/test.yml.

SH := $(shell git ls-files '*.sh')
WORKFLOWS := $(wildcard .github/workflows/*.yml) $(wildcard templates/github/*.yml)
SUITES := guard json-get scripts plugin

.PHONY: check lint fmt test test-bash32 validate

check: lint test test-bash32 validate

lint:
	shellcheck -S warning $(SH)
	shfmt -d $(SH)
	actionlint $(WORKFLOWS)
	zizmor --offline --quiet $(WORKFLOWS)

fmt:
	shfmt -w $(SH)

test:
	@for s in $(SUITES); do bash tests/$$s.test.sh || exit 1; done

# macOS ships bash 3.2 as /bin/bash; the scripts must run in it.
test-bash32:
	@if [ "$$(uname)" = Darwin ]; then \
	  for s in $(SUITES); do /bin/bash tests/$$s.test.sh || exit 1; done; \
	else echo "test-bash32: not macOS, skipped (CI runs it on macos-latest)"; fi

validate:
	@if command -v claude > /dev/null; then claude plugin validate .; \
	else echo "validate: claude not found, skipped"; fi
