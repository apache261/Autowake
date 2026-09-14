# AutoWake

**Scheduled suspend and automatic wake-up for Linux servers.**

AutoWake is a lightweight POSIX shell utility that uses a systemd timer to
suspend a physical Ubuntu/Debian server and a hardware real-time clock (RTC)
alarm to resume it.

## Status

AutoWake is complete and ready for installation. The timer is intentionally
left disabled during installation so hardware wake support can be validated on
the target server before activation.

## Default schedule

| Action | Time |
| --- | --- |
| Suspend | Every Friday at 19:00 |
| Wake | Every Monday at 06:00 |
| Timezone | Server's configured local timezone |
| RTC device | `/dev/rtc0` |

AutoWake calculates calendar dates in local time, so the elapsed weekend can be
58, 59, or 60 hours when the timezone offset changes.

## Requirements

- A physical Ubuntu/Debian server running systemd.
- GNU `date`, `sed`, `grep`, util-linux (`rtcwake`), and systemd.
- Firmware and hardware support for suspend-to-RAM and RTC wake alarms.
- Root access for installation, alarm setup, and suspension.

Suspend-to-RAM requires continued power. AutoWake resumes a suspended machine;
it cannot turn on a machine that has lost or disconnected power.

## Install

Review the default configuration, then install from the repository root:

```sh
cat autowake.conf
sudo ./install.sh
```

The installer places:

- `autowake` in `/usr/local/sbin`
- `autowake-uninstall` in `/usr/local/sbin`
- configuration in `/etc/autowake.conf`
- units in `/etc/systemd/system/autowake.service` and
  `/etc/systemd/system/autowake.timer`

An existing configuration is preserved. The installer regenerates the timer
from that configuration and reloads systemd. It does not enable or start the
timer, so a new installation cannot immediately suspend the server.

For an isolated package-style installation test, use an absolute staging path:

```sh
./install.sh --root /tmp/autowake-stage
```

This mode writes only below the staging path and does not call systemctl.

## Commands

```sh
sudo /usr/local/sbin/autowake check
/usr/local/sbin/autowake preview
sudo /usr/local/sbin/autowake run
```

- `check` validates configuration, looks for dependencies, the RTC device, and
  the kernel's `mem` suspend interface. It does not set an alarm or suspend.
- `preview` prints the next suspend and its associated wake time. It has no
  power-management side effects.
- `run` is intended for the timer. It only acts during the five minutes after a
  scheduled suspend, arms the alarm first, and then calls `systemctl suspend`.

Do not invoke `run` on a production server merely as a diagnostic: when called
inside its execution window it will suspend the machine.

## Configure

`/etc/autowake.conf` uses unquoted `KEY=value` entries:

```ini
SUSPEND_WEEKDAY=Fri
SUSPEND_TIME=19:00
WAKE_WEEKDAY=Mon
WAKE_TIME=06:00
RTC_DEVICE=/dev/rtc0
```

Weekdays are `Mon` through `Sun`; times must use 24-hour `HH:MM` format. The RTC
device must be an absolute path below `/dev`.

After editing the configuration, preview it and rerun the installer to
regenerate the timer's `OnCalendar` setting:

```sh
/usr/local/sbin/autowake preview
sudo ./install.sh
systemctl cat autowake.timer
```

## Validate and enable

First run non-invasive checks on the target server:

```sh
sudo /usr/local/sbin/autowake check
/usr/local/sbin/autowake preview
timedatectl
```

During a maintenance window, test the hardware with a short direct suspend and
wake cycle (the following example requests a wake after two minutes):

```sh
sudo rtcwake -m mem -d /dev/rtc0 -s 120
```

Confirm that the machine resumes and its services recover. A short test does
not establish that the RTC supports the full weekend alarm range. Test the full
configured interval on the target hardware before relying on AutoWake.

After hardware validation, enable scheduling explicitly:

```sh
sudo systemctl enable --now autowake.timer
systemctl list-timers autowake.timer
```

If the server wakes early for any reason, AutoWake leaves it awake until the
next scheduled suspension.

## Operate and troubleshoot

```sh
systemctl status autowake.timer
systemctl list-timers autowake.timer
journalctl -u autowake.service
sudo systemctl disable --now autowake.timer
```

An invalid configuration or failed `rtcwake` command prevents suspension. Runs
delivered more than five minutes late are logged and skipped. The timer uses
`Persistent=false`, so a missed event is not replayed after downtime.

## Remove

Run the installed uninstaller to disable the timer and remove AutoWake:

```sh
sudo /usr/local/sbin/autowake-uninstall
```

To preserve `/etc/autowake.conf` for a later reinstall:

```sh
sudo /usr/local/sbin/autowake-uninstall --keep-config
```

The uninstaller can also operate on an isolated staged installation without
contacting the host's systemd instance:

```sh
./uninstall.sh --root /tmp/autowake-stage
```

## Development verification

Run the complete automated suite with:

```sh
make test
```

It checks POSIX shell syntax, validates generated systemd units when
`systemd-analyze` is available, exercises calendar and daylight-saving
boundaries using fixed timestamps, and uses mocked power commands to verify
ordering and failures. It does not perform hardware validation.

RTC capabilities vary; consult the
[rtcwake manual](https://www.man7.org/linux/man-pages/man8/rtcwake.8.html) when
validating the target server.
