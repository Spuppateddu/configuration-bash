#!/usr/bin/env bash
# idle-poweroff — powers the machine off once unused: 10 min with the screen
# locked, 1 h otherwise (desktop, greeter or headless). Warns first, then acts.

# Usage: idle-poweroff.sh [--status|--dry-run]   Settings: /etc/idle-poweroff.conf

# Not `set -e`: a machine we cannot measure must be left alone, not powered off.
set -uo pipefail

# ── Defaults, overridable per machine in /etc/idle-poweroff.conf ─────────────
ENABLED=true
IDLE_MINUTES=60
LOCKED_MINUTES=10
WARN_SECONDS=120
# Absolute, not per-core: an idle Linux box sits near 0.00 whatever its cores.
MAX_LOAD=0.5
LOCKERS="i3lock swaylock xsecurelock slock xtrlock"
# Keep true on anything reached over the network, or a headless box powers off
# underneath an ssh session that is merely quiet.
BLOCK_ON_LOGIN_SESSIONS=true

CONF=/etc/idle-poweroff.conf
# shellcheck source=/dev/null
[ -r "$CONF" ] && . "$CONF"

# /run is a tmpfs: the headless counter restarts at boot and `b-idle off` cannot
# outlive a reboot. Both are deliberate.
STATE_DIR=/run/idle-poweroff
IDLE_SINCE="$STATE_DIR/idle-since"
WARNED="$STATE_DIR/warned"
DISABLED="$STATE_DIR/disabled"

MODE=act
case "${1:-}" in
    "")         ;;
    --status)   MODE=status ;;
    --dry-run)  MODE=dry ;;
    -h|--help)  sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'idle-poweroff: unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

IDLE_SECS=$(( IDLE_MINUTES * 60 ))
LOCKED_SECS=$(( LOCKED_MINUTES * 60 ))
NOW=$(date +%s)

has_cmd() { command -v "$1" >/dev/null 2>&1; }
# Journal under the timer, stderr for a human running --status by hand.
log() {
    if [ "$MODE" = act ]; then logger -t idle-poweroff -- "$*"
    else printf '%s\n' "$*" >&2
    fi
}
human() {
    local s=$1
    if [ "$s" -ge 3600 ]; then printf '%dh %02dm' $(( s / 3600 )) $(( s % 3600 / 60 ))
    else printf '%dm %02ds' $(( s / 60 )) $(( s % 60 ))
    fi
}

# ── Probes ───────────────────────────────────────────────────────────────────

# Root-only, and the one reliable source of a session's DISPLAY and XAUTHORITY:
# loginctl's Display is often empty and the greeter's xauth path varies by distro.
environ_of() {
    local pid=$1 var=$2 line
    [ -r "/proc/$pid/environ" ] || return 1
    while IFS= read -r -d '' line; do
        case "$line" in "$var="*) printf '%s\n' "${line#*=}"; return 0 ;; esac
    done < "/proc/$pid/environ"
    return 1
}

# Only `block` mode vetoes; unattended-upgrades holds a permanent `delay` one.
# Both ends of the table are free text, so match WHAT by its fixed vocabulary.
shutdown_inhibited() {
    has_cmd systemd-inhibit || return 1
    systemd-inhibit --list 2>/dev/null | awk '
        $NF == "block" {
            for (i = 1; i < NF; i++)
                if ($i ~ /^[a-z-]+(:[a-z-]+)*$/ && $i ~ /(^|:)shutdown(:|$)/) found = 1
        }
        END { exit !found }'
}

# awk, because the shell cannot compare floats.
load_high() {
    local load1
    load1=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null) || return 1
    awk -v l="$load1" -v m="$MAX_LOAD" 'BEGIN { exit !(l > m) }'
}

# Seconds since the least-idle tty/ssh login last wrote to its terminal — the
# mtime of the tty device, which is exactly what `w` prints as IDLE.
login_idle() {
    [ "$BLOCK_ON_LOGIN_SESSIONS" = true ] || return 1
    has_cmd who || return 1
    local tty mtime idle min=
    while read -r _ tty _; do
        # X sessions appear in utmp as `:0`, which is not a device node.
        case "$tty" in ""|:*) continue ;; esac
        [ -c "/dev/$tty" ] || continue
        mtime=$(stat -c %Y "/dev/$tty" 2>/dev/null) || continue
        idle=$(( NOW - mtime ))
        [ "$idle" -lt 0 ] && idle=0
        if [ -z "$min" ] || [ "$idle" -lt "$min" ]; then min=$idle; fi
    done < <(who 2>/dev/null)
    [ -n "$min" ] || return 1
    printf '%s\n' "$min"
}

