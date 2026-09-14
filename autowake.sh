#!/bin/sh

# AutoWake: schedule an RTC wake alarm before asking systemd to suspend.

set -u

PROGRAM=${0##*/}
CONFIG_FILE=${AUTOWAKE_CONFIG:-/etc/autowake.conf}
WAKE_HOOK_DIR=${AUTOWAKE_WAKE_HOOK_DIR:-/etc/autowake/wake.d}
WINDOW_SECONDS=300

error()
{
    printf '%s: %s\n' "$PROGRAM" "$*" >&2
}

trim()
{
    # Configuration values are short and deliberately exclude newlines.
    printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

weekday_number()
{
    case $1 in
        Mon) printf '%s\n' 1 ;;
        Tue) printf '%s\n' 2 ;;
        Wed) printf '%s\n' 3 ;;
        Thu) printf '%s\n' 4 ;;
        Fri) printf '%s\n' 5 ;;
        Sat) printf '%s\n' 6 ;;
        Sun) printf '%s\n' 7 ;;
        *) return 1 ;;
    esac
}

validate_time()
{
    case $1 in
        [0-2][0-9]:[0-5][0-9]) ;;
        *) return 1 ;;
    esac
    hour=${1%:*}
    [ "$hour" -le 23 ]
}

load_config()
{
    SUSPEND_WEEKDAY=
    SUSPEND_TIME=
    WAKE_WEEKDAY=
    WAKE_TIME=
    RTC_DEVICE=
    seen_suspend_weekday=false
    seen_suspend_time=false
    seen_wake_weekday=false
    seen_wake_time=false
    seen_rtc_device=false

    if [ ! -r "$CONFIG_FILE" ]; then
        error "cannot read configuration: $CONFIG_FILE"
        return 1
    fi

    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        line=$(trim "$raw_line")
        case $line in
            ''|'#'*) continue ;;
            *=*) ;;
            *) error "invalid configuration line: $raw_line"; return 1 ;;
        esac

        key=$(trim "${line%%=*}")
        value=$(trim "${line#*=}")
        case $key in
            SUSPEND_WEEKDAY)
                $seen_suspend_weekday && { error "duplicate setting: $key"; return 1; }
                SUSPEND_WEEKDAY=$value; seen_suspend_weekday=true ;;
            SUSPEND_TIME)
                $seen_suspend_time && { error "duplicate setting: $key"; return 1; }
                SUSPEND_TIME=$value; seen_suspend_time=true ;;
            WAKE_WEEKDAY)
                $seen_wake_weekday && { error "duplicate setting: $key"; return 1; }
                WAKE_WEEKDAY=$value; seen_wake_weekday=true ;;
            WAKE_TIME)
                $seen_wake_time && { error "duplicate setting: $key"; return 1; }
                WAKE_TIME=$value; seen_wake_time=true ;;
            RTC_DEVICE)
                $seen_rtc_device && { error "duplicate setting: $key"; return 1; }
                RTC_DEVICE=$value; seen_rtc_device=true ;;
            *) error "unknown configuration setting: $key"; return 1 ;;
        esac
    done < "$CONFIG_FILE"

    if ! suspend_day=$(weekday_number "$SUSPEND_WEEKDAY"); then
        error "SUSPEND_WEEKDAY must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun"
        return 1
    fi
    if ! wake_day=$(weekday_number "$WAKE_WEEKDAY"); then
        error "WAKE_WEEKDAY must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun"
        return 1
    fi
    if ! validate_time "$SUSPEND_TIME"; then
        error "SUSPEND_TIME must be a 24-hour time in HH:MM format"
        return 1
    fi
    if ! validate_time "$WAKE_TIME"; then
        error "WAKE_TIME must be a 24-hour time in HH:MM format"
        return 1
    fi
    case $RTC_DEVICE in
        /dev/?*) ;;
        *) error "RTC_DEVICE must be an absolute path below /dev"; return 1 ;;
    esac
}

now_epoch()
{
    if [ "${AUTOWAKE_NOW_EPOCH+x}" = x ]; then
        case $AUTOWAKE_NOW_EPOCH in
            ''|*[!0-9]*) error "AUTOWAKE_NOW_EPOCH must be a non-negative integer"; return 1 ;;
        esac
        printf '%s\n' "$AUTOWAKE_NOW_EPOCH"
    else
        date +%s
    fi
}

local_epoch()
{
    expected_date=$1
    expected_time=$2
    if ! result=$(date -d "$expected_date $expected_time" +%s 2>/dev/null); then
        error "local time does not exist: $expected_date $expected_time"
        return 1
    fi
    # Reject GNU date's normalization of nonexistent local times during DST jumps.
    if [ "$(date -d "@$result" '+%F %H:%M')" != "$expected_date $expected_time" ]; then
        error "local time was normalized and is not usable: $expected_date $expected_time"
        return 1
    fi
    printf '%s\n' "$result"
}

