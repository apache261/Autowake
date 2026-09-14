#!/bin/sh

set -u

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM
PASS=0
FAIL=0

pass()
{
    PASS=$((PASS + 1))
    printf 'ok %d - %s\n' "$((PASS + FAIL))" "$1"
}

fail()
{
    FAIL=$((FAIL + 1))
    printf 'not ok %d - %s\n' "$((PASS + FAIL))" "$1"
}

contains()
{
    case $1 in *"$2"*) return 0 ;; *) return 1 ;; esac
}

default_config()
{
    config_file=$1
    cp "$PROJECT_DIR/autowake.conf" "$config_file"
}

run_preview_test()
{
    name=$1
    zone=$2
    now_text=$3
    suspend_text=$4
    wake_text=$5
    config="$TEST_TMP/config"
    default_config "$config"
    now=$(TZ="$zone" date -d "$now_text" +%s)
    if output=$(TZ="$zone" AUTOWAKE_CONFIG="$config" AUTOWAKE_NOW_EPOCH="$now" \
        "$PROJECT_DIR/autowake.sh" preview 2>&1) &&
        contains "$output" "$suspend_text" && contains "$output" "$wake_text"; then
        pass "$name"
    else
        printf '%s\n' "$output" >&2
        fail "$name"
    fi
}

printf '1..21\n'

run_preview_test 'week and year boundary' UTC '2026-12-31 12:00' \
    '2027-01-01 19:00:00 UTC' '2027-01-04 06:00:00 UTC'
run_preview_test 'month boundary' UTC '2026-04-30 23:00' \
    '2026-05-01 19:00:00 UTC' '2026-05-04 06:00:00 UTC'
run_preview_test 'passed schedule selects next week' UTC '2026-05-01 19:01' \
    '2026-05-08 19:00:00 UTC' '2026-05-11 06:00:00 UTC'
run_preview_test 'spring DST uses local calendar times' America/New_York '2026-03-05 12:00' \
    '2026-03-06 19:00:00 EST' '2026-03-09 06:00:00 EDT'
run_preview_test 'autumn DST uses local calendar times' America/New_York '2026-10-29 12:00' \
    '2026-10-30 19:00:00 EDT' '2026-11-02 06:00:00 EST'

config="$TEST_TMP/config"
default_config "$config"
sed 's/SUSPEND_TIME=19:00/SUSPEND_TIME=25:00/' "$config" > "$TEST_TMP/invalid"
if output=$(AUTOWAKE_CONFIG="$TEST_TMP/invalid" "$PROJECT_DIR/autowake.sh" preview 2>&1); then
    fail 'invalid configuration is rejected'
elif contains "$output" 'SUSPEND_TIME must be'; then
    pass 'invalid configuration is rejected'
else
    printf '%s\n' "$output" >&2
    fail 'invalid configuration is rejected'
fi

MOCK_BIN="$TEST_TMP/mock-bin"
mkdir "$MOCK_BIN"
cat > "$MOCK_BIN/rtcwake" <<'EOF'
#!/bin/sh
printf 'rtcwake %s\n' "$*" >> "$AUTOWAKE_TEST_LOG"
exit "${MOCK_RTCWAKE_STATUS:-0}"
EOF
cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl %s\n' "$*" >> "$AUTOWAKE_TEST_LOG"
exit "${MOCK_SYSTEMCTL_STATUS:-0}"
EOF
chmod +x "$MOCK_BIN/rtcwake" "$MOCK_BIN/systemctl"
MOCK_PATH="$MOCK_BIN:/usr/bin:/bin"
log="$TEST_TMP/power.log"

: > "$log"
if output=$(TZ=UTC PATH="$MOCK_PATH" AUTOWAKE_CONFIG="$TEST_TMP/invalid" \
    AUTOWAKE_NOW_EPOCH=0 AUTOWAKE_TEST_LOG="$log" "$PROJECT_DIR/autowake.sh" run 2>&1); then
    fail 'invalid configuration prevents power actions'
elif [ ! -s "$log" ] && contains "$output" 'SUSPEND_TIME must be'; then
    pass 'invalid configuration prevents power actions'
else
    fail 'invalid configuration prevents power actions'
fi

: > "$log"
scheduled=$(TZ=UTC date -d '2026-01-02 19:00:00' +%s)
expected_wake=$(TZ=UTC date -d '2026-01-05 06:00:00' +%s)
if TZ=UTC PATH="$MOCK_PATH" AUTOWAKE_CONFIG="$config" AUTOWAKE_NOW_EPOCH="$scheduled" \
    AUTOWAKE_TEST_LOG="$log" "$PROJECT_DIR/autowake.sh" run >/dev/null 2>&1 &&
    [ "$(sed -n '1p' "$log")" = "rtcwake -m no -d /dev/rtc0 -t $expected_wake" ] &&
    [ "$(sed -n '2p' "$log")" = 'systemctl suspend' ]; then
    pass 'alarm is armed before suspend'
