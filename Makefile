PREFIX ?= $(HOME)/.local

build:
	swift build -c release

install: build
	mkdir -p $(PREFIX)/bin
	cp .build/release/offload $(PREFIX)/bin/offload.new
	mv $(PREFIX)/bin/offload.new $(PREFIX)/bin/offload
	@echo "Installed $(PREFIX)/bin/offload"

test: build
	swift test
	PATH="$(CURDIR)/.build/release:$$PATH" scripts/selftest.sh

bench: build
	PATH="$(CURDIR)/.build/release:$$PATH" python3 benchmarks/run.py

uninstall:
	rm -f $(PREFIX)/bin/offload

.PHONY: build install test bench uninstall
