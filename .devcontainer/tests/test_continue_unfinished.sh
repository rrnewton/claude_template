#!/bin/bash
# E2E test for --continue-unfinished feature
# Tests that a trivial completed task moves on to the next iteration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOGO_SCRIPT="$SCRIPT_DIR/../gogo_claude.py"
TEMP_PROMPT=$(mktemp)

# Cleanup on exit
cleanup() {
    rm -f "$TEMP_PROMPT"
}
trap cleanup EXIT

# Create a trivial prompt that should be considered "complete" after one run
echo 'Say "Hello world" and nothing else.' > "$TEMP_PROMPT"

echo "=== E2E Test: --continue-unfinished with trivial complete task ==="
echo "Prompt: $(cat "$TEMP_PROMPT")"
echo ""

# Run with --continue-unfinished and 2 iterations
# Capture output to check behavior
OUTPUT=$(python3 "$GOGO_SCRIPT" --constant-prompt "$TEMP_PROMPT" --continue-unfinished 2 2>&1)

echo "$OUTPUT"
echo ""

# Verify expected behavior:
# 1. Should show "Task complete: True" after checking
# 2. Should complete both iterations (not continue the first one)

if echo "$OUTPUT" | grep -q "Task complete: True"; then
    echo "✓ PASS: Task was correctly identified as complete"
else
    echo "✗ FAIL: Expected 'Task complete: True' in output"
    exit 1
fi

if echo "$OUTPUT" | grep -q "Successfully completed all 2 iterations"; then
    echo "✓ PASS: Both iterations completed successfully"
else
    echo "✗ FAIL: Expected successful completion of 2 iterations"
    exit 1
fi

# Check that iteration 2 used a fresh prompt (not continuation)
if echo "$OUTPUT" | grep -q "Using constant prompt.*for iteration 2"; then
    echo "✓ PASS: Iteration 2 started with fresh prompt (not continuation)"
else
    echo "✗ FAIL: Expected iteration 2 to use fresh prompt"
    exit 1
fi

echo ""
echo "=== All tests passed ==="
