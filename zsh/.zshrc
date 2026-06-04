HISTFILE=~/.histfile
HISTSIZE=100000
SAVEHIST=100000
setopt HIST_SAVE_NO_DUPS
setopt INC_APPEND_HISTORY
# Move to directories without cd
setopt autocd
# Enable completions
autoload -Uz compinit && compinit

# Source the Arch packages
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Basic prompt
PROMPT='%F{green}%n@%m%f %F{blue}%~%f $ '
