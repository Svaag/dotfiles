export TERM=xterm-color
export LANG=en_US.UTF-8

ZSH=/usr/share/oh-my-zsh/

ZSH_THEME="bureau"

DISABLE_AUTO_UPDATE="true"

# Plugins
plugins=(git)

ZSH_CACHE_DIR=$HOME/.cache/oh-my-zsh
if [[ ! -d $ZSH_CACHE_DIR ]]; then
  mkdir $ZSH_CACHE_DIR
fi

source $ZSH/oh-my-zsh.sh

setopt histignorespace
