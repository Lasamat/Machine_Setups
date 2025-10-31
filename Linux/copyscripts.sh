#!/bin/bash

SOURCE="./scripts"
DESTINATION="$HOME/.local"

# Check if source exists
if [ ! -d "$SOURCE" ]; then
  echo "Error: Source folder '$SOURCE' does not exist." >&2
  exit 1
fi

# Check if destination is writable
if [ ! -w "$HOME" ]; then
  echo "Error: No write permission in the home directory." >&2
  exit 1
fi

# Copy the folder, overwriting existing files
if cp -r -f "$SOURCE" "$DESTINATION"/; then
  echo "Folder copied to $DESTINATION, overwriting existing files."
else
  echo "Error: Failed to copy folder from $SOURCE to $DESTINATION." >&2
  exit 1
fi
