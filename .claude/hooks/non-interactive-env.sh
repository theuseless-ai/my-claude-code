#!/bin/bash
# PreToolUse hook: Blocks interactive shell commands that would hang.
# Prevents vim, nano, less, ssh (without batch mode), and other TUI apps.

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# List of interactive commands that would hang
BLOCKED_CMDS="^(vim|nvim|vi|nano|emacs|less|more|htop|top|ssh|telnet|ftp|mysql|psql|mongosh|redis-cli|irb|pry|ipython|python3?[[:space:]]*$)"

if echo "$COMMAND" | grep -qE "$BLOCKED_CMDS"; then
  echo "{\"decision\": \"block\", \"reason\": \"Blocked interactive command. This environment does not support TUI/interactive applications. Use non-interactive alternatives (e.g., 'cat' instead of 'less', CLI flags like 'mysql -e' instead of interactive mysql).\"}"
  exit 0
fi

exit 0
