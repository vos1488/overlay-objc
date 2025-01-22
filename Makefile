# Version and build info
VERSION = ALPHA_1.0.2
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

# Enhanced colors and formatting
CYAN    := \033[36m
RED     := \033[31m
GREEN   := \033[32m
YELLOW  := \033[33m
BLUE    := \033[34m
MAGENTA := \033[35m
RESET   := \033[0m
BOLD    := \033[1m
DIM     := \033[2m
ITALIC  := \033[3m
LINE    := \033[4m

# Unicode symbols
ARROW   := →
CHECK   := ✓
CROSS   := ✗
STAR    := ★
WARN    := ⚠
BUILD   := 🔨
CLEAN   := 🧹
RUN     := 🚀
BOOK    := 📖
GEAR    := ⚙️
PACK    := 📦
LOCK    := 🔒

# Enhanced visual elements
PURPLE  := \033[35;1m
WHITE   := \033[37;1m
BG_BLUE := \033[44m
FRAME   := \033[51m
BLINK   := \033[5m
INVERT  := \033[7m

# Additional Unicode symbols
ROCKET  := 🚀
SPARKLE := ✨
TOOLS   := 🛠️
INFO    := ℹ️
OK      := ✅
ERROR   := ❌
DEBUG   := 🔍
COG     := ⚙️
CLOCK   := 🕒
DEPLOY  := 📦
TRASH   := 🗑️

# Additional visual elements
BG_BLACK  := \033[40m
BG_RED    := \033[41m
BG_GREEN  := \033[42m
BG_YELLOW := \033[43m
UNDERLINE := \033[4m
BLINK_HI  := \033[6m
INVERSE   := \033[7m

# More Unicode symbols
DIAMOND   := 💎
COMPUTER  := 💻
WRENCH    := 🔧
PACKAGE   := 📦
LINK      := 🔗
MAGIC     := ✨
TARGET    := 🎯
SHIELD    := 🛡️
LIGHT     := 💡
SPEED     := ⚡️

# Additional visual styles
BG_GRADIENT := \033[48;5;
FG_GRADIENT := \033[38;5;
FLASH      := \033[5;1m
RAINBOW    := \033[38;5;%(i)dm

# More UI symbols
LOADING    := ⏳
SUCCESS    := 🎉
FAILED     := 💔
WORKING    := 🔄
DONE       := ✨
BUILDING   := 🏗️
CLEANING   := 🧹
TESTING    := 🧪
CONFIG     := ⚙️
ROCKET     := 🚀

# Fancy separator
define separator
	@echo "$(BLUE)▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃$(RESET)"
endef

# Enhanced box drawing
define draw_box
	@echo "$(BOLD)╭───────────────────────────────────────────╮"
	@echo "$(BOLD)│ $(PURPLE)$(1)$(RESET)$(BOLD)                      │$(RESET)"
	@echo "$(BOLD)╰─$(LINE)─────────────────────────────────────────$(RESET)─╯"
endef

# Progress spinner
define show_progress
	@echo -n "$(CYAN)$(BLINK)⠋$(RESET) $(1)"
	@sleep 0.1
	@echo -ne "\r$(CYAN)⠙$(RESET) $(1)"
	@sleep 0.1
	@echo -ne "\r$(CYAN)⠹$(RESET) $(1)"
	@sleep 0.1
	@echo -ne "\r$(CYAN)⠸$(RESET) $(1)"
	@sleep 0.1
	@echo -ne "\r$(CYAN)⠼$(RESET) $(1)"
	@sleep 0.1
	@echo -ne "\r$(CYAN)⠴$(RESET) $(1)"
	@sleep 0.1
	@echo -ne "\r$(CYAN)⠦$(RESET) $(1)"
	@sleep 0.1
	@echo -ne "\r$(CYAN)⠧$(RESET) $(1)"
	@sleep 0.1
	@echo -ne "\r$(CYAN)⠇$(RESET) $(1)"
	@sleep 0.1
	@echo -ne "\r$(CYAN)⠏$(RESET) $(1)\n"
endef

# Improved double box style
define double_box
	@echo "$(BOLD)╔══$(CYAN)$(1)══╗$(RESET)"
	@echo "$(BOLD)║$(RESET)  $(BLUE)$(2)$(RESET)  $(BOLD)║$(RESET)"
	@echo "$(BOLD)╚═════════════════════════╝$(RESET)"
endef

# Enhanced progress bar
define progress_bar
	@echo -n "$(CYAN)["
	@for i in $(shell seq 1 25); do \
		sleep 0.02; \
		echo -n "▓"; \
	done
	@echo "] $(1)$(RESET)"
endef

# Fancy section divider
define section_divider
	@echo "$(BLUE)"
	@echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
	@echo "┃  $(WHITE)$(1)$(BLUE)  ┃"
	@echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
	@echo "$(RESET)"
endef

# Build status indicator
define status_indicator
	@echo "$(BG_BLUE)$(WHITE) $(1) $(RESET) $(2)"
endef

# Header template
define print_header
	@echo "$(BOLD)┌─────────────────────────────────────────────────┐$(RESET)"
	@echo "$(BOLD)│       $(BLUE)Overlay Build System $(VERSION)$(RESET)$(BOLD)        │$(RESET)"
	@echo "$(BOLD)│             $(MAGENTA)Created by $(AUTHOR)$(RESET)$(BOLD)              │$(RESET)"
	@echo "$(BOLD)└─────────────────────────────────────────────────┘$(RESET)"
endef

# Section header template
define print_section
	@echo "$(BLUE)══════════════ $(1) ══════════════$(RESET)"
endef

# Enhanced box styles
define fancy_box
	@echo "$(BOLD)╭───━━━━━━━━━━$(1)━━━━━━━━━━───╮$(RESET)"
	@echo "$(BOLD)│     $(FLASH)$(2)$(RESET)$(BOLD)          │$(RESET)"
	@echo "$(BOLD)╰───━━━━━━━━━━━━━━━━━━━━━───╯$(RESET)"
endef

# Animated building indicator
define build_animation
	@echo -n "$(BUILDING) Building $(1) "
	@for i in 1 2 3; do \
		echo -n "." && sleep 0.2; \
	done
	@echo ""
endef

# Rainbow text effect
define rainbow_print
	@for i in {1..6}; do \
		printf "$(RAINBOW)" $$i; \
		echo -n "$(1)"; \
		printf "$(RESET)"; \
	done
	@echo ""
endef

# Enhanced progress bar with percentage
define progress_bar_pct
	@echo -n "$(CYAN)[" 
	@for i in $(shell seq 1 $(2)); do \
		if [ $$i -le $$(($(1)*$(2)/100)) ]; then \
			echo -n "█"; \
		else \
			echo -n "░"; \
		fi \
	done
	@echo "] $(1)%$(RESET)"
endef

# Status message with icon
define status_msg
	@echo "$(1) $(BOLD)$(2)$(RESET) $(DIM)$(3)$(RESET)"
endef

# Box drawing with dynamic width
define box_with_title
	@echo "$(BOLD)╔══$(CYAN)$(1)$(BOLD)══╗$(RESET)"
	@echo "$(BOLD)║  $(BLUE)$(2)$(BOLD)  ║$(RESET)"
	@echo "$(BOLD)╚════════════════════════════╝$(RESET)"
endef

# Enhanced status bar
define status_bar
	@printf "$(CYAN)[" 
	@for i in $(shell seq 1 40); do \
		if [ $$i -le $$(($(1)*40/100)) ]; then \
			printf "▰"; \
		else \
			printf "▱"; \
		fi; \
	done
	@printf "] %3d%%$(RESET)\n" "$(1)"
endef

# Animated spinner with message
define spinner
	@printf "$(CYAN)⠋$(RESET) $(1)"
	@for i in {1..3}; do \
		for c in ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏; do \
			printf "\r$(CYAN)$$c$(RESET) $(1)"; \
			sleep 0.1; \
		done; \
	done
	@printf "\r$(GREEN)✓$(RESET) $(1)\n"
endef

# Sources and objects
SOURCES = main.m OverlayWindowController.m OverlayView.m
OBJECTS = $(SOURCES:%.m=$(OBJ_DIR)/$(BUILD_TYPE)/%.o)
DEPS = $(SOURCES:%.m=$(DEP_DIR)/%.d)
EXECUTABLE = $(BUILD_DIR)/$(BUILD_TYPE)/overlay

# Resource files
RESOURCE_FILES = icon.png

# Targets
.PHONY: all clean install uninstall dirs debug release run check help dist distclean \
        profile analyze sign dsym bundle bundle-clean bundle-sign bundle-verify bundle-zip run-bundle

# Default target
.DEFAULT_GOAL := help

# Enhanced help target
help:
	$(call box_with_title,"OVERLAY","Build System $(VERSION)")
	@echo ""
	$(call section_divider,"$(COMPUTER) System Information")
	$(call status_indicator,"OS","macOS $(OSX_VERSION)")
	$(call status_indicator,"CPU","$(ARCH) with $(NPROC) cores")
	$(call status_indicator,"GIT","$(GIT_HASH)")
	@echo ""
	$(call section_divider,"$(WRENCH) Build Commands")
	$(call box_with_title,"BUILD","make all     - Full Release Build")
	$(call box_with_title,"DEBUG","make debug   - Debug Build")
	$(call box_with_title,"PROF", "make profile - Profile Build")
	@echo "$(BG_BLUE)$(WHITE)"
	@echo "    ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄    "
	@echo "    █  $(RESET)$(BOLD)Overlay Build System$(BG_BLUE)$(WHITE)  █    "
	@echo "    █   Version $(VERSION)  █    "
	@echo "    ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀    "
	@echo "$(RESET)"
	$(call section_divider,"$(DIAMOND) Overlay Build System $(VERSION) ")
	@echo "$(BG_BLUE)$(WHITE)"
	@echo "     ▒█████   ██▒   █▓▓█████  ██▀███   ██▓    ▄▄▄     ▓██   ██▓"
	@echo "    ▒██▒  ██▒▓██░   █▒▓█   ▀ ▓██ ▒ ██▒▓██▒   ▒████▄    ▒██  ██▒"
	@echo "    ▒██░  ██▒ ▓██  █▒░▒███   ▓██ ░▄█ ▒▒██░   ▒██  ▀█▄   ▒██ ██░"
	@echo "    ▒██   ██░  ▒██ █░░▒▓█  ▄ ▒██▀▀█▄  ▒██░   ░██▄▄▄▄██  ░ ▐██▓░"
	@echo "    ░ ████▓▒░   ▒▀█░  ░▒████▒░██▓ ▒██▒░██████▒▓█   ▓██▒ ░ ██▒▓░"
	@echo "    ░ ▒░▒░▒░    ░ ▐░  ░░ ▒░ ░░ ▒▓ ░▒▓░░ ▒░▓  ░▒▒   ▓▒█░  ██▒▒▒ "
	@echo "      ░ ▒ ▒░    ░ ░░   ░ ░  ░  ░▒ ░ ▒░░ ░ ▒  ░ ▒   ▒▒ ░▓██ ░▒░ "
	@echo "$(RESET)"
	$(call separator)
	
	$(call section_divider,"$(COMPUTER) System Information")
	$(call status_indicator,"SYS","macOS $(OSX_VERSION) on $(ARCH)")
	$(call status_indicator,"CPU","$(NPROC) cores available")
	$(call status_indicator,"GIT","$(GIT_HASH)")
	
	$(call section_divider,"$(WRENCH) Build Commands")
	$(call double_box,"BUILD","make all     - Full Release Build")
	$(call double_box,"DEBUG","make debug   - Debug Build")
	$(call double_box,"PROF ","make profile - Profile Build")
	
	@echo ""
	$(call draw_box,"$(COG) System Information")
	@echo "  $(CYAN)•$(RESET) OS:     $(BOLD)macOS $(OSX_VERSION)$(RESET)"
	@echo "  $(CYAN)•$(RESET) CPU:    $(BOLD)$(ARCH)$(RESET)"
	@echo "  $(CYAN)•$(RESET) Cores:  $(BOLD)$(NPROC)$(RESET)"
	@echo "  $(CYAN)•$(RESET) Git:    $(BOLD)$(GIT_HASH)$(RESET)"
	@echo ""
	$(call draw_box,"$(ROCKET) Build Commands")
	@echo "  $(CYAN)make$(RESET)        $(DIM)Show this help message$(RESET)"
	@echo "  $(CYAN)make all$(RESET)    $(DIM)Build complete release version$(RESET)"
	@echo "  $(CYAN)make release$(RESET)$(DIM) Build optimized version$(RESET)"
	@echo "  $(CYAN)make debug$(RESET)  $(DIM)Build with debug symbols$(RESET)"
	@echo ""
	$(call print_section,$(GEAR) Development Tools)
	@echo "  $(CYAN)make analyze$(RESET)      $(DIM)Run static code analyzer$(RESET)"
	@echo "  $(CYAN)make dsym$(RESET)         $(DIM)Generate debug symbols$(RESET)"
	@echo "  $(CYAN)make check$(RESET)        $(DIM)Verify build environment$(RESET)"
	@echo ""
	$(call print_section,$(PACK) Distribution)
	@echo "  $(CYAN)make bundle$(RESET)       $(DIM)Create application bundle$(RESET)"
	@echo "  $(CYAN)make sign$(RESET)         $(DIM)Sign application bundle$(RESET)"
	@echo "  $(CYAN)make dist$(RESET)         $(DIM)Create distribution package$(RESET)"
	@echo ""
	$(call print_section,$(RUN) Testing)
	@echo "  $(CYAN)make run$(RESET)          $(DIM)Build and run application$(RESET)"
	@echo "  $(CYAN)make run-bundle$(RESET)   $(DIM)Run application bundle$(RESET)"
	@echo ""
	$(call print_section,$(WARN) Options)
	@echo "  $(YELLOW)DEBUG=1$(RESET)           Enable debug build"
	@echo "  $(YELLOW)PROFILE=1$(RESET)        Enable profiling build"
	@echo "  $(YELLOW)PREFIX=/path$(RESET)     Set installation prefix"
	@echo ""
	@echo "$(DIM)For more information, visit: https://github.com/vos9/overlay-objc$(RESET)"

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
release: dirs check
	@echo "$(CYAN)Building release version...$(RESET)"
	$(call status_bar,25)
	@$(MAKE) $(EXECUTABLE)
	$(call status_bar,50)
	@echo "$(CYAN)Creating application bundle...$(RESET)"
	@$(MAKE) bundle
	$(call status_bar,100)
	@echo "$(GREEN)Release build complete$(RESET)"

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

# Enhanced cleaning targets
.PHONY: clean clean-all clean-deps clean-logs clean-dist clean-bundles clean-dsym clean-cache

clean: clean-all
	@echo "$(GREEN)All clean targets completed successfully$(RESET)"

clean-all: clean-deps clean-logs clean-dist clean-bundles clean-dsym clean-cache
	$(call spinner,"Cleaning build directories...")
	@$(RM) $(OBJ_DIR) $(BUILD_DIR)
	$(call box_with_title,"CLEAN","All build artifacts removed")

clean-deps:
	@echo "$(CYAN)Cleaning dependency files...$(RESET)"
	@$(RM) $(DEP_DIR)
	@find . -name "*.d" -type f -delete
	@echo "$(GREEN)Dependencies cleaned$(RESET)"

clean-logs:
	@echo "$(CYAN)Cleaning log files...$(RESET)"
	@$(RM) $(LOG_DIR)
	@find . -name "*.log" -type f -delete
	@echo "$(GREEN)Logs cleaned$(RESET)"

clean-dist:
	@echo "$(CYAN)Cleaning distribution files...$(RESET)"
	@$(RM) $(DIST_DIR)
	@find . -name "*.zip" -type f -delete
	@find . -name "*.tar.gz" -type f -delete
	@echo "$(GREEN)Distribution files cleaned$(RESET)"

clean-bundles:
	@echo "$(CYAN)Cleaning application bundles...$(RESET)"
	@$(RM) $(BUILD_DIR)/$(BUILD_TYPE)/$(BUNDLE_NAME)
	@find . -name "*.app" -type d -exec rm -rf {} +
	@echo "$(GREEN)Application bundles cleaned$(RESET)"

clean-dsym:
	@echo "$(CYAN)Cleaning debug symbols...$(RESET)"
	@find . -name "*.dSYM" -type d -exec rm -rf {} +
	@echo "$(GREEN)Debug symbols cleaned$(RESET)"

clean-cache:
	@echo "$(CYAN)Cleaning cache files...$(RESET)"
	@find . -name ".DS_Store" -type f -delete
	@find . -name "*.swp" -type f -delete
	@find . -name "*~" -type f -delete
	@if [ -n "$(CCACHE)" ]; then \
		$(CCACHE) -C; \
		echo "$(GREEN)Compiler cache cleaned$(RESET)"; \
	fi
	@echo "$(GREEN)Cache files cleaned$(RESET)"

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
	$(call fancy_box,"BUNDLE","Creating application bundle")
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	@cp $(EXECUTABLE) $(MACOS_DIR)/$(APP_NAME)
	@cp icon.png $(RESOURCES_DIR)/
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
	@echo '    <key>CFBundleIconFile</key><string>icon</string>' >> $(CONTENTS_DIR)/Info.plist
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

# Add new convenience targets
.PHONY: doctor info version update-icons

doctor: ## Run system checks
	$(call fancy_box,"DOCTOR","Running system diagnostics")
	$(call status_msg,$(CONFIG),"Checking system configuration","")
	@echo "$(CYAN)System Information:$(RESET)"
	@system_profiler SPSoftwareDataType SPHardwareDataType 2>/dev/null | grep -E "System Version:|Memory:" || echo "Unable to get system info"
	
	@echo "\n$(CYAN)Development Tools:$(RESET)"
	@if [ -d "/Applications/Xcode.app" ]; then \
		echo "$(GREEN)✓ Xcode:$(RESET)     $$(xcodebuild -version 2>/dev/null || echo 'Not installed')"; \
	else \
		echo "$(YELLOW)⚠ Xcode:$(RESET)     Not installed (using Command Line Tools)"; \
	fi
	
	@echo "$(GREEN)✓ CLTools:$(RESET)   $$(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | grep -i version: | cut -d: -f2 || echo 'Not found')"
	@echo "$(GREEN)✓ Clang:$(RESET)     $$($(CC) --version | head -n1)"
	@echo "$(GREEN)✓ Make:$(RESET)      $$($(MAKE) --version | head -n1)"
	
	@echo "\n$(CYAN)Build Environment:$(RESET)"
	@echo "$(GREEN)✓ Architecture:$(RESET) $(ARCH)"
	@echo "$(GREEN)✓ Cores:$(RESET)       $(NPROC)"
	@echo "$(GREEN)✓ Git Hash:$(RESET)    $(GIT_HASH)"
	
	@if [ ! -d "/Applications/Xcode.app" ]; then \
		echo "\n$(YELLOW)Note:$(RESET) Building with Command Line Tools only"; \
		echo "      This is sufficient for building the project."; \
	fi
	
	$(call status_msg,$(DONE),"Diagnostics complete","Environment checked")
	@exit 0

info: ## Show build information
	$(call fancy_box,"INFO","Build Configuration")
	@echo "$(BOLD)Version:$(RESET)    $(VERSION)"
	@echo "$(BOLD)Build:$(RESET)      $(BUILD_TIME)"
	@echo "$(BOLD)Arch:$(RESET)       $(ARCH)"
	@echo "$(BOLD)Compiler:$(RESET)   $(shell $(CC) --version | head -n1)"
	@echo "$(BOLD)SDK:$(RESET)        $(shell xcrun --show-sdk-path)"

version: ## Show version
	@echo "$(BOLD)$(APP_NAME) $(VERSION)$(RESET)"
	@echo "$(DIM)Build $(BUILD_TIME) for $(ARCH)$(RESET)"

update-icons: ## Update application icons
	$(call status_msg,$(WORKING),"Updating icons","")
	@mkdir -p $(RESOURCES_DIR)
	@for size in 16 32 64 128 256 512 1024; do \
		sips -z $$size $$size icon.png --out $(RESOURCES_DIR)/icon_$${size}x$${size}.png; \
	done
	$(call status_msg,$(DONE),"Icons updated","")

# Include dependencies
-include $(DEPS)