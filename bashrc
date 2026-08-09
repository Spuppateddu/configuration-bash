# Bash counterpart of the zsh config in this same linux-configuration/ folder.
# Sourced from ~/.bashrc by install.sh, at the very end of it — so the options
# below win over whatever Ubuntu's stock ~/.bashrc set earlier.
#
# This file does NOT touch PS1: the prompt stays whatever stock bash set.

# Directory this file lives in, so the repo works from any clone location. $0 is
# the *shell* when a file is sourced in bash, never the file — ${BASH_SOURCE[0]}
# is. `cd -P` resolves the ~/.bash symlink, which readlink -f would too but macOS
# has no readlink -f.
BASH_CONFIG_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Default only — never override a locale the system already set.
export LANG="${LANG:-en_US.UTF-8}"

# bash has no `typeset -U path`, so de-duplication is by hand: re-sourcing this
# file (or `exec bash`) would otherwise grow PATH one copy per shell.
# Guarded on the directory existing. Later calls land further left, so call
# order is precedence order (lowest first).
_prepend_path() {
    [ -d "$1" ] || return 0
    # The colons make this a whole-element match: without them /usr/local/bin
    # would be found inside /usr/local/bin.d and skipped.
    case ":$PATH:" in
        *":$1:"*) ;;
        *) export PATH="$1:$PATH" ;;
    esac
}

_prepend_path "$HOME/bin"
# Locally-installed binaries (yazi, fzf, lazygit, temps). Ubuntu adds this from
# ~/.profile, which a non-login shell never reads — without this they don't
# resolve over SSH.
_prepend_path "$HOME/.local/bin"
# Intel-Homebrew path — absent on Linux and on Apple Silicon.
_prepend_path /usr/local/opt/mysql-client/bin

# nvm, loaded on first use: sourcing nvm.sh costs 100-400ms per shell and most
# shells never run node.
export NVM_DIR="$HOME/.nvm"
_nvm_load() {
    # `unset -f`, bash's spelling of zsh's `unfunction`.
    unset -f nvm node npm npx 2>/dev/null
    local dir
    # First hit wins — sourcing both would load two nvm versions over each other.
    for dir in /opt/homebrew/opt/nvm "$NVM_DIR"; do
        [ -s "$dir/nvm.sh" ] && { \. "$dir/nvm.sh"; break; }
    done
    [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \
        \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    return 0
}
for _nvm_cmd in nvm node npm npx; do
    # No `command` prefix: nvm itself is a shell function, which it would skip.
    eval "$_nvm_cmd() { _nvm_load; $_nvm_cmd \"\$@\"; }"
done
unset _nvm_cmd

# Composer's global bin — legacy first, so the XDG path wins when both exist.
_prepend_path "$HOME/.composer/vendor/bin"
_prepend_path "$HOME/.config/composer/vendor/bin"
# Homebrew only exists on macOS here — guard so Linux doesn't error.
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"

# Guarded like the zsh side: the aliases below still load without the rest of
# this file working, so name the path tried instead of "no such file or directory".
if [ -f "$BASH_CONFIG_DIR/bash-alias" ]; then
    . "$BASH_CONFIG_DIR/bash-alias"
else
    printf 'bashrc: bash-alias not found at %s — aliases and helper functions are off.\n' \
        "$BASH_CONFIG_DIR" >&2
fi

# ── everything below is interactive-only ────────────────────────────────────
# `bind`, the prompt and the shell options are meaningless in a script, and
# `bind` in particular prints a warning to stderr when there is no line editor.
# Ubuntu's stock ~/.bashrc already returns early for non-interactive shells, but
# this file is also sourced by hand and from other rc files, so it guards itself.
case $- in
    *i*) ;;
    *) return 0 ;;
esac

# ── shell options ───────────────────────────────────────────────────────────
shopt -s checkwinsize    # keep $LINES/$COLUMNS right after a resize
shopt -s histappend      # append to the history file, never truncate it
shopt -s cmdhist         # a multi-line command is one history entry
shopt -s globstar        # ** matches recursively, as zsh does by default
shopt -s cdspell         # fix small typos in a cd target
shopt -s dirspell        # ...and in a directory being completed
shopt -s no_empty_cmd_completion   # don't scan all of PATH on an empty line

# History. bash keeps far less by default than Oh My Zsh does, and the numbers
# below are the omz ones: ignoredups drops an immediately repeated command,
# ignorespace lets a command prefixed with a space stay out of the file
# entirely (for a one-off with a token in it).
HISTSIZE=50000
HISTFILESIZE=50000
HISTCONTROL=ignoredups:ignorespace
# Commands that say nothing about what you were doing, and only push something
# useful out of the file.
HISTIGNORE='ls:ll:la:cd:cd -:pwd:exit:clear:bg:fg:history'
HISTTIMEFORMAT='%F %T '

# ── keys ────────────────────────────────────────────────────────────────────
# The zsh config binds ↑/↓ to zsh-history-substring-search. readline's
# history-search-backward is the same behaviour built in: type a prefix, then ↑
# walks only the history entries starting with it.
#
# Both spellings are bound for the same reason the zsh config binds both: \e[A
# is what a terminal sends normally, \eOA what it sends in application cursor
# mode (which is what tmux and vim put it in).
if [[ $- == *i* ]]; then
    bind '"\e[A": history-search-backward'
    bind '"\e[B": history-search-forward'
    bind '"\eOA": history-search-backward'
    bind '"\eOB": history-search-forward'

    bind 'set enable-bracketed-paste on'   # a pasted newline doesn't run yet
    bind 'set colored-stats on'            # ls-style colours in completion lists
    # Oh My Zsh completes case-insensitively by default (CASE_SENSITIVE="false"),
    # so bash is told to as well rather than being the odd one out.
    bind 'set completion-ignore-case on'
    bind 'set show-all-if-ambiguous on'    # one Tab, not two, to see the list
fi

# ── completion ──────────────────────────────────────────────────────────────
# bash-completion is what gives `git <tab>`, `docker <tab>`, `apt <tab>` and the
# rest — the closest thing to what the git plugin does for zsh. install.sh
# installs the package; this finds it wherever the distro put it.
if ! shopt -oq posix; then
    for _bc in /usr/share/bash-completion/bash_completion \
               /etc/bash_completion \
               /opt/homebrew/etc/profile.d/bash_completion.sh \
               /usr/local/etc/profile.d/bash_completion.sh; do
        [ -r "$_bc" ] && { . "$_bc"; break; }
    done
    unset _bc
fi

# ── prompt ──────────────────────────────────────────────────────────────────
# On purpose: nothing here. PS1 is left exactly as Ubuntu's stock ~/.bashrc set
# it (`user@host:path$`, one line, no git branch). If you ever want a custom
# prompt, set PS1 in ~/.bashrc *after* the line that sources this file — bash-
# alias runs further up, so it is too early to win.
