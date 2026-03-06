CC = clang
CFLAGS = -O2 -Wall -Wextra -Wno-unused-parameter
FRAMEWORKS = -framework ApplicationServices -framework Cocoa
INCLUDES = -Isrc

BIN_DIR = bin
TARGET = $(BIN_DIR)/McWinning
TEST_TARGET = $(BIN_DIR)/TestSuite

.PHONY: all clean test

all: $(TARGET)

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

$(TARGET): src/McWinning.m | $(BIN_DIR)
	$(CC) $(CFLAGS) $(FRAMEWORKS) $< -o $@

test: $(TEST_TARGET)
	./$(TEST_TARGET)

$(TEST_TARGET): tests/TestSuite.m src/McWinning.m | $(BIN_DIR)
	$(CC) $(CFLAGS) $(FRAMEWORKS) $(INCLUDES) $< -o $@

clean:
	rm -rf $(BIN_DIR)
