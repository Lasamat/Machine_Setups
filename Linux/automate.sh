!#/bin/bash

sudo apt install zsh
# Change default shell from Bash to ZSH
chsh -s $(which zsh)

# Install oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

echo "ZSH_THEME=\"agnoster\"" >.zshrc
echo "source $ZSH/oh-my-zsh.sh" >.zshrc
