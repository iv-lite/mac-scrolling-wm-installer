# Antigen bundling — managed by mac-scrolling-wm-installer (scripts/install-antigen).
# Installed to ~/.config/zsh/antigen.zsh and sourced from ~/.zshrc inside a
# marked block. Edit freely; re-running the installer refreshes this file
# (previous copy kept as *.bak) but never touches the rest of ~/.zshrc.
#
# Requires Antigen itself to be loaded first (~/antigen.zsh, installed by
# scripts/install-antigen). Antigen runs compinit at `antigen apply`, so no
# manual `autoload -Uz compinit; compinit` belongs here or after this block.

if ! command -v antigen >/dev/null 2>&1; then
  echo "mac-scrolling-wm antigen config: 'antigen' not loaded — run scripts/install-antigen first" >&2
  return 1 2>/dev/null || exit 1
fi

antigen use oh-my-zsh

# Bundles from the default repo (robbyrussell's oh-my-zsh).
antigen bundle git
antigen bundle command-not-found

antigen bundle zsh-users/zsh-completions
antigen bundle zsh-users/zsh-autosuggestions
# Syntax highlighting must stay the LAST bundle: it registers its
# zle-line-pre-redraw hook after everything else mutating the buffer,
# otherwise suggestions highlight incorrectly.
antigen bundle zsh-users/zsh-syntax-highlighting

export TYPEWRITTEN_PROMPT_LAYOUT="singleline_verbose"
export TYPEWRITTEN_SYMBOL="$"
export TYPEWRITTEN_COLOR_MAPPINGS="primary:cyan;info_neutral_1:white"
export TYPEWRITTEN_RELATIVE_PATH="adaptive"
export TYPEWRITTEN_CURSOR="beam"
export TYPEWRITTEN_DISABLE_RETURN_CODE="true"

antigen theme reobin/typewritten@main

antigen apply
