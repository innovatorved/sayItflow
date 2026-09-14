.PHONY: test build verify dmg install

ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
SCHEME := SayItFlow
DEST ?= /Applications/SayItFlow.app

test:
	cd "$(ROOT)apps/macos" && xcodebuild test \
		-scheme $(SCHEME) \
		-destination 'platform=macOS'

verify:
	chmod +x "$(ROOT)scripts/verify-scaffold.sh"
	"$(ROOT)scripts/verify-scaffold.sh"

build:
	@if ! xcodebuild -version >/dev/null 2>&1; then \
		echo "ERROR: Full Xcode required."; exit 1; \
	fi
	cd "$(ROOT)apps/macos" && xcodebuild \
		-scheme $(SCHEME) \
		-configuration Debug \
		-destination 'platform=macOS' \
		build

dmg:
	chmod +x "$(ROOT)scripts/make-dmg.sh"
	"$(ROOT)scripts/make-dmg.sh"

install: dmg
	@pkill -x SayItFlow 2>/dev/null || true
	@sleep 1
	@hdiutil attach "$(ROOT)build/SayItFlow.dmg" -nobrowse -mountpoint /tmp/sayitflow-dmg; \
	rm -rf "$(DEST)"; \
	ditto /tmp/sayitflow-dmg/SayItFlow.app "$(DEST)"; \
	hdiutil detach /tmp/sayitflow-dmg; \
	echo "Installed $(DEST)"