date_plus_days()
{
    # A leading plus next to a clock can be parsed as a numeric timezone.
    day_offset=${2#+}
    date -d "$1 $day_offset days 12:00" +%F
}

next_suspend_epoch()
{
    current=$1
    current_day=$(date -d "@$current" +%u) || return 1
    current_date=$(date -d "@$current" +%F) || return 1
    days=$(( (suspend_day - current_day + 7) % 7 ))
    target_date=$(date_plus_days "$current_date" "+$days") || return 1
    candidate=$(local_epoch "$target_date" "$SUSPEND_TIME") || return 1
    if [ "$candidate" -lt "$current" ]; then
        target_date=$(date_plus_days "$target_date" +7) || return 1
        candidate=$(local_epoch "$target_date" "$SUSPEND_TIME") || return 1
    fi
    printf '%s\n' "$candidate"
}

previous_suspend_epoch()
{
    current=$1
    current_day=$(date -d "@$current" +%u) || return 1
    current_date=$(date -d "@$current" +%F) || return 1
    days=$(( (current_day - suspend_day + 7) % 7 ))
    target_date=$(date_plus_days "$current_date" "-$days") || return 1
    candidate=$(local_epoch "$target_date" "$SUSPEND_TIME") || return 1
    if [ "$candidate" -gt "$current" ]; then
        target_date=$(date_plus_days "$target_date" -7) || return 1
        candidate=$(local_epoch "$target_date" "$SUSPEND_TIME") || return 1
    fi
    printf '%s\n' "$candidate"
}

wake_after_suspend_epoch()
{
    suspend_epoch=$1
    suspend_date=$(date -d "@$suspend_epoch" +%F) || return 1
    days=$(( (wake_day - suspend_day + 7) % 7 ))
    wake_date=$(date_plus_days "$suspend_date" "+$days") || return 1
    candidate=$(local_epoch "$wake_date" "$WAKE_TIME") || return 1
    if [ "$candidate" -le "$suspend_epoch" ]; then
        wake_date=$(date_plus_days "$wake_date" +7) || return 1
        candidate=$(local_epoch "$wake_date" "$WAKE_TIME") || return 1
    fi
    printf '%s\n' "$candidate"
}

format_epoch()
{
    date -d "@$1" '+%Y-%m-%d %H:%M:%S %Z (%z)'
}

command_exists()
{
    command -v "$1" >/dev/null 2>&1
}

run_wake_hooks()
{
    hook_status=0
    [ -d "$WAKE_HOOK_DIR" ] || return 0

    for hook in "$WAKE_HOOK_DIR"/*; do
        [ -f "$hook" ] && [ -x "$hook" ] || continue
        printf 'Running wake hook: %s\n' "${hook##*/}"
        if ! "$hook"; then
            error "wake hook failed: $hook"
            hook_status=1
        fi
    done
    return "$hook_status"
}

do_preview()
{
    load_config || return 1
    current=$(now_epoch) || return 1
    suspend_epoch=$(next_suspend_epoch "$current") || return 1
    wake_epoch=$(wake_after_suspend_epoch "$suspend_epoch") || return 1
    printf 'Next suspend: %s\n' "$(format_epoch "$suspend_epoch")"
    printf 'Next wake:    %s\n' "$(format_epoch "$wake_epoch")"
    printf 'RTC device:   %s\n' "$RTC_DEVICE"
}

do_check()
{
    status=0
    if load_config; then
        printf 'Configuration: valid (%s)\n' "$CONFIG_FILE"
    else
        status=1
    fi

    for dependency in date sed grep rtcwake systemctl; do
        if command_exists "$dependency"; then
            printf 'Dependency:    %s found\n' "$dependency"
        else
            error "required command not found: $dependency"
            status=1
        fi
    done

    if [ -n "${RTC_DEVICE:-}" ] && [ -e "$RTC_DEVICE" ]; then
        printf 'RTC device:    %s exists\n' "$RTC_DEVICE"
    else
        error "RTC device does not exist: ${RTC_DEVICE:-unknown}"
        status=1
    fi

    if [ -r /sys/power/state ] && grep -Eq '(^|[[:space:]])mem([[:space:]]|$)' /sys/power/state; then
        printf 'Suspend state: mem advertised by kernel\n'
    else
        error "kernel does not advertise the mem suspend state"
        status=1
    fi

    printf '%s\n' 'Hardware wake reliability requires a manual short test and full-interval test.'
    return "$status"
}

do_run()
{
    load_config || return 1
    for dependency in date rtcwake systemctl; do
        if ! command_exists "$dependency"; then
            error "required command not found: $dependency"
            return 1
        fi
    done
    current=$(now_epoch) || return 1
    scheduled=$(previous_suspend_epoch "$current") || return 1
    delay=$((current - scheduled))
    if [ "$delay" -lt 0 ]; then
        error "refusing suspend before the scheduled time"
        return 1
    fi
    if [ "$delay" -gt "$WINDOW_SECONDS" ]; then
        error "skipping suspend: execution is ${delay}s after the scheduled time (limit ${WINDOW_SECONDS}s)"
        return 0
    fi
    wake_epoch=$(wake_after_suspend_epoch "$scheduled") || return 1
    printf 'Arming RTC wake for %s\n' "$(format_epoch "$wake_epoch")"
    if ! rtcwake -m no -d "$RTC_DEVICE" -t "$wake_epoch"; then
        error "failed to arm RTC wake alarm; suspend aborted"
        return 1
    fi
    printf '%s\n' 'RTC wake alarm armed; requesting suspend through systemd'
    if ! systemctl suspend; then
        error "systemctl suspend failed"
        return 1
    fi
    printf '%s\n' 'System resumed; running wake hooks'
    run_wake_hooks
}

usage()
{
    printf 'Usage: %s {check|preview|run}\n' "$PROGRAM" >&2
}

case ${1:-} in
    check) [ "$#" -eq 1 ] || { usage; exit 2; }; do_check ;;
    preview) [ "$#" -eq 1 ] || { usage; exit 2; }; do_preview ;;
    run) [ "$#" -eq 1 ] || { usage; exit 2; }; do_run ;;
    *) usage; exit 2 ;;
esac
