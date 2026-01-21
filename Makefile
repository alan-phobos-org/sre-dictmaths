# Makefile for sre-dictmaths PoC
# Builds on macOS with support for multiple macOS versions

CC = clang
OBJCFLAGS = -fobjc-arc -fmodules -Wall -Wextra
FRAMEWORKS = -framework Foundation

# Support both newer and older macOS versions
# Minimum deployment target set to macOS 10.13 for broad compatibility
MACOS_MIN_VERSION = 10.13
DEPLOYMENT_FLAGS = -mmacosx-version-min=$(MACOS_MIN_VERSION)

# Architecture flags - build universal binary for Apple Silicon and Intel
# On macOS 11+, can build universal; on older systems, build for host arch
ARCH_FLAGS = -arch arm64 -arch x86_64

# Detect if building on older macOS that doesn't support universal binaries
MACOS_VERSION := $(shell sw_vers -productVersion 2>/dev/null | cut -d '.' -f 1)
ifeq ($(shell test $(MACOS_VERSION) -lt 11; echo $$?),0)
    # On macOS < 11, build for host architecture only
    ARCH_FLAGS = -arch $(shell uname -m)
endif

# Combine all flags
CFLAGS = $(OBJCFLAGS) $(DEPLOYMENT_FLAGS) $(ARCH_FLAGS)
LDFLAGS = $(FRAMEWORKS)

# Source files
SRC_DIR = src
SOURCES = $(SRC_DIR)/leak-slide.m \
          $(SRC_DIR)/diagnostics.m \
          $(SRC_DIR)/hash-utils.m \
          $(SRC_DIR)/dict-builder.m \
          $(SRC_DIR)/crt-solver.m

# Output
TARGET = leak-slide

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(SOURCES)
	@echo "Building $(TARGET)..."
	@echo "Target macOS version: $(MACOS_MIN_VERSION)+"
	@echo "Architecture: $(ARCH_FLAGS)"
	$(CC) $(CFLAGS) $(SOURCES) $(LDFLAGS) -o $(TARGET)
	@echo "Build complete: ./$(TARGET)"

clean:
	rm -f $(TARGET)
	@echo "Cleaned build artifacts"

# Run the PoC
run: $(TARGET)
	./$(TARGET)

# Check build environment
check:
	@echo "Checking build environment..."
	@echo "Compiler: $(CC)"
	@$(CC) --version
	@echo ""
	@echo "macOS version: $(shell sw_vers -productVersion 2>/dev/null || echo 'unknown')"
	@echo "Architecture: $(shell uname -m)"
	@echo "Xcode command line tools: $(shell xcode-select -p 2>/dev/null || echo 'NOT INSTALLED')"

help:
	@echo "sre-dictmaths - NSDictionary Pointer Leak PoC"
	@echo ""
	@echo "Targets:"
	@echo "  make          - Build the leak-slide binary"
	@echo "  make run      - Build and run the PoC"
	@echo "  make clean    - Remove build artifacts"
	@echo "  make check    - Check build environment"
	@echo "  make help     - Show this help message"
	@echo ""
	@echo "Requirements:"
	@echo "  - macOS $(MACOS_MIN_VERSION) or later"
	@echo "  - Xcode command line tools (xcode-select --install)"
	@echo "  - clang compiler with Objective-C support"
