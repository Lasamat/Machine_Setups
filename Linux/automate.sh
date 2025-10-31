#!/bin/bash

source ./install_scripts/zsh_util.sh

./install_scripts/zsh.sh

# Set `~/.local/bin` to PATH
append_to_zshrc 'export PATH="$HOME/.local/bin:$PATH"' '.local/bin'

./install_scripts/mise.sh

# Start ssh-agent when zsh loads and add alias to load ssh key
append_to_zshrc 'eval "$(ssh-agent -s)"' 'ssh-agent'
append_to_zshrc 'alias gitkey="ssh-add ~/.ssh/id_ed25519"' 'alias gitkey'

./install_scripts/neovim.sh

reload_zsh_config