# `pgrep -o` takes the OLDEST match, so a respawned child still reports when the
# screen actually went dark.
lock_idle() {
    local name pid secs
    for name in $LOCKERS; do
        pid=$(pgrep -o -x "$name" 2>/dev/null) || continue
        secs=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ') || continue
        [ -n "$secs" ] || continue
        printf '%s\n' "$secs"
        return 0
    done
    return 1
}

# X's own idle timer, in seconds. As root any Xauthority is readable, so the
# greeter's display answers as readily as a logged-in user's.
x_idle() {
    local sid=$1 leader=$2 display xauth ms home user
    has_cmd xprintidle || return 1
    display=$(environ_of "$leader" DISPLAY) \
        || display=$(loginctl show-session "$sid" -p Display --value 2>/dev/null)
    [ -n "$display" ] || return 1
    xauth=$(environ_of "$leader" XAUTHORITY) || xauth=""
    if [ -z "$xauth" ]; then
        user=$(loginctl show-session "$sid" -p Name --value 2>/dev/null)
        home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6)
        [ -n "$home" ] && xauth="$home/.Xauthority"
    fi
    [ -n "$xauth" ] && [ -r "$xauth" ] || return 1
    ms=$(DISPLAY="$display" XAUTHORITY="$xauth" xprintidle 2>/dev/null) || return 1
    case "$ms" in ''|*[!0-9]*) return 1 ;; esac
    printf '%s\n' $(( ms / 1000 ))
}

# ── Collect the checks ───────────────────────────────────────────────────────
# "idle:limit:description" — every check must pass its own limit.
CHECKS=()
BLOCKED=""
GFX_FOUND=false

add_check() { CHECKS+=("$1:$2:$3"); }

if [ "$ENABLED" != true ]; then
    BLOCKED="disabled in $CONF"
elif [ -e "$DISABLED" ]; then
    BLOCKED="disabled until reboot (b-idle off)"
elif load_high; then
    BLOCKED="load average $(cut -d' ' -f1 /proc/loadavg) is above $MAX_LOAD"
elif shutdown_inhibited; then
    BLOCKED="a systemd block inhibitor is holding shutdown"
fi

if [ -z "$BLOCKED" ]; then
    while read -r sid _; do
        [ -n "$sid" ] || continue
        [ "$(loginctl show-session "$sid" -p Active --value 2>/dev/null)" = yes ] || continue
        class=$(loginctl show-session "$sid" -p Class --value 2>/dev/null)
        type=$(loginctl show-session "$sid" -p Type --value 2>/dev/null)
        # `manager` is the per-user systemd instance, not a screen someone sits at.
        case "$class" in user|greeter) ;; *) continue ;; esac
        case "$type" in x11|wayland|mir) ;; *) continue ;; esac
        GFX_FOUND=true
        leader=$(loginctl show-session "$sid" -p Leader --value 2>/dev/null)

        if locked=$(lock_idle); then
            # Locking is the human saying they left, so no need to wait the hour.
            add_check "$locked" "$LOCKED_SECS" "screen locked (session $sid)"
        elif idle=$(x_idle "$sid" "${leader:-0}"); then
            add_check "$idle" "$IDLE_SECS" "$class session $sid idle"
        else
            # Wayland, or an unreachable Xauthority. Powering off a desktop we
            # cannot see is the one mistake here that cannot be undone.
            BLOCKED="cannot read the idle time of $class session $sid — assuming it is in use"
            break
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
fi

if [ -z "$BLOCKED" ] && [ "$GFX_FOUND" = false ]; then
    # Headless: nothing to interrogate, so count from the first quiet check —
    # after a Wake-on-LAN or post-blackout boot that is the first check at all.
    mkdir -p "$STATE_DIR" 2>/dev/null
    [ -f "$IDLE_SINCE" ] || printf '%s\n' "$NOW" > "$IDLE_SINCE" 2>/dev/null
    since=$(cat "$IDLE_SINCE" 2>/dev/null)
    case "$since" in ''|*[!0-9]*) since=$NOW ;; esac
    add_check "$(( NOW - since ))" "$IDLE_SECS" "no graphical session since"
fi

if [ -z "$BLOCKED" ] && lidle=$(login_idle); then
    add_check "$lidle" "$IDLE_SECS" "tty/ssh login last active"
fi

