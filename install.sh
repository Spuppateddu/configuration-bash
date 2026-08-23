#!/usr/bin/env bash
# Installs bash-completion, points ~/.bashrc at ./bashrc, makes bash the login
# shell. Idempotent. No framework, no plugins, nothing cloned — the whole config
# is the two files next to this script.
#
# Usage: ./install.sh [--dry-run] [--no-login-shell] [--no-idle-poweroff]
#   --dry-run          print every step, touch nothing (DRY_RUN env also honoured)
#   --no-login-shell   wire the config but leave the login shell alone. What
#                      best-linux-environment passes when you chose zsh: both
#                      config repos may be on the machine, only one owns `chsh`.
#   --no-idle-poweroff wire the config but install no idle-poweroff timer, so
#                      this machine will never turn itself off
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Reject unknown args rather than ignoring them — a typo'd `--dryrun` silently
# performing a real install is the worst outcome.
usage() {
    printf 'Usage: %s [--dry-run] [--no-login-shell] [--no-idle-poweroff]\n' \
        "$(basename "${BASH_SOURCE[0]}")" >&2
    exit 2
}
SET_LOGIN_SHELL=true
# On by default: these machines are woken by Wake-on-LAN and by the BIOS after a
# power cut, so something has to turn them back off.
INSTALL_IDLE=true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)          DRY_RUN=true ;;
        --no-login-shell)   SET_LOGIN_SHELL=false ;;
        --no-idle-poweroff) INSTALL_IDLE=false ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage ;;
    esac
    shift
done
# Normalise to true/false once — every check below is a literal `== true`, so
# DRY_RUN=1 would otherwise read as false and install for real.
case "${DRY_RUN:-}" in
    ""|[Ff]alse|FALSE|0|[Nn]o|NO|[Oo]ff|OFF) DRY_RUN=false ;;
    [Tt]rue|TRUE|1|[Yy]es|YES|[Oo]n|ON)      DRY_RUN=true ;;
    *) printf 'Invalid DRY_RUN: %s\nUse DRY_RUN=true or DRY_RUN=false.\n' \
           "$DRY_RUN" >&2; exit 2 ;;
esac

# The file bash actually reads for an interactive shell. Unlike zsh there is no
# ZDOTDIR to redirect it — ~/.bashrc is the only answer.
BASHRC="$HOME/.bashrc"
# Whether the rc file predates this run, so the closing notes can tell "we added
# ourselves to your config" from "we created your config".
BASHRC_PREEXISTING=false
[[ -e "$BASHRC" ]] && BASHRC_PREEXISTING=true

# ── Self-contained helpers (no external lib — this repo installs alone) ──────
if [[ -t 1 ]]; then
    C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
    C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_DIM=''; C_BOLD=''; C_OFF=''
