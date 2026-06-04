APP_NAME=OKXMenuBar
REPO_NAME=okx-menubar
CONFIG=release
VERSION?=v0.1.0
BUNDLE=.build/$(APP_NAME).app
BINARY=.build/$(CONFIG)/$(APP_NAME)
DIST=dist
DMG=$(DIST)/$(REPO_NAME)-$(VERSION)-macos.dmg

.PHONY: run build app dmg clean

run:
	swift run $(APP_NAME)

build:
	swift build -c $(CONFIG)

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	@echo "Built $(BUNDLE)"

dmg: app
	./scripts/build-dmg.sh "$(BUNDLE)" "$(DMG)" "$(APP_NAME)"

clean:
	rm -rf .build $(DIST)
