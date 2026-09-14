#!/bin/sh

set -eu

PROGRAM=${0##*/}
ROOT=
KEEP_CONFIG=false

usage()
{
    printf 'Usage: %s [--keep-config] [--root DIRECTORY]\n' "$PROGRAM" >&2
}

while [ "$#" -gt 0 ]; do
    case $1 in
        --keep-config)
            KEEP_CONFIG=true
            shift
            ;;
        --root)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            ROOT=${2%/}
            [ -n "$ROOT" ] || ROOT=/
            case $ROOT in
                /*) ;;
                *) printf '%s: --root must be an absolute path\n' "$PROGRAM" >&2; exit 2 ;;
            esac
            [ "$ROOT" != / ] || {
                printf '%s: --root / is not an isolated staging path\n' "$PROGRAM" >&2
                exit 2
            }
            shift 2
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if [ -z "$ROOT" ] && [ "$(id -u)" -ne 0 ]; then
    printf '%s: removal requires root privileges\n' "$PROGRAM" >&2
    exit 1
fi

UNIT_DIR="$ROOT/etc/systemd/system"
BIN_DIR="$ROOT/usr/local/sbin"
CONFIG_PATH="$ROOT/etc/autowake.conf"

if [ -z "$ROOT" ] && [ -e "$UNIT_DIR/autowake.timer" ]; then
    if ! systemctl disable --now autowake.timer; then
        printf '%s: could not disable autowake.timer; no files were removed\n' "$PROGRAM" >&2
        exit 1
    fi
fi

rm -f -- \
    "$UNIT_DIR/autowake.timer" \
    "$UNIT_DIR/autowake.service" \
    "$BIN_DIR/autowake" \
    "$BIN_DIR/autowake-uninstall"

if $KEEP_CONFIG; then
    printf 'Configuration preserved: %s\n' "$CONFIG_PATH"
else
    rm -f -- "$CONFIG_PATH"
fi

if [ -z "$ROOT" ]; then
    systemctl daemon-reload
    systemctl reset-failed autowake.service >/dev/null 2>&1 || true
fi

printf '%s\n' 'AutoWake removed.'