else
    fail 'alarm is armed before suspend'
fi

: > "$log"
if TZ=UTC PATH="$MOCK_PATH" AUTOWAKE_CONFIG="$config" AUTOWAKE_NOW_EPOCH="$((scheduled + 300))" \
    AUTOWAKE_TEST_LOG="$log" "$PROJECT_DIR/autowake.sh" run >/dev/null 2>&1 &&
    contains "$(cat "$log")" 'systemctl suspend'; then
    pass 'five-minute boundary is allowed'
else
    fail 'five-minute boundary is allowed'
fi

: > "$log"
if output=$(TZ=UTC PATH="$MOCK_PATH" AUTOWAKE_CONFIG="$config" AUTOWAKE_NOW_EPOCH="$((scheduled + 301))" \
    AUTOWAKE_TEST_LOG="$log" "$PROJECT_DIR/autowake.sh" run 2>&1) &&
    [ ! -s "$log" ] && contains "$output" 'skipping suspend'; then
    pass 'late run is skipped without power actions'
else
    fail 'late run is skipped without power actions'
fi

: > "$log"
if output=$(TZ=UTC PATH="$MOCK_PATH" AUTOWAKE_CONFIG="$config" AUTOWAKE_NOW_EPOCH="$scheduled" \
    AUTOWAKE_TEST_LOG="$log" MOCK_RTCWAKE_STATUS=1 "$PROJECT_DIR/autowake.sh" run 2>&1); then
    fail 'alarm failure prevents suspend'
elif [ "$(wc -l < "$log")" -eq 1 ] && contains "$output" 'suspend aborted'; then
    pass 'alarm failure prevents suspend'
else
    fail 'alarm failure prevents suspend'
fi

: > "$log"
if output=$(TZ=UTC PATH="$MOCK_PATH" AUTOWAKE_CONFIG="$config" AUTOWAKE_NOW_EPOCH="$scheduled" \
    AUTOWAKE_TEST_LOG="$log" MOCK_SYSTEMCTL_STATUS=1 "$PROJECT_DIR/autowake.sh" run 2>&1); then
    fail 'suspend command failure is propagated'
elif [ "$(wc -l < "$log")" -eq 2 ] && contains "$output" 'systemctl suspend failed'; then
    pass 'suspend command failure is propagated'
else
    fail 'suspend command failure is propagated'
fi

success_hooks="$TEST_TMP/hooks-success"
mkdir "$success_hooks"
cat > "$success_hooks/10-first" <<'EOF'
#!/bin/sh
printf '%s\n' 'hook first' >> "$AUTOWAKE_TEST_LOG"
EOF
cat > "$success_hooks/20-second" <<'EOF'
#!/bin/sh
printf '%s\n' 'hook second' >> "$AUTOWAKE_TEST_LOG"
EOF
printf '%s\n' 'not executable' > "$success_hooks/15-ignore"
chmod +x "$success_hooks/10-first" "$success_hooks/20-second"
: > "$log"
if TZ=UTC PATH="$MOCK_PATH" AUTOWAKE_CONFIG="$config" AUTOWAKE_NOW_EPOCH="$scheduled" \
    AUTOWAKE_TEST_LOG="$log" AUTOWAKE_WAKE_HOOK_DIR="$success_hooks" \
    "$PROJECT_DIR/autowake.sh" run >/dev/null 2>&1 &&
    [ "$(sed -n '1p' "$log")" = "rtcwake -m no -d /dev/rtc0 -t $expected_wake" ] &&
    [ "$(sed -n '2p' "$log")" = 'systemctl suspend' ] &&
    [ "$(sed -n '3p' "$log")" = 'hook first' ] &&
    [ "$(sed -n '4p' "$log")" = 'hook second' ] &&
    [ "$(wc -l < "$log")" -eq 4 ]; then
    pass 'executable wake hooks run in filename order after resume'
else
    fail 'executable wake hooks run in filename order after resume'
fi

failure_hooks="$TEST_TMP/hooks-failure"
mkdir "$failure_hooks"
cat > "$failure_hooks/10-fail" <<'EOF'
#!/bin/sh
printf '%s\n' 'hook failed' >> "$AUTOWAKE_TEST_LOG"
exit 1
EOF
cat > "$failure_hooks/20-after" <<'EOF'
#!/bin/sh
printf '%s\n' 'hook after failure' >> "$AUTOWAKE_TEST_LOG"
EOF
chmod +x "$failure_hooks/10-fail" "$failure_hooks/20-after"
: > "$log"
if output=$(TZ=UTC PATH="$MOCK_PATH" AUTOWAKE_CONFIG="$config" AUTOWAKE_NOW_EPOCH="$scheduled" \
    AUTOWAKE_TEST_LOG="$log" AUTOWAKE_WAKE_HOOK_DIR="$failure_hooks" \
    "$PROJECT_DIR/autowake.sh" run 2>&1); then
    fail 'wake hook failures are reported after remaining hooks run'
