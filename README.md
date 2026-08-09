# .bash

My personal **Bash** configuration — the counterpart of
[**zshrc**](https://github.com/Spuppateddu/zshrc), with the same aliases and the
same helper functions, for machines where bash is the shell. The prompt is left
alone on purpose: it stays the plain one bash ships with.

No framework. Nothing is cloned, nothing is compiled, nothing third-party is
sourced into your shell: the whole config is the two files in this repo plus the
`bash-completion` package. That is the deliberate difference from the zsh side,
which is built on Oh My Zsh.

## 🔗 On its own, or as part of best-linux-environment

Both work, and this repo is written not to care which one ran it.

**On its own** — clone it, run [`install.sh`](./install.sh), done. That script
owns every bash-specific step (`bash-completion`, `~/.bashrc`, the login shell);
nothing outside this repo is needed.

**As part of a whole machine** —
[**best-linux-environment**](https://github.com/Spuppateddu/best-linux-environment)
sets up an entire Ubuntu box and asks you, once, at the start, whether this
machine runs **zsh or bash**. Pick bash and it clones this repo into
`~/linux-configuration/bash`, leaves `~/.bash` behind as a symlink to it, and
calls this repo's own `install.sh` — the same script, doing the same work. It
also keeps it pulled and re-applied at every boot.

Both config repos can sit on the same machine; only one of them owns the login
shell. That is what `--no-login-shell` is for (see [Usage](#-usage) below):
best-linux-environment passes it to whichever of the two you did *not* pick, so
a `./boot.sh` can re-apply both configs without either one quietly `chsh`-ing
you back.

## ✨ Features

- **No prompt of its own.** `PS1` is never touched, so you get stock bash's
  `user@host:path$` — one line, no git branch, no theme.
- ↑/↓ search history by prefix (readline's `history-search-backward`), which is
  what the zsh config uses `zsh-history-substring-search` for.
- Tab completion for git, apt, docker and the rest, via `bash-completion`.
- The same aliases and functions as the zsh config: Git, Laravel/PHP, Composer,
  Node, tmux, yazi, lazygit, headless Chrome.
- `nvm` loaded on first use, not at every shell start.
- Machine-local overrides kept **out of version control** (`bash-alias.local`).

## 🔀 What zsh has and this doesn't

Honest list, because these are the reasons to pick zsh:

| zsh | bash |
| --- | --- |
| **Ghost-text autosuggestions** (`zsh-autosuggestions`) — the rest of a command greyed out ahead of the cursor, Ctrl+Space to accept | Nothing. readline has no such thing. `ble.sh` adds it, at the cost of a large third-party line editor in every shell |
| **Live syntax highlighting** (`zsh-syntax-highlighting`) — a typo'd command turns red as you type it | Nothing, same reason |
| **Oh My Zsh's `git` plugin** — around 150 short git aliases (`gst`, `gco`, `gcm`…) | Only the two the config itself defines, `gs` and `gp`. `git <tab>` covers the rest |
| `**/` and `AUTO_CD` on by default | `**/` turned on explicitly (`shopt -s globstar`). `AUTO_CD` is deliberately left off — a bare directory name is not a command |
| Function-scoped `trap`, so `r` and `chrome-debug` clean up on any exit | Worked around — see the comments on those two functions in [`bash-alias`](./bash-alias) |

Everything else in the zsh config is here, line for line.

## 📦 Requirements

| Tool | Why |
| --- | --- |
| [Bash](https://www.gnu.org/software/bash/) 4.2+ | The shell itself. `${var/#pat/rep}` and `local -a` need it; Ubuntu ships 5.x |
| [bash-completion](https://github.com/scop/bash-completion) | Tab completion for git, apt, docker… (optional) |
| [tmux](https://github.com/tmux/tmux) | The `ta` / `tn` aliases (optional) |
| [yazi](https://github.com/sxyazi/yazi) | The `r` file-manager function (optional) |
| [Qalculate](https://qalculate.github.io/) | The `calc` alias — provides `qalc` (optional) |
| [lazygit](https://github.com/jesseduffield/lazygit) | The `lz` alias (optional) |
| [Homebrew](https://brew.sh/) | Referenced for some paths (optional) |

`install.sh` installs bash, git, curl and bash-completion for you — you only need
this list if you'd rather wire things up by hand.

## 🚀 Installation

1. **Clone the repo and run the installer:**

   ```sh
   git clone https://github.com/Spuppateddu/configuration-bash.git ~/.bash
   ~/.bash/install.sh
   ```

   `~/.bash` is the conventional spot, but any path works — `install.sh` wires
   `~/.bashrc` to wherever you cloned it, and `bashrc` resolves its own directory
   at runtime from `${BASH_SOURCE[0]}`.

   The installer is idempotent, so re-run it any time to update. It installs
   bash/git/curl/bash-completion (apt or Homebrew), **appends** `source
   <repo>/bashrc` to the **end** of `~/.bashrc` (backing the file up first), and
   sets bash as your login shell.

   Appending at the end is the whole trick: Ubuntu's stock `~/.bashrc` sets its
   own history options and a few aliases, and going last is what makes this
   config win over them rather than be overwritten by them. Nothing in the stock
   file is deleted — and its `PS1` block is left to do its job, since this config
   sets no prompt of its own.

   Run it as yourself, **not** with `sudo` — it configures `$HOME`, and under
   `sudo` that is root's. It escalates on its own for the package installs, and
   refuses to run rather than quietly setting root's shell up instead of yours.

   Use `./install.sh --dry-run` to see every step without touching anything —
   `DRY_RUN` from the environment works too and accepts `true`/`1`/`yes`/`on`
   (anything unrecognised is rejected rather than quietly treated as a real run).

   If you keep a hand-written `~/.bash_profile`, the installer checks it: bash
   reads *that* file at login and ignores `~/.profile` (the one Ubuntu ships,
   which sources `~/.bashrc`) entirely, so a TTY or ssh session would get none of
   this config. It tells you the one line to add rather than editing your file.

   **On the login shell.** `chsh` needs your password, which it asks PAM for — so
   it needs either a terminal to ask on or root. Running this script yourself, it
   asks. Run from `best-linux-environment`, there is no terminal (stdin is
   `/dev/null`, so no installer can stop a run to ask a question), and it uses
   that run's already-cached `sudo` instead. If neither is available it says so
   and prints `chsh -s /usr/bin/bash` for you to run — it never reports success
   for something it skipped.

   **And once it is changed, you have to log out.** This is the part that looks
   like a bug and isn't. `chsh` writes `/etc/passwd` — and almost nothing reads
   `/etc/passwd`. What terminals read is `$SHELL`, which PAM sets **once**, when
   your desktop session logs in, from whatever `/etc/passwd` said at that moment.
   Change it afterwards and the running session never hears about it: your window
   manager still holds the old value and every terminal it spawns inherits it.

   Measured on Alacritty 0.16 — it prefers `$SHELL`, and only falls back to the
   passwd entry when `$SHELL` is unset:

   ```
   SHELL unset          -> bash     (falls back to the passwd entry)
   SHELL=/usr/bin/bash  -> bash
   SHELL=/usr/bin/zsh   -> zsh      (passwd said bash — $SHELL won)
   ```

   So a brand-new window from the same session is still the old shell. Fixes, in
   increasing order of thoroughness:

   | | |
   | --- | --- |
   | this shell, right now | `exec bash -l` |
   | new tmux panes | `tmux kill-server` (a running server cached the old `$SHELL`) |
   | everything, properly | log out and back in |

2. **Set up your machine-local aliases** (SSH hosts, secrets, etc.).
   Create `bash-alias.local` next to `bash-alias` — it's gitignored and sourced
   automatically, so your private hostnames/IPs never get committed:

   ```sh
   cat > ~/.bash/bash-alias.local <<'EOF'
   # Machine-local aliases — not tracked by git
   alias myserver="ssh user@host-or-ip"
   alias prod="ssh ubuntu@your.prod.ip"
   EOF
   ```

3. **Reload the shell:**

   ```sh
   exec bash   # or just open a new terminal
   ```

## 🔧 Usage

A few of the aliases you get (see [`bash-alias`](./bash-alias) for the full list):

| Alias | Does |
| --- | --- |
| `bashreload` | Re-exec bash to pick up config changes |
| `gs` / `gp` | `git status` / `git pull` |
| `lz` | Open `lazygit` |
| `pa <cmd>` | `php artisan <cmd>` |
| `lpm [:sub] [args]` | `php artisan migrate` (`lpm :fresh --seed`) |
| `r` | Open `yazi`, and `cd` to wherever you left it |
| `chrome-debug` | Headless Chrome with remote debugging on `:9222` (`CHROME_DEBUG_PORT` to change) |

And the installer's flags:

| Flag | Does |
| --- | --- |
| `--dry-run` | Print every step, change nothing |
| `--no-login-shell` | Wire the config, but don't `chsh`. Used when zsh owns the login shell on this machine |

## 📁 Layout

```
.bash/
├── install.sh    # installs deps + wires ~/.bashrc (idempotent)
├── bashrc        # main entry point (sourced from the end of ~/.bashrc)
└── bash-alias    # aliases & functions (sources bash-alias.local)
# bash-alias.local — your private, untracked aliases (gitignored)
```

The file names deliberately mirror the zsh repo's (`zshrc` / `zsh-alias` /
`zsh-alias.local`), so the two can be diffed against each other when one of them
changes.

## 📄 License

Personal dotfiles — feel free to copy anything useful.
