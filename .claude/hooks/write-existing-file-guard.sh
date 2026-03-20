#!/bin/bash
# PreToolUse hook: Blocks Write tool from overwriting existing files.
# Forces use of Edit tool instead to prevent accidental full-file overwrites.

# Read tool input from stdin
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only check Write tool, not Edit
if [ "$TOOL_NAME" != "Write" ]; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# If the file already exists, block Write and suggest Edit
if [ -f "$FILE_PATH" ]; then
  echo '{"decision": "block", "reason": "File already exists. Use the Edit tool instead of Write to modify existing files. Write tool should only be used to create NEW files."}'
  exit 0
fi

# New file — allow
exit 0
