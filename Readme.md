# AutoWake

**Scheduled suspend and automatic wake-up for Linux servers.**

AutoWake is a lightweight POSIX shell utility that uses a systemd timer to
suspend a physical Ubuntu/Debian server and a hardware real-time clock (RTC)
alarm to resume it.

## Why I created AutoWake

I created AutoWake because I was too lazy to manually start and suspend my
server every week. It automates the routine: the server goes to sleep when I no
longer need it and wakes up before I need it again.

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

The editable [architecture diagram](docs/autowake-architecture.drawio) shows
the installation, diagnostic, scheduled suspend, and hardware wake flows. Open
it with [draw.io](https://app.diagrams.net/) or the diagrams.net desktop app.

## Requirements

- A physical Ubuntu/Debian server running systemd.
- GNU `date`, `sed`, `grep`, util-linux (`rtcwake`), and systemd.
- Firmware and hardware support for suspend-to-RAM and RTC wake alarms.
- Root access for installation, alarm setup, and suspension.

Suspend-to-RAM requires continued power. AutoWake resumes a suspended machine;
it cannot turn on a machine that has lost or disconnected power.

## Install

For a fresh installation, run:

```sh
git clone https://github.com/apache261/Autowake.git
cd Autowake
sudo ./install.sh
```

If the repository is already downloaded, open its directory and run only:

```sh
sudo ./install.sh
```

The installer does not activate the schedule. Verify the installation with:

```sh
sudo /usr/local/sbin/autowake check
/usr/local/sbin/autowake preview
```

After completing a hardware wake test, enable the weekly timer:

```sh
sudo systemctl enable --now autowake.timer
systemctl list-timers autowake.timer
```

The installer places:

- `autowake` in `/usr/local/sbin`
- `autowake-uninstall` in `/usr/local/sbin`
- configuration in `/etc/autowake.conf`
- units in `/etc/systemd/system/autowake.service` and
  `/etc/systemd/system/autowake.timer`

An existing configuration is preserved. The installer regenerates the timer
from that configuration and reloads systemd. It never enables or starts the
timer automatically.

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

## Run custom scripts after wake

After a successful resume, AutoWake runs every executable regular file in
`/etc/autowake/wake.d` in filename order. This can be used for service health
checks, notifications, storage checks, or other site-specific recovery work.

Wake hooks run as root. Install them as root-owned files and do not make them
writable by untrusted users:

```sh
sudo install -o root -g root -m 0755 my-wake-check.sh \
    /etc/autowake/wake.d/20-my-wake-check
```

Non-executable files are ignored. If a hook fails, AutoWake records the failure
in the journal, continues running the remaining hooks, and marks the service
run as failed after all hooks finish. Hooks run only after suspends initiated by
AutoWake; they do not run after a reboot or an unrelated manual suspend.

An example hook checks for `llama-server` and starts it with `nohup` when it is
not running:

```sh
sudo install -o root -g root -m 0755 \
    examples/wake.d/10-ensure-llama-server \
    /etc/autowake/wake.d/10-ensure-llama-server
```

The example uses absolute paths below `/home/nisadmin/llama.cpp` and runs the
process as `nisadmin`. Edit `LLAMA_SERVER`, `MODEL`, and `RUN_AS_USER` if your
installation differs. A dedicated systemd service is still recommended if the
program must also recover after a reboot or power interruption, because wake
hooks run only after an AutoWake suspend.

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

Custom wake hooks are preserved during removal. The uninstaller removes the
hook directory only when it is empty.

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

To test installation without writing to system directories or contacting the
host's systemd instance:

```sh
./install.sh --root /tmp/autowake-stage
./uninstall.sh --root /tmp/autowake-stage
```

It checks POSIX shell syntax, validates generated systemd units when
`systemd-analyze` is available, exercises calendar and daylight-saving
boundaries using fixed timestamps, and uses mocked power commands to verify
ordering and failures. It does not perform hardware validation.

RTC capabilities vary; consult the
[rtcwake manual](https://www.man7.org/linux/man-pages/man8/rtcwake.8.html) when
validating the target server.

For common operational questions, see the [FAQ](FAQ.md).
