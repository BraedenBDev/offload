PREFIX ?= $(HOME)/.local
SOURCE_HASH = cat Sources/offload/*.swift | shasum -a 256 | cut -d' ' -f1

build:
	swift build -c release

# Refreshes the binary that ships inside the skill. Run it before every commit that changes Sources.
bundle: build
	cp .build/release/offload skills/offload/bin/offload.new
	strip -x skills/offload/bin/offload.new
	codesign --force --sign - skills/offload/bin/offload.new
	mv skills/offload/bin/offload.new skills/offload/bin/offload
	$(SOURCE_HASH) > skills/offload/bin/SOURCE_SHA256

check-bundle:
	@test "$$($(SOURCE_HASH))" = "$$(cat skills/offload/bin/SOURCE_SHA256)" || (echo "skills/offload/bin/offload is out of date: run make bundle"; exit 1)
	@test "$$(skills/offload/bin/offload version)" = "$$(grep '^let version' Sources/offload/Offload.swift | cut -d'"' -f2)" || (echo "bundled binary reports the wrong version: run make bundle"; exit 1)

install: build
	mkdir -p $(PREFIX)/bin
	cp .build/release/offload $(PREFIX)/bin/offload.new
	mv $(PREFIX)/bin/offload.new $(PREFIX)/bin/offload
	@echo "Installed $(PREFIX)/bin/offload"

test: build
	swift test
	OFFLOAD="$(CURDIR)/.build/release/offload" skills/offload/scripts/selftest.sh

# Installs from a tarball into a sandbox with developer tools, Homebrew and your config blocked.
virgin: bundle
	scripts/virgin-test.sh

bench: build
	PATH="$(CURDIR)/.build/release:$$PATH" python3 benchmarks/run.py

uninstall:
	rm -f $(PREFIX)/bin/offload

.PHONY: build bundle check-bundle install test virgin bench uninstall