elif contains "$output" 'wake hook failed' &&
    [ "$(sed -n '4p' "$log")" = 'hook after failure' ]; then
    pass 'wake hook failures are reported after remaining hooks run'
else
    fail 'wake hook failures are reported after remaining hooks run'
fi

: > "$log"
now=$(TZ=UTC date -d '2026-01-01 12:00:00' +%s)
if TZ=UTC PATH="$MOCK_PATH" AUTOWAKE_CONFIG="$config" AUTOWAKE_NOW_EPOCH="$now" \
    AUTOWAKE_TEST_LOG="$log" "$PROJECT_DIR/autowake.sh" preview >/dev/null 2>&1 && [ ! -s "$log" ]; then
    pass 'preview has no power-management side effects'
else
    fail 'preview has no power-management side effects'
fi

: > "$log"
PATH="$MOCK_PATH" AUTOWAKE_CONFIG="$config" AUTOWAKE_TEST_LOG="$log" \
    "$PROJECT_DIR/autowake.sh" check >/dev/null 2>&1 || true
if [ ! -s "$log" ]; then
    pass 'check has no power-management side effects'
else
    fail 'check has no power-management side effects'
fi

stage="$TEST_TMP/stage"
mkdir "$stage"
if "$PROJECT_DIR/install.sh" --root "$stage" >/dev/null 2>&1 &&
    [ -x "$stage/usr/local/sbin/autowake" ] &&
    [ -x "$stage/usr/local/sbin/autowake-uninstall" ] &&
    [ -d "$stage/etc/autowake/wake.d" ] &&
    [ -f "$stage/etc/systemd/system/autowake.timer" ] &&
    contains "$(cat "$stage/etc/systemd/system/autowake.timer")" 'OnCalendar=Fri *-*-* 19:00:00' &&
    [ ! -e "$stage/etc/systemd/system/timers.target.wants/autowake.timer" ]; then
    pass 'staged install generates units and remains disabled'
else
    fail 'staged install generates units and remains disabled'
fi

sed 's/SUSPEND_TIME=19:00/SUSPEND_TIME=20:15/' "$stage/etc/autowake.conf" > "$TEST_TMP/changed"
mv "$TEST_TMP/changed" "$stage/etc/autowake.conf"
if "$PROJECT_DIR/install.sh" --root "$stage" >/dev/null 2>&1 &&
    contains "$(cat "$stage/etc/systemd/system/autowake.timer")" 'OnCalendar=Fri *-*-* 20:15:00'; then
    pass 'reinstall preserves configuration and regenerates timer'
else
    fail 'reinstall preserves configuration and regenerates timer'
fi

if "$stage/usr/local/sbin/autowake-uninstall" --root "$stage" >/dev/null 2>&1 &&
    [ ! -e "$stage/usr/local/sbin/autowake" ] &&
    [ ! -e "$stage/usr/local/sbin/autowake-uninstall" ] &&
    [ ! -e "$stage/etc/autowake.conf" ] &&
    [ ! -e "$stage/etc/systemd/system/autowake.service" ] &&
    [ ! -e "$stage/etc/systemd/system/autowake.timer" ]; then
    pass 'staged uninstall removes installed files'
else
    fail 'staged uninstall removes installed files'
fi

if "$PROJECT_DIR/install.sh" --root "$stage" >/dev/null 2>&1 &&
    "$stage/usr/local/sbin/autowake-uninstall" --keep-config --root "$stage" >/dev/null 2>&1 &&
    [ -f "$stage/etc/autowake.conf" ] &&
    [ ! -e "$stage/usr/local/sbin/autowake" ] &&
    [ ! -e "$stage/etc/systemd/system/autowake.timer" ]; then
    pass 'uninstall can preserve configuration'
else
    fail 'uninstall can preserve configuration'
fi

if "$PROJECT_DIR/install.sh" --root "$stage" >/dev/null 2>&1; then
    printf '%s\n' '#!/bin/sh' > "$stage/etc/autowake/wake.d/10-custom"
    chmod +x "$stage/etc/autowake/wake.d/10-custom"
fi
if "$stage/usr/local/sbin/autowake-uninstall" --root "$stage" >/dev/null 2>&1 &&
    [ -x "$stage/etc/autowake/wake.d/10-custom" ]; then
    pass 'uninstall preserves custom wake hooks'
else
    fail 'uninstall preserves custom wake hooks'
fi

if [ "$FAIL" -ne 0 ]; then
    printf '# %d passed; %d failed\n' "$PASS" "$FAIL"
    exit 1
fi
printf '# all %d tests passed\n' "$PASS"
