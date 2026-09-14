# AutoWake

**Scheduled suspend and automatic wake-up for Linux servers.**

AutoWake is a planned lightweight POSIX shell utility that uses systemd to schedule suspension and a hardware real-time clock (RTC) alarm to wake a physical Ubuntu/Debian server.

## Project status

**Planning stage.** This repository currently contains the design and implementation phases. The executable script, installer, systemd units, and automated tests are not yet available.

## Default schedule

| Action | Time |
| --- | --- |
| Suspend | Every Friday at 7:00 PM |
| Wake up | Every Monday at 6:00 AM |
| Timezone | Server’s configured local timezone |

The planned configuration will allow changing the weekdays, times, and RTC device. The default device is `/dev/rtc0`.

## How it will work

1. A systemd timer starts AutoWake at the configured suspend time.
2. AutoWake validates the configuration and calculates the upcoming wake time.
3. It sets an RTC wake alarm using `rtcwake`.
4. After successful alarm setup, it requests suspension through `systemctl suspend`.
5. The hardware alarm resumes the server at the configured wake time.

Invalid configuration or alarm setup failure will prevent suspension. Late executions beyond the planned five-minute window will be skipped. If the server wakes early, it will remain awake until the next scheduled suspension.

## Planned commands

| Command | Purpose |
| --- | --- |
| `autowake.sh check` | Inspect configuration, dependencies, and available suspend/RTC interfaces without changing alarms or power state. |
| `autowake.sh preview` | Display the next scheduled suspend and wake times without changing the machine. |
| `autowake.sh run` | Set the wake alarm and request suspension within the scheduled execution window. |

These commands are planned interfaces and cannot be run from this repository yet. Installation and usage instructions will be added with the implementation. Initial installation will leave the timer disabled until explicitly enabled.

## Target environment

- A physical Ubuntu/Debian server running systemd.
- Standard system tools: `/bin/sh`, GNU coreutils, and util-linux (`rtcwake`).
- Hardware and firmware that support suspend-to-RAM and RTC wake-up over the full intended interval.
- Administrative privileges for installation, RTC alarm setup, and suspension.

Suspend-to-RAM requires continued power. Wake-up means resuming the suspended server, not powering on a disconnected machine. The default weekend interval is 59 hours unless a timezone offset change occurs. RTC alarm capabilities vary, so the target server needs both a short wake-up test and a full-interval test; see the [rtcwake manual](https://www.man7.org/linux/man-pages/man8/rtcwake.8.html).

## Project documents

- [Implementation plan](docs/plan.md)
- [Implementation phases and acceptance criteria](docs/plan_phase.md)
- [Contributor and agent guidance](AGENTS.md)

The implementation will use shell and systemd, with no Go runtime or continuously running custom daemon.
