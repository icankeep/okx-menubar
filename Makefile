APP_NAME=OKXMenuBar
CONFIG=release
BUNDLE=.build/$(APP_NAME).app
BINARY=.build/$(CONFIG)/$(APP_NAME)

.PHONY: run build app clean

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

clean:
	rm -rf .build
