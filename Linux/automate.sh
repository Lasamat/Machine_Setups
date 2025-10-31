#!/bin/bash

# Check if Zsh is installed
if command -v zsh >/dev/null 2>&1; then
  echo "Zsh is already installed. So we skip it."
else
  sudo apt install zsh
  # Change default shell from Bash to ZSH
  chsh -s $(which zsh)

  # Install oh-my-zsh
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

  # TODO fix this because its not working yet
  # echo "ZSH_THEME=\"agnoster\"" >.zshrc
  # echo "source $ZSH/oh-my-zsh.sh" >.zshrc
fi

# Set `~/.local/bin` to PATH
# Define the command to add
COMMAND='export PATH="$HOME/.local/bin:$PATH"'

# Check if the command is already in ~/.zshrc
if ! grep -qF "$COMMAND" ~/.zshrc; then
  # Append the command to ~/.zshrc
  echo "$COMMAND" >>~/.zshrc
  echo "Added the export command to ~/.zshrc"
else
  echo "The export command is already in ~/.zshrc"
fi
source ~/.zshrc

# Install mise The front-end to your dev env
curl https://mise.run | sh
# Activate mise
# Define the command to add
COMMAND2='eval "$(~/.local/bin/mise activate zsh)"'
# Check if the command is already in ~/.zshrc
if ! grep -qF "$COMMAND2" ~/.zshrc; then
  # Append the command to ~/.zshrc
  echo "$COMMAND2" >>~/.zshrc
  echo "Added the export command to ~/.zshrc"
else
  echo "The export command is already in ~/.zshrc"
fi

source ~/.zshrc

mise use --global node@22
mise use --global erlang@27.3.3
mise use --global elixir@1.18.2-otp-27

# Neovim Dependencies Ubuntu
sudo apt update
sudo apt install make gcc ripgrep unzip git xclip fd-find fzf curl
