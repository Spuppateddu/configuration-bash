# .bash

My personal **Bash** configuration: two files and the `bash-completion` package.
No framework, nothing third-party sourced into your shell. The prompt stays the
one bash ships with, only always coloured.

![The stock bash prompt running fastfetch in alacritty](./pictures/bash_setup.png)

## ✨ What you get

- **Stock prompt, always coloured.** The `user@host:path$` bash ships with — one
  line, no git branch, no theme — user@host gruvbox orange, path gruvbox aqua.
  Stock `~/.bashrc` colours it only for `TERM` `xterm-color|*-256color`, which is
  why tmux had colour and alacritty did not; here the test is `tput colors`. On a
  terminal without 256 colours it falls back to plain red and cyan.
- **↑/↓ searches history by prefix.** Type the start of a command, then ↑ walks
  only the entries that begin with it (readline's `history-search-backward`).
- **Tab completion** for git, apt, docker and the rest, via `bash-completion` —
  case-insensitive, and one Tab shows the list instead of two.
- **50 000 lines of history** that appends instead of truncating, drops repeats,
  and skips any command you type with a leading space.
- **Recursive globs and a forgiving `cd`.** `shopt -s globstar`, plus `cdspell`
  and `dirspell` to fix small typos in a directory name.
- **Short aliases** for git, tmux, yazi, lazygit, lazydocker and Qalculate — see
  [Usage](#-usage).
- **`nvm` loaded on first use**, not at every shell start. Sourcing `nvm.sh`
  costs 100–400 ms and most shells never run node.
- **Private aliases stay private.** `bash-alias.local` is gitignored and sourced
  automatically, so machine-specific hosts and IPs never get committed.
- **The machine turns itself off when nobody is using it** — an hour idle, ten
  minutes with the screen locked. The counterpart to Wake-on-LAN and
  "power on after power loss". See [Idle poweroff](#-idle-poweroff).

## 🚀 Install

Two ways in. Same script, same result — this repo does not care which one ran it.

### On its own

```sh
git clone https://github.com/Spuppateddu/configuration-bash.git ~/.bash
~/.bash/install.sh
exec bash
```

That is the whole thing. `install.sh` owns every step — the packages, `~/.bashrc`
and the login shell — so nothing outside this repo is needed.

`~/.bash` is the conventional spot, but any path works: the installer wires
`~/.bashrc` to wherever you cloned it, and `bashrc` finds its own directory at
runtime from `${BASH_SOURCE[0]}`.

Then, optionally, add your machine-local aliases — SSH hosts, secrets, anything
you don't want on GitHub:

```sh
cat > ~/.bash/bash-alias.local <<'EOF'
# Machine-local aliases — not tracked by git
alias myserver="ssh user@host-or-ip"
alias prod="ssh ubuntu@your.prod.ip"
EOF
```

### As part of best-linux-environment

[**best-linux-environment**](https://github.com/Spuppateddu/best-linux-environment)
sets up a whole Ubuntu box. It clones this repo into `~/linux-configuration/bash`,
symlinks `~/.bash` to it, and calls this same `install.sh` — then keeps it pulled
and re-applied at every boot. The `b-reload` alias triggers that by hand.

Several shell configs can live on one machine, but only one owns the login shell.
That is what `--no-login-shell` is for: best-linux-environment passes it to the
configs that did *not* win, so re-running `boot.sh` never quietly `chsh`-es you
back.

## 📦 Requirements

Only bash is required. Everything else is optional — you lose the matching alias
and nothing else.

| Tool | Needed for |
| --- | --- |
| [Bash](https://www.gnu.org/software/bash/) 4.2+ | The shell itself. `${var/#pat/rep}` and `local -a` need it; Ubuntu ships 5.x |
| [bash-completion](https://github.com/scop/bash-completion) | Tab completion for git, apt, docker… |
| [tmux](https://github.com/tmux/tmux) | `ta`, `tn` |
| [yazi](https://github.com/sxyazi/yazi) | `r` |
| [lazygit](https://github.com/jesseduffield/lazygit) / [lazydocker](https://github.com/jesseduffield/lazydocker) | `lz`, `ld` |
| [Qalculate](https://qalculate.github.io/) | `calc` (provides `qalc`) |

`install.sh` installs bash, git, curl and bash-completion for you — this list is
only for wiring things up by hand.

## 🔧 Usage

| Alias | Does |
| --- | --- |
| `gs` / `gp` | `git status` / `git pull` |
| `lz` / `ld` | Open `lazygit` / `lazydocker` |
| `v` | `vim .` |
| `r` | Open `yazi`, and `cd` to wherever you left it |
| `ta` | `tmux attach` |
| `tn [name]` | New tmux session, named if you give it one |
| `calc ['43 + 5 * 20']` | Qalculate, interactive or one-shot |
| `b-reload` | Re-apply every config repo via best-linux-environment's `boot.sh`, then `exec bash` |
| `b-idle [off\|on\|log]` | Idle-poweroff status, or hold it off until reboot — see [Idle poweroff](#-idle-poweroff) |

Full source in [`bash-alias`](./bash-alias). Installer flags:

| Flag | Does |
| --- | --- |
| `--dry-run` | Print every step, change nothing. `DRY_RUN` in the environment works too |
| `--no-login-shell` | Wire the config, but don't `chsh` — for when another shell owns the login shell |
| `--no-idle-poweroff` | Wire the config, but install no idle-poweroff timer, so this machine never turns itself off |

## 🔍 What the installer actually does

It is idempotent, so re-run it any time to update.

1. Installs bash, git, curl and bash-completion (apt, or Homebrew on macOS).
2. Backs up `~/.bashrc`, then **appends** `source <repo>/bashrc` to the **end**
   of it.
3. Sets bash as your login shell.
4. Installs the [idle poweroff](#-idle-poweroff) systemd timer (needs root; skipped
   with a warning if there isn't any, and by `--no-idle-poweroff`).

Appending at the end is the whole trick. Ubuntu's stock `~/.bashrc` sets its own
history options and aliases; going last is what makes this config win over them
instead of being overwritten by them. Nothing in the stock file is deleted, and
its `PS1` block still runs — this config just repaints the prompt after it.

Run it as yourself, **not** with `sudo`: it configures `$HOME`, and under `sudo`
that is root's. It escalates on its own for the package installs, and refuses to
run rather than quietly setting up root's shell instead of yours.

If you keep a hand-written `~/.bash_profile`, the installer checks it. Bash reads
*that* file at login and ignores `~/.profile` (the one Ubuntu ships, which
sources `~/.bashrc`) — so a TTY or ssh session would get none of this config. It
prints the one line to add rather than editing your file.

## 🩺 The login shell changed, but my terminal didn't

This looks like a bug and isn't.

`chsh` writes `/etc/passwd` — and almost nothing reads `/etc/passwd`. What
terminals read is `$SHELL`, which PAM sets **once**, when your desktop session
logs in, from whatever `/etc/passwd` said at that moment. Change it afterwards
and the running session never hears about it: your window manager still holds the
old value, and every terminal it spawns inherits it.

Measured on Alacritty 0.16 — it prefers `$SHELL`, and only falls back to the
passwd entry when `$SHELL` is unset:

```
SHELL unset             -> bash          (falls back to the passwd entry)
SHELL=/usr/bin/bash     -> bash
SHELL=<any other shell> -> that shell    (passwd said bash — $SHELL won)
```

So a brand-new window from the same session is still the old shell. Fixes, least
to most thorough:

| | |
| --- | --- |
| this shell, right now | `exec bash -l` |
| new tmux panes | `tmux kill-server` (a running server cached the old `$SHELL`) |
| everything, properly | log out and back in |

One more wrinkle: `chsh` asks PAM for your password, so it needs either a
terminal to ask on, or root. Run the script yourself and it asks. Run it from
best-linux-environment and there is no terminal (stdin is `/dev/null`, so no
installer can stop the run to ask), so it uses that run's already-cached `sudo`.
If neither is available it says so and prints `chsh -s /usr/bin/bash` for you —
it never reports success for something it skipped.

## 📁 Layout

```
.bash/
├── install.sh    # installs deps + wires ~/.bashrc (idempotent)
├── bashrc        # main entry point (sourced from the end of ~/.bashrc)
├── bash-alias    # aliases & functions (sources bash-alias.local)
├── idle-poweroff/  # the idle poweroff script, its systemd units and its config
│   ├── idle-poweroff.sh       # → /usr/local/sbin/idle-poweroff
│   ├── idle-poweroff.service  # → /etc/systemd/system/
│   ├── idle-poweroff.timer    # → /etc/systemd/system/  (once a minute)
│   └── idle-poweroff.conf     # → /etc/idle-poweroff.conf, written once
└── pictures/     # screenshots used by this README
# bash-alias.local — your private, untracked aliases (gitignored)
```

## ⏻ Idle poweroff

These machines are woken with Wake-on-LAN, and their BIOS is set to power on
again after a power loss. A blackout at 3am therefore boots every box in the
house — and with nobody home they sit at the login screen for days. `install.sh`
installs the other half of that setting: a root systemd timer that powers the
machine back off once it is demonstrably unused.

| Situation | Powers off after |
| --- | --- |
| Screen locked (`i3lock`) | **10 min** — locking is the human saying they left |
| Unlocked desktop | **1 h** with no key or mouse event (`xprintidle`) |
| Sitting at the LightDM login window | **1 h** — the blackout case |
| Headless, or no X at all | **1 h**, counted from the first check after boot |

It never powers off silently. At the limit it sends a desktop notification and a
`wall`, waits two minutes, and only then pulls the plug — any activity in that
window cancels it.

And it will not power off **at all** while:

- the 1-minute load average is above `0.5` — a build, a render, a backup;
- a tty or ssh login has written to its terminal within the last hour;
- a systemd `block` inhibitor is holding shutdown, which is the clean way to
  protect a long job: `systemd-inhibit --what=shutdown --why='ripping a disc' -- make -j16`;
- `b-idle off` is in force, or `ENABLED=false` is set in the config.

A graphical session that exists but cannot be measured — a Wayland compositor,
an unreadable Xauthority — counts as *in use*. Powering off a desktop we cannot
see is the one mistake here that cannot be undone.

Day to day you only ever type `b-idle`:

```sh
b-idle          # what it sees right now, and how close it is to powering off
b-idle off      # hold it off until the next reboot
b-idle on       # release that hold
b-idle log      # what it has actually done, from the journal
```

`off` writes into `/run`, a tmpfs, so it cannot outlive a reboot and leave a
machine that silently never powers off again.

Settings live in `/etc/idle-poweroff.conf`, written once on the first install and
never overwritten afterwards — the same idea as the `.local` alias file, so
`boot.sh` re-running the installer can never undo them. Every key is documented
in there; the ones worth knowing are `IDLE_MINUTES`, `LOCKED_MINUTES` and
`MAX_LOAD`. To keep one machine on for good, set `ENABLED=false` there, or
install with `./install.sh --no-idle-poweroff`.

It needs root — it writes a systemd unit and calls `poweroff` — and a machine
booted with systemd. Without either, `install.sh` says so and installs the rest
of the shell config as usual.

If you also run the [i3 config](https://github.com/Spuppateddu/configuration-i3),
its DPMS timer blanks the panel at 50 minutes, ten minutes before this fires — so
a dark screen is the visible warning that the machine is about to go.

## 📄 License

Personal dotfiles — feel free to copy anything useful.
