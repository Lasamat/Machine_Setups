#!/usr/bin/env zsh

source ./zsh_util.sh

# Check if Zsh is installed
if command -v zsh >/dev/null 2>&1; then
  echo "Zsh is already installed. So we skip it."
else
  sudo apt install zsh
  # Change default shell from Bash to ZSH
  chsh -s $(which zsh)

  # Install oh-my-zsh
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

  reload_zsh_config
fi

# NOTE: ~/.zshrc is repo-owned and symlinked by ../linkconfig.sh (which must
# run after this script, since a fresh oh-my-zsh install writes a template
# .zshrc that linkconfig preserves as a backup).