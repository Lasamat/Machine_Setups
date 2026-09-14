#!/bin/bash

./install_scripts/zsh.sh

./install_scripts/mise.sh

./install_scripts/neovim.sh
# Create symlink so fdfind can be used as fd
mkdir -p ~/.local/bin
ln -s "$(which fdfind)" ~/.local/bin/fd

./linkconfig.sh

reload_zsh_config