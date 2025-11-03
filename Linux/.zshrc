# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="agnoster"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )


# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git vi-mode)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='nvim'
fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
#


alias repo='cd /mnt/g/Repository/'
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.local/scripts:$PATH"

activateMise() {
  eval "$(~/.local/bin/mise activate zsh)"
}

gitkey() {
  eval "$(ssh-agent -s)"
  ssh-add ~/.ssh/id_ed25519
}

v() {
    local dir="${1:-.}"  # Default to current directory if no argument is provided
    fd --type f --hidden --exclude .git . "$dir" | fzf-tmux -p --reverse | { read file && nvim "$file"; }
}

c() {
    local dir="${1:-.}"  # Default to current directory if no argument is provided
    # Use fd to list directories, then use fzf to select one and finally change into it
    local chosen_dir
    chosen_dir=$(fd --type d --hidden --exclude .git . "$dir" | fzf-tmux -p --reverse) || return
    if [ -n "$chosen_dir" ]; then
        cd "$chosen_dir" || return
    fi
}

alias tmuxs='~/.local/scripts/tmux-sessionizer'

# Check if inside a tmux session
if [ -z "$TMUX" ]; then
    # Check if there are any existing tmux sessions
    if tmux list-sessions 2>/dev/null | grep -q .; then
        # Attach to the first available session
        tmux attach-session
    else
        # Start a new tmux session named 'default'
        tmux new-session -s default
    fi
fi

