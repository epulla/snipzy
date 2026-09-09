APP_NAME := Snipzy
BUNDLE_SCRIPT := scripts/bundle.sh

.PHONY: build release test bundle run clean

build:
	swift build --product $(APP_NAME)

release:
	swift build -c release --product $(APP_NAME)

test:
	swift test

bundle:
	$(BUNDLE_SCRIPT)

run:
	swift run --product $(APP_NAME)

clean:
	swift package clean