# ── Decide ───────────────────────────────────────────────────────────────────
IDLE_ENOUGH=true
REASON=""
if [ -n "$BLOCKED" ]; then
    IDLE_ENOUGH=false
    REASON="$BLOCKED"
else
    for check in "${CHECKS[@]}"; do
        idle=${check%%:*}; rest=${check#*:}
        limit=${rest%%:*}; desc=${rest#*:}
        if [ "$idle" -lt "$limit" ]; then
            IDLE_ENOUGH=false
            REASON="$desc $(human "$idle") of $(human "$limit")"
            break
        fi
    done
fi

if [ "$MODE" = status ]; then
    if [ "$IDLE_ENOUGH" = true ]; then
        printf 'idle-poweroff: idle past every limit — would power off.\n'
    else
        printf 'idle-poweroff: in use — %s\n' "$REASON"
    fi
    for check in "${CHECKS[@]}"; do
        idle=${check%%:*}; rest=${check#*:}
        limit=${rest%%:*}; desc=${rest#*:}
        printf '  %-42s %8s / %s\n' "$desc" "$(human "$idle")" "$(human "$limit")"
    done
    [ -e "$WARNED" ] && printf '  warning sent, powering off shortly\n'
    exit 0
fi

# ── Act ──────────────────────────────────────────────────────────────────────
if [ "$IDLE_ENOUGH" != true ]; then
    # Drop both bits of state, so the next idle spell is timed from scratch.
    if [ -e "$WARNED" ]; then
        log "activity resumed ($REASON) — poweroff cancelled"
        rm -f "$WARNED"
    fi
    rm -f "$IDLE_SINCE"
    exit 0
fi

mkdir -p "$STATE_DIR" 2>/dev/null

# Best effort throughout: a failed notification must not stop the poweroff, or a
# machine with no desktop would never turn off at all.
warn_everybody() {
    local msg="This machine has been idle and will power off in $(human "$WARN_SECONDS"). Move the mouse or press a key to cancel."
    has_cmd wall && printf '%s\n' "$msg" | wall -n 2>/dev/null
    has_cmd notify-send && has_cmd runuser || return 0
    local sid uid user leader bus display xauth
    while read -r sid _; do
        [ -n "$sid" ] || continue
        # A greeter has no notification daemon and nobody to notify.
        [ "$(loginctl show-session "$sid" -p Class --value 2>/dev/null)" = user ] || continue
        # runuser resolves through getpwnam and rejects sudo's `#1000` spelling.
        user=$(loginctl show-session "$sid" -p Name --value 2>/dev/null)
        uid=$(loginctl show-session "$sid" -p User --value 2>/dev/null)
        leader=$(loginctl show-session "$sid" -p Leader --value 2>/dev/null)
        [ -n "$user" ] && [ -n "$leader" ] || continue
        display=$(environ_of "$leader" DISPLAY) \
            || display=$(loginctl show-session "$sid" -p Display --value 2>/dev/null)
        [ -n "$display" ] || display=":0"
        xauth=$(environ_of "$leader" XAUTHORITY) || xauth="/home/$user/.Xauthority"
        # The per-user bus is at a fixed path, so the fallback is as good.
        bus=$(environ_of "$leader" DBUS_SESSION_BUS_ADDRESS) \
            || bus="unix:path=/run/user/${uid:-0}/bus"
        runuser -u "$user" -- env \
            DISPLAY="$display" XAUTHORITY="$xauth" \
            DBUS_SESSION_BUS_ADDRESS="$bus" \
            notify-send -u critical -t "$(( WARN_SECONDS * 1000 ))" \
                "Powering off" "$msg" 2>/dev/null
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
    return 0
}

if [ ! -e "$WARNED" ]; then
    log "idle past every limit — warning, then powering off in ${WARN_SECONDS}s"
    printf '%s\n' "$NOW" > "$WARNED" 2>/dev/null
    [ "$MODE" = dry ] || warn_everybody
    exit 0
fi

warned_at=$(cat "$WARNED" 2>/dev/null)
case "$warned_at" in ''|*[!0-9]*) warned_at=$NOW ;; esac
if [ $(( NOW - warned_at )) -lt "$WARN_SECONDS" ]; then
    exit 0
fi

if [ "$MODE" = dry ]; then
    printf 'idle-poweroff: dry run — would power off now.\n'
    exit 0
fi

log "still idle after the warning — powering off"
rm -f "$WARNED" "$IDLE_SINCE"
systemctl poweroff
