APP := SimMan.app
INSTALL_DIR := /Applications
# Only the copy needs root, and only when the user can't write to INSTALL_DIR.
SUDO := $(shell test -w $(INSTALL_DIR) || echo sudo)

.PHONY: build run dist install clean

# Wraps the SwiftPM binary for configuration $(1) in an app bundle at build/$(1)/$(APP).
define bundle
	swift build -c $(1)
	rm -rf build/$(1)/$(APP)
	mkdir -p build/$(1)/$(APP)/Contents/MacOS
	cp "$$(swift build -c $(1) --show-bin-path)/SimMan" build/$(1)/$(APP)/Contents/MacOS/SimMan
	cp Support/Info.plist build/$(1)/$(APP)/Contents/Info.plist
	codesign --force --sign - build/$(1)/$(APP)
endef

build:
	$(call bundle,debug)

# Quits any running SimMan first, so only one menu bar icon shows.
run: build
	pkill -x SimMan || true
	while pgrep -x SimMan >/dev/null; do sleep 0.1; done
	open build/debug/$(APP)

dist:
	$(call bundle,release)

install: dist
	pkill -x SimMan || true
	$(SUDO) rm -rf $(INSTALL_DIR)/$(APP)
	$(SUDO) cp -R build/release/$(APP) $(INSTALL_DIR)/
	@echo "Installed $(INSTALL_DIR)/$(APP)"

clean:
	rm -rf build .build
