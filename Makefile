# Version and build info
VERSION = ALPHA_1.0.1
BUILD_TIME = $(shell date +%Y%m%d_%H%M%S)
ARCH = $(shell uname -m)
GIT_HASH = $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
AUTHOR = vos9.su

# Environment detection
NPROC = $(shell sysctl -n hw.ncpu || echo 2)
OSX_VERSION = $(shell sw_vers -productVersion 2>/dev/null || echo "unknown")

# Compiler and tools
CC = clang
INSTALL = install
RM = rm -rf
STRIP = strip
DSYM = dsymutil
CODESIGN = codesign
PLIST_BUDDY = /usr/libexec/PlistBuddy

# Directories
PREFIX ?= /usr/local
OBJ_DIR = obj
BUILD_DIR = build
DEP_DIR = $(OBJ_DIR)/deps
LOG_DIR = $(BUILD_DIR)/logs
DIST_DIR = dist

# App bundle structure
APP_NAME = Overlay
BUNDLE_NAME = $(APP_NAME).app
BUNDLE_DIR = $(BUILD_DIR)/$(BUILD_TYPE)/$(BUNDLE_NAME)
CONTENTS_DIR = $(BUNDLE_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

# Additional tools
PLUTIL = plutil
ZIP = zip
SECURITY = security

# Base flags with more optimizations
BASE_CFLAGS = -fobjc-arc -x objective-c -Wall -Wextra -Werror \
              -Wno-unused-parameter -fstack-protector-strong \
              -fblocks -fobjc-exceptions \
              -Ofast -flto -march=native -mtune=native \
              -fno-exceptions -fno-rtti \
              -ffast-math -fomit-frame-pointer

# Fix linker flags - add CoreVideo framework
BASE_LDFLAGS = -framework Cocoa -framework IOKit -framework SystemConfiguration -framework CoreVideo \
               -Wl,-no_pie,-bind_at_load,-dead_strip \
               -flto

# Cache settings
CCACHE = $(shell which ccache)
ifneq ($(CCACHE),)
    CC := $(CCACHE) $(CC)
endif

# Architecture specific flags
ifeq ($(ARCH),arm64)
    CFLAGS += -arch arm64 -mtune=apple-m1
else
    CFLAGS += -arch x86_64 -mtune=native
endif

# Profile/Debug/Release configurations
ifdef PROFILE
    CFLAGS = $(BASE_CFLAGS) -O2 -g -DPROFILE -fprofile-instr-generate
    LDFLAGS = $(BASE_LDFLAGS) -fprofile-instr-generate
    BUILD_TYPE = profile
else ifdef DEBUG
    CFLAGS = $(BASE_CFLAGS) -g3 -O0 -DDEBUG -fsanitize=address
    LDFLAGS = $(BASE_LDFLAGS) -fsanitize=address
    BUILD_TYPE = debug
else
    CFLAGS = $(BASE_CFLAGS) -O3 -DNDEBUG -flto
    LDFLAGS = $(BASE_LDFLAGS) -flto
    BUILD_TYPE = release
endif

# Bundle version
BUNDLE_VERSION = $(VERSION).$(BUILD_TIME)
MARKETING_VERSION = $(VERSION)

# Additional build info
DEFINES = -DVERSION=\"$(VERSION)\" \
          -DBUILD_TIME=\"$(BUILD_TIME)\" \
          -DARCH=\"$(ARCH)\" \
          -DGIT_HASH=\"$(GIT_HASH)\" \
          -DOSX_VERSION=\"$(OSX_VERSION)\" \
          -DAPP_NAME=\"$(APP_NAME)\" \
          -DAUTHOR=\"$(AUTHOR)\" \
          -DBUNDLE_VERSION=\"$(BUNDLE_VERSION)\"

# Colors and formatting
CYAN = \033[36m
RED = \033[31m
GREEN = \033[32m
RESET = \033[0m
BOLD = \033[1m

# Sources and objects
SOURCES = main.m OverlayWindowController.m OverlayView.m
OBJECTS = $(SOURCES:%.m=$(OBJ_DIR)/$(BUILD_TYPE)/%.o)
DEPS = $(SOURCES:%.m=$(DEP_DIR)/%.d)
EXECUTABLE = $(BUILD_DIR)/$(BUILD_TYPE)/overlay

# Targets
.PHONY: all clean install uninstall dirs debug release run check help dist distclean \
        profile analyze sign dsym bundle bundle-clean bundle-sign bundle-verify bundle-zip run-bundle

# Default target
.DEFAULT_GOAL := help

# Help target with categories
help:
	@echo "$(BOLD)Overlay Build System $(VERSION) ($(ARCH))$(RESET)"
	@echo "$(BOLD)By $(AUTHOR)$(RESET)"
	@echo "$(BOLD)Build Environment:$(RESET)"
	@echo "  macOS: $(OSX_VERSION)"
	@echo "  Cores: $(NPROC)"
	@echo "  Git:   $(GIT_HASH)"
	@echo "\n$(BOLD)Basic Commands:$(RESET)"
	@echo "  $(CYAN)make$(RESET)        - Show this help"
	@echo "  $(CYAN)make all$(RESET)    - Build release version"
	@echo "  $(CYAN)make run$(RESET)    - Build and run"
	@echo "  $(CYAN)make clean$(RESET)  - Clean build files"
	@echo "\n$(BOLD)Build Variants:$(RESET)"
	@echo "  $(CYAN)make release$(RESET)  - Optimized build"
	@echo "  $(CYAN)make debug$(RESET)    - Debug build with sanitizers"
	@echo "  $(CYAN)make profile$(RESET)  - Build with profiling"
	@echo "\n$(BOLD)Development:$(RESET)"
	@echo "  $(CYAN)make analyze$(RESET)  - Run static analyzer"
	@echo "  $(CYAN)make dsym$(RESET)     - Generate debug symbols"
	@echo "  $(CYAN)make sign$(RESET)     - Sign application"
	@echo "\n$(BOLD)Distribution:$(RESET)"
	@echo "  $(CYAN)make dist$(RESET)     - Create distribution"
	@echo "  $(CYAN)make install$(RESET)  - Install to $(PREFIX)"

# New targets
profile: PROFILE=1
profile: dirs check $(EXECUTABLE)
	@echo "$(GREEN)Profile build complete: $(EXECUTABLE)$(RESET)"

analyze:
	@echo "$(CYAN)Running static analyzer...$(RESET)"
	@$(CC) --analyze $(CFLAGS) $(DEFINES) $(SOURCES)

dsym: $(EXECUTABLE)
	@echo "$(CYAN)Generating debug symbols...$(RESET)"
	@$(DSYM) $(EXECUTABLE)

sign: $(EXECUTABLE)
	@echo "$(CYAN)Signing application...$(RESET)"
	@$(CODESIGN) --force --options runtime --deep -s - $(EXECUTABLE) || \
		(echo "$(RED)Signing failed$(RESET)" && exit 1)
	@echo "$(GREEN)Successfully signed $(notdir $(EXECUTABLE))$(RESET)"

# Enhanced build targets
release: MAKEFLAGS += -j$(NPROC)
release: dirs check $(EXECUTABLE)
	@echo "$(GREEN)Release build complete: $(EXECUTABLE)$(RESET)"
	@echo "Build info: $(VERSION) ($(GIT_HASH)) for $(ARCH)"

debug: MAKEFLAGS += -j$(NPROC)
debug: DEBUG=1
debug: dirs check $(EXECUTABLE)
	@echo "$(GREEN)Debug build complete: $(EXECUTABLE)$(RESET)"

# Directory creation
dirs:
	@mkdir -p $(OBJ_DIR)/$(BUILD_TYPE) $(BUILD_DIR)/$(BUILD_TYPE) $(DEP_DIR) $(LOG_DIR) $(DIST_DIR)

# Enhanced check target
check:
	@echo "$(CYAN)Checking build environment...$(RESET)"
	@echo "  macOS:    $(OSX_VERSION)"
	@echo "  Arch:     $(ARCH)"
	@echo "  Cores:    $(NPROC)"
	@echo "  Compiler: $(shell $(CC) --version | head -n1)"
	@echo "  Git:      $(GIT_HASH)"
	@which $(CC) >/dev/null 2>&1 || (echo "$(RED)Error: $(CC) not found$(RESET)" && exit 1)
	@echo "$(GREEN)Environment OK$(RESET)"

# Compilation and linking
$(EXECUTABLE): $(OBJECTS)
	@echo "$(CYAN)Linking $@$(RESET)"
	@$(CC) $(OBJECTS) $(LDFLAGS) -o $@ || (echo "$(RED)Link failed$(RESET)" && exit 1)
	@echo "$(GREEN)Successfully built $(notdir $@)$(RESET)"

$(OBJ_DIR)/$(BUILD_TYPE)/%.o: %.m
	@printf "$(CYAN)Compiling %-30s$(RESET)" "$<"
	@$(CC) $(CFLAGS) $(DEFINES) -MMD -MP -MF $(DEP_DIR)/$*.d -c $< -o $@ 2>$(LOG_DIR)/$*.log || \
		(echo "$(RED)Failed$(RESET)" && cat $(LOG_DIR)/$*.log && exit 1)
	@echo "$(GREEN)OK$(RESET)"

# Installation
install: bundle
	@echo "$(CYAN)Installing application bundle...$(RESET)"
	@$(RM) "/Applications/$(BUNDLE_NAME)"
	@cp -R $(BUNDLE_DIR) "/Applications/"
	@echo "$(GREEN)Installation complete$(RESET)"

uninstall:
	@echo "$(CYAN)Uninstalling from $(PREFIX)/bin$(RESET)"
	@$(RM) $(PREFIX)/bin/overlay
	@echo "$(GREEN)Uninstallation complete$(RESET)"

# Running
run: release
	@echo "$(CYAN)Running application...$(RESET)"
	@$(EXECUTABLE)

run-bundle: bundle
	@echo "$(CYAN)Running application bundle...$(RESET)"
	@open $(BUNDLE_DIR)

# Cleaning
clean: bundle-clean
	@echo "$(CYAN)Cleaning build files...$(RESET)"
	@$(RM) $(OBJ_DIR) $(BUILD_DIR)
	@echo "$(GREEN)Clean complete$(RESET)"

dist: bundle-zip
	@echo "$(CYAN)Creating distribution package...$(RESET)"
	@mkdir -p $(DIST_DIR)
	@cp $(EXECUTABLE) $(DIST_DIR)/
	@$(STRIP) $(DIST_DIR)/$(notdir $(EXECUTABLE))
	@tar czf $(DIST_DIR)/overlay-$(VERSION)-$(ARCH).tar.gz -C $(DIST_DIR) $(notdir $(EXECUTABLE))
	@echo "$(GREEN)Distribution package created in $(DIST_DIR)$(RESET)"

distclean: clean
	@echo "$(CYAN)Removing distribution files...$(RESET)"
	@$(RM) $(DIST_DIR)
	@echo "$(GREEN)All generated files removed$(RESET)"

# Bundle targets
bundle: $(EXECUTABLE)
	@echo "$(CYAN)Creating application bundle...$(RESET)"
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	@cp $(EXECUTABLE) $(MACOS_DIR)/$(APP_NAME)
	@echo "$(CYAN)Generating Info.plist...$(RESET)"
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $(CONTENTS_DIR)/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(CONTENTS_DIR)/Info.plist
	@echo '<plist version="1.0">' >> $(CONTENTS_DIR)/Info.plist
	@echo '<dict>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleExecutable</key><string>$(APP_NAME)</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleIdentifier</key><string>com.vos9.$(APP_NAME)</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleName</key><string>$(APP_NAME)</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundlePackageType</key><string>APPL</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>CFBundleVersion</key><string>$(BUNDLE_VERSION)</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>LSMinimumSystemVersion</key><string>10.10.0</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>LSUIElement</key><true/>' >> $(CONTENTS_DIR)/Info.plist
	@echo '    <key>NSHumanReadableCopyright</key><string>Copyright © $(shell date +%Y) $(AUTHOR)</string>' >> $(CONTENTS_DIR)/Info.plist
	@echo '</dict>' >> $(CONTENTS_DIR)/Info.plist
	@echo '</plist>' >> $(CONTENTS_DIR)/Info.plist
	@$(PLUTIL) -convert binary1 $(CONTENTS_DIR)/Info.plist
	@echo "$(GREEN)Bundle created: $(BUNDLE_DIR)$(RESET)"

bundle-sign: bundle
	@echo "$(CYAN)Signing application bundle...$(RESET)"
	@$(CODESIGN) --force --options runtime --deep -s - $(BUNDLE_DIR) 2>/dev/null || \
		(echo "$(RED)Bundle signing failed$(RESET)" && exit 1)
	@echo "$(GREEN)Bundle signed$(RESET)"

bundle-verify:
	@echo "$(CYAN)Verifying bundle signature...$(RESET)"
	@$(CODESIGN) --verify --verbose $(BUNDLE_DIR)
	@echo "$(GREEN)Bundle verification complete$(RESET)"

bundle-zip: bundle-sign bundle-verify
	@echo "$(CYAN)Creating ZIP archive...$(RESET)"
	@cd $(BUILD_DIR)/$(BUILD_TYPE) && $(ZIP) -r9 ../$(APP_NAME)-$(VERSION)-$(ARCH).zip $(BUNDLE_NAME)
	@echo "$(GREEN)ZIP archive created$(RESET)"

bundle-clean:
	@echo "$(CYAN)Cleaning bundle...$(RESET)"
	@$(RM) $(BUNDLE_DIR)
	@echo "$(GREEN)Bundle cleaned$(RESET)"

# Include dependencies
-include $(DEPS)
