#!/usr/bin/env zsh

# Function to append a command to ~/.zshrc if it doesn't already exist
append_to_zshrc() {
  local COMMAND="$1"
  local NAME="$2"

  # Check if the command is already in ~/.zshrc
  if ! grep -qF "$COMMAND" ~/.zshrc; then
    # Append the command to ~/.zshrc
    echo -e "$COMMAND" >>~/.zshrc
    echo "Added $2 to ~/.zshrc"
  else
    echo "$2 is already in ~/.zshrc"
  fi
  reload_zsh_config
}

reload_zsh_config() {
  zsh -c 'source ~/.zshrc'
}
