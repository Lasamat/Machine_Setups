#!/usr/bin/env zsh

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