fi
step()  { printf '%s▸%s %s\n' "$C_BLUE"  "$C_OFF" "$*"; }
ok()    { printf '%s✓%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
skip()  { printf '%s·%s %s%s%s\n' "$C_DIM" "$C_OFF" "$C_DIM" "$*" "$C_OFF"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_OFF" "$*"; }
title() { printf '\n%s══ %s ══%s\n' "$C_BOLD" "$*" "$C_OFF"; }
run() {
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would run:%s %s\n' "$C_DIM" "$C_OFF" "$*"
    else
        "$@"
    fi
}
has_cmd() { command -v "$1" >/dev/null 2>&1; }
# Root needs no sudo (containers often lack the binary entirely); otherwise it
# needs a terminal or cached credentials, so cron runs never hang on a prompt.
can_sudo() {
    [[ $EUID -eq 0 ]] && return 0
    has_cmd sudo || return 1
    [[ -t 0 ]] || sudo -n true 2>/dev/null
}
# Prefix for privileged commands. Unquoted at call sites so root expands to
# nothing rather than an empty argv[0].
SUDO=sudo
[[ $EUID -eq 0 ]] && SUDO=""
# `sudo ./install.sh` would configure root's account instead — every path here
# is $HOME-derived. Plain root (container, SUDO_USER unset) still works.
if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
    printf 'Run this as %s, not with sudo — it configures $HOME (now %s).\n' \
        "$SUDO_USER" "$HOME" >&2
    printf 'Package installs escalate on their own. Re-run: ./install.sh\n' >&2
    exit 2
fi

# Where bash-completion's entry point lands, distro by distro. bashrc looks in
# this same list — keep the two in step.
BC_PATHS=(
    /usr/share/bash-completion/bash_completion
    /etc/bash_completion
    /opt/homebrew/etc/profile.d/bash_completion.sh
    /usr/local/etc/profile.d/bash_completion.sh
)
# bash-completion is the one dependency here that installs no binary, so
# has_cmd cannot see it — it is a file to source. Tested as a path instead.
bash_completion_here() {
    local p
    for p in "${BC_PATHS[@]}"; do [[ -r "$p" ]] && return 0; done
    return 1
}

# Install what's missing via apt or brew. The commands and the file above are
# checked before anything is handed to a package manager; a failure only warns
# and the setup continues.
pkg_ensure() {
    local pkg missing=()
    for pkg in "$@"; do
        case "$pkg" in
            bash-completion) bash_completion_here || missing+=("$pkg") ;;
            *)               has_cmd "$pkg"       || missing+=("$pkg") ;;
        esac
    done
    [[ ${#missing[@]} -eq 0 ]] && { skip "nothing to install (${*})."; return 0; }
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would install:%s %s\n' "$C_DIM" "$C_OFF" "${missing[*]}"; return 0
    fi
    if has_cmd apt-get; then
        if ! can_sudo; then
            warn "No root privileges (no sudo, or non-interactive) — skipped install: ${missing[*]}"
            return 0
        fi
        step "apt: installing ${missing[*]}"
        $SUDO apt-get update -qq || warn "apt update reported errors — continuing."
        $SUDO apt-get install -y "${missing[@]}" \
            || warn "apt install failed — install yourself: ${missing[*]}"
    elif has_cmd brew; then
        step "brew: installing ${missing[*]}"
        brew install "${missing[@]}" \
            || warn "brew install failed — install yourself: ${missing[*]}"
    else
        warn "No apt-get or brew found — install yourself: ${missing[*]}"
    fi
}

# Absolute path with the *directory* symlinks resolved, so two spellings of one
# file compare equal. `cd -P` not `readlink -f`, which macOS lacks.
canon_path() {
    local p="$1" d b
    d="$(dirname -- "$p")"; b="$(basename -- "$p")"
    if [[ -d "$d" ]]; then printf '%s/%s\n' "$(cd -P -- "$d" && pwd)" "$b"
    else printf '%s\n' "$p"; fi
}

# already_sources <path> <rc-file> — true however the line was spelled, since
# candidates are canonicalised: the repo is reachable under two names (its clone
# in linux-configuration/, and the ~/.bash symlink pointing at it).
already_sources() {
    local target="$1" file="$2" want raw path
    [[ -f "$file" ]] || return 1
    want="$(canon_path "$target")"
    while IFS= read -r raw; do
        path="$raw"
        # No shell expands the rc file here, so handle the three spellings by
        # hand. Anything still relative is unresolvable — skip it.
        case "$path" in
            "~/"*)       path="$HOME/${path#\~/}" ;;
            '$HOME/'*)   path="$HOME/${path#\$HOME/}" ;;
            '${HOME}/'*) path="$HOME/${path#\$\{HOME\}/}" ;;
        esac
        [[ "$path" == /* ]] || continue
        [[ "$(canon_path "$path")" == "$want" ]] && return 0
    done < <(awk '
        # Print the argument of every source/. command, one per line. Anchored
        # at a command position, so a path inside an alias is not collected.
        { line = $0
          sub(/^[[:space:]]+/, "", line)
          if (line ~ /^#/) next
          if (!match(line, /(^|[;&|(])[[:space:]]*(source|\.)[[:space:]]+/)) next
          rest = substr(line, RSTART + RLENGTH)
          q = substr(rest, 1, 1)
          # A quoted argument runs to its closing quote, so a path with a space
          # survives; an unquoted one stops at the first separator.
          if (q == "\"" || q == "\047") {
              rest = substr(rest, 2)
              i = index(rest, q)
              if (i > 0) rest = substr(rest, 1, i - 1)
          } else {
              sub(/[[:space:];&|)].*$/, "", rest)
          }
          if (rest != "") print rest
        }' "$file")
    return 1
}

# ensure_source_line <path-to-source> <rc-file> — always appends, and appends at
# the very END of the file. That position is the point: Ubuntu's stock ~/.bashrc
# sets its own history options and a handful of aliases, and going last is what
# makes this config win over them instead of being overwritten by them. Its PS1
# is left alone — this config sets no prompt. The original is backed up first.
ensure_source_line() {
    local target="$1" file="$2"
    # Quoted, so a repo cloned to a path with spaces still sources.
    local line="source \"$target\""
    if already_sources "$target" "$file"; then
        skip "${file/#$HOME/\~} already wired."
        return
    fi
    # Under --dry-run nothing is touched, so no message may claim otherwise.
    local say=appending
    [[ "$DRY_RUN" == true ]] && say="would append"
    if [[ -s "$file" ]]; then
        step "${file/#$HOME/\~} exists — $say to the end of it"
        # One stable backup, written only the first time — re-copying would bury
        # the pristine original under an already-wired copy.
        local backup="$file.pre-bash-config.backup"
        if [[ -e "$backup" ]]; then
            skip "backup already exists at ${backup/#$HOME/\~} — keeping it."
        elif [[ "$DRY_RUN" == true ]]; then
            printf '%s  would back up:%s %s → %s\n' "$C_DIM" "$C_OFF" \
                "${file/#$HOME/\~}" "${backup/#$HOME/\~}"
        else
            step "Backing up to ${backup/#$HOME/\~}"
            cp "$file" "$backup"
        fi
    fi
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would append:%s %s → %s\n' "$C_DIM" "$C_OFF" "$line" \
            "${file/#$HOME/\~}"
        return
    fi
    # Don't glue onto a file whose last line has no newline.
    [[ -s "$file" && -n "$(tail -c1 "$file")" ]] && printf '\n' >> "$file"
    {
        printf '\n# Bash config from %s — keep this last so it wins over the\n' \
            "${REPO/#$HOME/\~}"
        printf '# options and aliases the lines above set.\n'
        printf '%s\n' "$line"
    } >> "$file"
    ok "wired ${file/#$HOME/\~}"
}

# ── Install ──────────────────────────────────────────────────────────────────
title "Bash"

# bash and git are almost certainly here already; bash-completion is the one that
# usually isn't, and it is what gives `git <tab>`, `apt <tab>` and __git_ps1.
pkg_ensure bash git curl bash-completion

# 1. Point the rc file at this repo, wherever it was cloned — bashrc resolves its
#    own paths from ${BASH_SOURCE[0]}.
ensure_source_line "$REPO/bashrc" "$BASHRC"

# 2. Make sure a LOGIN shell reaches ~/.bashrc too.
#
#    This is the one piece of bash that has no zsh equivalent and catches people
#    out. An interactive non-login shell (a terminal you open on the desktop)
#    reads ~/.bashrc, which step 1 just wired. A LOGIN shell — a TTY, an ssh
#    session, `bash -l`, and the shell `chsh` gives you — does not read ~/.bashrc
#    at all. It reads the FIRST of ~/.bash_profile, ~/.bash_login, ~/.profile that
#    exists, and none of the others.
#
#    Ubuntu ships a ~/.profile (from /etc/skel) whose last stanza sources
#    ~/.bashrc, which is why wiring ~/.bashrc is normally the whole job. Two ways
#    that breaks: a hand-written ~/.bash_profile shadows ~/.profile outright, and
#    a home directory built without /etc/skel has none of the three. Either way
#    ssh'ing in would give you a bare bash with no prompt, no aliases, no PATH.
LOGIN_RC=""
for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
    [[ -f "$candidate" ]] && { LOGIN_RC="$candidate"; break; }
done

# Matches every spelling in the wild: Debian's own tab-indented `. "$HOME/.bashrc"`
# inside an if, and the one-liner `[ -f ~/.bashrc ] && . ~/.bashrc`.
sources_bashrc() {
    grep -qE '(^|[[:space:];&])(source|\.)[[:space:]]+.*\.bashrc' "$1"
}

if [[ -z "$LOGIN_RC" ]]; then
    # Writing ~/.profile rather than warning, because there is nothing here to
    # overwrite and no judgement call to make: the file does not exist, and every
    # Ubuntu home has one. This is the stanza Debian's own /etc/skel/.profile
    # ends with, and nothing else.
    step "No ~/.bash_profile, ~/.bash_login or ~/.profile — login shells would read nothing"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s ~/.profile, sourcing ~/.bashrc\n' "$C_DIM" "$C_OFF"
    else
        cat > "$HOME/.profile" <<'PROFILE'
# ~/.profile: read by a login shell. Written by the bash config's install.sh
# because none of ~/.bash_profile, ~/.bash_login or ~/.profile existed, and a
# login shell reads one of those three or nothing at all — never ~/.bashrc.
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi
PROFILE
        ok "wrote ~/.profile (sources ~/.bashrc, so ssh and TTY logins get the config)"
    fi
elif sources_bashrc "$LOGIN_RC"; then
    skip "${LOGIN_RC/#$HOME/\~} already sources ~/.bashrc — login shells are covered."
else
    # Not edited: this one is yours, and which of the three bash picks depends on
    # what else you keep in it. One line is all it needs.
    warn "${LOGIN_RC/#$HOME/\~} exists and does not source ~/.bashrc."
    warn "bash reads that file at login and stops there, so a TTY or ssh session"
    warn "would get none of this config. Add this line to ${LOGIN_RC/#$HOME/\~}:"
    warn '    [ -f ~/.bashrc ] && . ~/.bashrc'
fi

# 3. Make bash the login shell.
#
# `chsh` changing your own entry goes through PAM, which wants your password — so
# it needs either a terminal to ask on or root. A plain `[[ -t 0 ]]` guard is not
# enough, and getting that wrong is silent in the worst way: run under
# best-linux-environment, stdin is /dev/null (no installer may stop the run to ask
# a question), so the guard was false, chsh was skipped, and the whole shell
# choice you had just been asked for did nothing. The next terminal was still zsh.
#
# So try the ways this can work, in order of what is actually available:
#   root          no PAM prompt at all
#   cached sudo   `sudo -n` — the case that matters. A ./setup.sh run has already
#                 used sudo for the package installs, so its credentials are warm
#                 and this goes through with no prompt and no terminal.
#   a terminal    running this repo on its own: chsh asks, you type it
# and only when none of those hold, print the command to run by hand.
set_login_shell() {
    local target="$1" user; user="$(id -un)"
    if [[ $EUID -eq 0 ]]; then
        run chsh -s "$target" "$user"
    elif has_cmd sudo && sudo -n true 2>/dev/null; then
        run sudo -n chsh -s "$target" "$user"
    elif [[ -t 0 ]]; then
        run chsh -s "$target"
    else
        return 1
    fi
}

bash_path="$(command -v bash || true)"
# id -un, not $USER — $USER is unset under cron/systemd and set -u would abort.
login_shell="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7 || true)"
[[ -z "$login_shell" ]] && login_shell="${SHELL:-}"   # getent is Linux-only
if [[ "$SET_LOGIN_SHELL" != true ]]; then
    skip "--no-login-shell — config wired, login shell left as ${login_shell:-unknown}."
elif [[ -z "$bash_path" ]]; then
    warn "bash not found on PATH — skipping login-shell step."
elif [[ "$login_shell" == "$bash_path" ]]; then
    skip "bash already the login shell."
elif [[ "$DRY_RUN" == true ]]; then
    # A dry run must not claim the shell changed: the block below tells you to log
    # out, and doing that after a dry run is the exact confusion it fights.
    set_login_shell "$bash_path" || warn "no terminal and no cached sudo — chsh would be skipped."
    skip "dry run — login shell still ${login_shell:-unknown}."
elif set_login_shell "$bash_path"; then
    ok "bash is now your login shell (was ${login_shell:-unknown})."
    # Spelled out because this is the thing people file a bug about — "I chose
    # bash, chsh worked, and my next terminal was STILL the old shell".
    #
    # chsh changes /etc/passwd. Almost nothing reads /etc/passwd. What terminals
    # read is $SHELL, and $SHELL is set once, by PAM, when your desktop session
    # logs in — from whatever /etc/passwd said AT THAT MOMENT. Change it
    # afterwards and the running session never hears about it: your window
    # manager still holds the old value, and every terminal it spawns inherits it.
    #
    # Measured on Alacritty 0.16: it prefers $SHELL and only falls back to the
    # passwd entry when $SHELL is unset. So a brand-new window opened from the
    # same session is still the old shell. That is not a failed chsh — it is a
    # session that has not logged in again yet.
    warn "chsh is done, but it only takes effect at your next LOGIN."
    warn "\$SHELL is still ${SHELL:-unset} in this session, and terminals read that —"
    warn "so even a brand-new window keeps the old shell until you log out."
    warn "  now, in this shell   : exec bash -l"
    warn "  new tmux panes       : tmux kill-server"
    warn "  everything, properly : log out and back in"
else
    warn "Could not change the login shell: no terminal to ask for a password on,"
    warn "and no cached sudo credentials. Run it yourself:"
    warn "    chsh -s $bash_path"
fi

# bash-completion missing is not fatal — the config just degrades to no tab
# completion — but it is worth saying out loud.
if [[ "$DRY_RUN" != true ]] && ! bash_completion_here; then
    warn "bash-completion is not installed — tab completion for git/apt/docker"
    warn "stays off. Everything else in this config works."
fi

# ── Idle poweroff ────────────────────────────────────────────────────────────
# A root systemd timer that powers this machine off once unused. Never fatal.

# install_root_file <mode> <src> <dest> — copies only when the contents differ,
# so ./boot.sh re-running this at every boot is silent. Sets IDLE_CHANGED.
IDLE_CHANGED=false
install_root_file() {
    local mode="$1" src="$2" dest="$3"
    if [[ ! -r "$src" ]]; then
        warn "Missing $src — skipping ${dest}."
        return 1
    fi
    if cmp -s "$src" "$dest"; then
        skip "$dest already current."
        return 0
    fi
    step "installing $dest"
    if run $SUDO install -D -m "$mode" -o root -g root "$src" "$dest"; then
        IDLE_CHANGED=true
        return 0
    fi
    warn "Could not write $dest."
    return 1
}

install_idle_poweroff() {
    local src="$REPO/idle-poweroff"
    title "Idle poweroff"

    if [[ "$INSTALL_IDLE" != true ]]; then
        skip "--no-idle-poweroff — leaving the idle timer alone."
        return 0
    fi
    if [[ ! -d "$src" ]]; then
        skip "No idle-poweroff/ in this repo — nothing to install."
        return 0
    fi
    # The documented "booted with systemd" test; false inside a container even
    # when the systemctl binary is present.
    if ! has_cmd systemctl || [[ ! -d /run/systemd/system ]]; then
        skip "Not booted with systemd — idle poweroff needs its timer, skipping."
        return 0
    fi
    if ! can_sudo; then
        warn "No root privileges — idle poweroff not installed."
        warn "It writes a systemd unit and calls poweroff, so it needs root."
        warn "Re-run ./install.sh from a terminal to install it."
        return 0
    fi

    # Without it a desktop falls back to "cannot measure, assume in use" and
    # never powers off; a headless machine never needs it.
    pkg_ensure xprintidle

    install_root_file 0755 "$src/idle-poweroff.sh"      /usr/local/sbin/idle-poweroff
    install_root_file 0644 "$src/idle-poweroff.service" /etc/systemd/system/idle-poweroff.service
    install_root_file 0644 "$src/idle-poweroff.timer"   /etc/systemd/system/idle-poweroff.timer

    # Machine-local, like bash-alias.local: written once so ./boot.sh can never
    # undo your settings.
    if [[ -e /etc/idle-poweroff.conf ]]; then
        skip "/etc/idle-poweroff.conf exists — your settings kept."
    else
        install_root_file 0644 "$src/idle-poweroff.conf" /etc/idle-poweroff.conf
    fi

    if [[ "$DRY_RUN" == true ]]; then
        skip "dry run — timer not reloaded or enabled."
        return 0
    fi

    if [[ "$IDLE_CHANGED" == true ]]; then
        $SUDO systemctl daemon-reload || warn "systemctl daemon-reload failed."
        $SUDO systemctl enable --quiet idle-poweroff.timer 2>/dev/null \
            || warn "Could not enable idle-poweroff.timer."
        # restart, not start: a running timer still holds the OLD unit file.
        if $SUDO systemctl restart idle-poweroff.timer; then
            ok "idle-poweroff.timer installed and running."
        else
            warn "Could not start it — see: systemctl status idle-poweroff.timer"
            return 0
        fi
    elif systemctl is-active --quiet idle-poweroff.timer; then
        skip "idle-poweroff.timer already running."
    else
        $SUDO systemctl enable --now idle-poweroff.timer \
            && ok "idle-poweroff.timer enabled." \
            || warn "Could not enable idle-poweroff.timer."
    fi

    # Said out loud: a machine that powers itself off should never be a surprise.
    local mins locked
    mins=$(awk -F= '/^[[:space:]]*IDLE_MINUTES=/   { v = $2 } END { print (v ? v : 60) }' /etc/idle-poweroff.conf 2>/dev/null)
    locked=$(awk -F= '/^[[:space:]]*LOCKED_MINUTES=/ { v = $2 } END { print (v ? v : 10) }' /etc/idle-poweroff.conf 2>/dev/null)
    ok "This machine now powers itself off after ${mins:-60} min unused (${locked:-10} min with the screen locked)."
    ok "Check it with 'b-idle'; pause it with 'b-idle off'; settings in /etc/idle-poweroff.conf."
}

install_idle_poweroff

# ── Machine-local aliases ────────────────────────────────────────────────────
# Not created: an empty file would make bashrc's `[ -f ]` test pass and hide the
# fact that there is nothing in it. See the README for what goes here.
if [[ ! -f "$REPO/bash-alias.local" ]]; then
    skip "No bash-alias.local yet — put your SSH hosts and private aliases there."
fi

# Reload: a parent shell can't be re-sourced from this subprocess, so guide it.
if [[ "$BASHRC_PREEXISTING" == true ]]; then
    warn "Reload bash to apply the config: run 'exec bash' or open a new terminal."
else
    warn "Created ~/.bashrc. Open a new terminal, or run 'exec bash'."
fi
ok "Bash ready."
