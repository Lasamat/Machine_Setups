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

  # TODO fix this because its not working yet
  # echo "ZSH_THEME=\"agnoster\"" >.zshrc
  # echo "source $ZSH/oh-my-zsh.sh" >.zshrc

  # Set `~/.local/bin` to PATH
  append_to_zshrc 'export PATH="$HOME/.local/bin:$PATH"' '.local/bin'
  # Set `~/.local/scripts` to PATH
  append_to_zshrc 'export PATH="$HOME/.local/scripts:$PATH"' '.local/bin'
  # Start ssh-agent when zsh loads and add alias to load ssh key
  append_to_zshrc 'eval "$(ssh-agent -s)"' 'ssh-agent'
  append_to_zshrc 'alias gitkey="ssh-add ~/.ssh/id_ed25519"' 'alias gitkey'
  append_to_zshrc 'alias v="fd --type f --hidden --exclude .git | fzf-tmux -p --reverse | { read file && nvim "$file"; }"'
fi
