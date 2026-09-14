#!/bin/sh

set -eu

PROGRAM=${0##*/}
ROOT=

usage()
{
    printf 'Usage: %s [--root DIRECTORY]\n' "$PROGRAM" >&2
}

case $# in
    0) ;;
    2)
        [ "$1" = --root ] || { usage; exit 2; }
        ROOT=${2%/}
        [ -n "$ROOT" ] || ROOT=/
        case $ROOT in /*) ;; *) printf '%s: --root must be an absolute path\n' "$PROGRAM" >&2; exit 2 ;; esac
        [ "$ROOT" != / ] || { printf '%s: --root / is not an isolated staging path\n' "$PROGRAM" >&2; exit 2; }
        ;;
    *) usage; exit 2 ;;
esac

if [ -z "$ROOT" ] && [ "$(id -u)" -ne 0 ]; then
    printf '%s: installation requires root privileges\n' "$PROGRAM" >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CONFIG_PATH="$ROOT/etc/autowake.conf"
BIN_DIR="$ROOT/usr/local/sbin"
UNIT_DIR="$ROOT/etc/systemd/system"
WAKE_HOOK_DIR="$ROOT/etc/autowake/wake.d"

install -d -m 0755 "$BIN_DIR" "$UNIT_DIR" "$WAKE_HOOK_DIR" "$(dirname "$CONFIG_PATH")"
install -m 0755 "$SCRIPT_DIR/autowake.sh" "$BIN_DIR/autowake"
install -m 0755 "$SCRIPT_DIR/uninstall.sh" "$BIN_DIR/autowake-uninstall"
if [ ! -e "$CONFIG_PATH" ]; then
    install -m 0644 "$SCRIPT_DIR/autowake.conf" "$CONFIG_PATH"
    printf 'Installed default configuration at %s\n' "$CONFIG_PATH"
else
    printf 'Preserved existing configuration at %s\n' "$CONFIG_PATH"
fi

# preview validates every setting without touching the RTC or power state.
preview_output=$(AUTOWAKE_CONFIG="$CONFIG_PATH" "$SCRIPT_DIR/autowake.sh" preview) || {
    printf '%s: configuration is invalid; systemd units were not updated\n' "$PROGRAM" >&2
    exit 1
}

SUSPEND_WEEKDAY=$(sed -n 's/^[[:space:]]*SUSPEND_WEEKDAY[[:space:]]*=[[:space:]]*\([^[:space:]#]*\)[[:space:]]*$/\1/p' "$CONFIG_PATH")
SUSPEND_TIME=$(sed -n 's/^[[:space:]]*SUSPEND_TIME[[:space:]]*=[[:space:]]*\([^[:space:]#]*\)[[:space:]]*$/\1/p' "$CONFIG_PATH")

service_tmp=$(mktemp "$UNIT_DIR/.autowake.service.XXXXXX")
timer_tmp=$(mktemp "$UNIT_DIR/.autowake.timer.XXXXXX")
cleanup()
{
    rm -f "$service_tmp" "$timer_tmp"
}
trap cleanup EXIT HUP INT TERM

sed "s|@AUTOWAKE_BIN@|/usr/local/sbin/autowake|g" "$SCRIPT_DIR/systemd/autowake.service.in" > "$service_tmp"
sed -e "s/@SUSPEND_WEEKDAY@/$SUSPEND_WEEKDAY/g" -e "s/@SUSPEND_TIME@/$SUSPEND_TIME/g" "$SCRIPT_DIR/systemd/autowake.timer.in" > "$timer_tmp"
chmod 0644 "$service_tmp" "$timer_tmp"
mv "$service_tmp" "$UNIT_DIR/autowake.service"
mv "$timer_tmp" "$UNIT_DIR/autowake.timer"
trap - EXIT HUP INT TERM

if [ -z "$ROOT" ]; then
    chown root:root "$BIN_DIR/autowake" "$BIN_DIR/autowake-uninstall" \
        "$CONFIG_PATH" "$UNIT_DIR/autowake.service" "$UNIT_DIR/autowake.timer" \
        "$ROOT/etc/autowake" "$WAKE_HOOK_DIR"
    systemctl daemon-reload
fi

printf '%s\n' "$preview_output"
printf '%s\n' 'AutoWake installed. The installer did not enable or start scheduling.'
printf '%s\n' 'After hardware validation, enable it with: systemctl enable --now autowake.timer'
