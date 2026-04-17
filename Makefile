EXECUTABLE_NAME := del-is-archive
APP_NAME := Del is Archive
APP_BUNDLE := .build/release/$(APP_NAME).app
APP_ICON := Support/del-is-archive.icns
ICONSET := .build/del-is-archive.iconset
DIST_DIR := dist
ZIP_PATH := $(DIST_DIR)/del-is-archive.zip
INSTALL_DIR ?= /Applications

.PHONY: build run icon app install uninstall zip clean

build:
	swift build -c release

run: build
	.build/release/$(EXECUTABLE_NAME)

icon:
	swift Support/GenerateIcon.swift "$(ICONSET)"
	iconutil -c icns "$(ICONSET)" -o "$(APP_ICON)"

app: build icon
	install -d "$(APP_BUNDLE)/Contents/MacOS"
	install -d "$(APP_BUNDLE)/Contents/Resources"
	cp ".build/release/$(EXECUTABLE_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(EXECUTABLE_NAME)"
	cp "Support/Info.plist" "$(APP_BUNDLE)/Contents/Info.plist"
	cp "$(APP_ICON)" "$(APP_BUNDLE)/Contents/Resources/del-is-archive.icns"

install: app
	install -d "$(INSTALL_DIR)"
	ditto "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"

uninstall:
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"

zip: app
	rm -rf "$(DIST_DIR)"
	install -d "$(DIST_DIR)"
	ditto -c -k --keepParent "$(APP_BUNDLE)" "$(ZIP_PATH)"

clean:
	swift package clean
	rm -rf "$(DIST_DIR)" "$(ICONSET)" "$(APP_ICON)"
