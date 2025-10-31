#!/bin/bash

./install_scripts/zsh.sh

# Create scripts folder to `~/.local/`
mkdir ~/.local/scripts

./install_scripts/mise.sh

./install_scripts/neovim.sh
# Create symlink so fdfind can be used as fd
ln -s "$(which fdfind)" ~/.local/bin/fd

./copyconfig.sh
./copyscripts.sh

reload_zsh_config
