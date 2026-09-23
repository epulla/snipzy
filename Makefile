APP_NAME := Snipzy
BUNDLE_SCRIPT := scripts/bundle.sh
# Command Line Tools ship Swift Testing but SwiftPM does not add its search path.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := $(if $(wildcard $(CLT_DEV)/Frameworks/Testing.framework),-Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib)

.PHONY: build release test bundle run clean

build:
	swift build --product $(APP_NAME)

release:
	swift build -c release --product $(APP_NAME)

test:
	swift test $(TEST_FLAGS)

bundle:
	$(BUNDLE_SCRIPT)

run:
	swift run --product $(APP_NAME)

clean:
	swift package clean
