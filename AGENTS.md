# AutoWake — contributor and agent guidance

## Project purpose and status

AutoWake schedules weekly suspend and automatic wake-up for physical Ubuntu/Debian Linux servers using POSIX shell, systemd, and RTC alarms.

The repository currently contains planning documents only. The script, installer, systemd units, and tests have not been implemented. Keep documentation accurate about what exists and what is planned.

Read these documents before implementation:

- [Project overview](Readme.md)
- [Implementation plan](docs/plan.md)
- [Implementation phases](docs/plan_phase.md)

## Implementation conventions

- Use **AutoWake** in human-facing documentation and `autowake` for commands, configuration, and systemd unit names.
- Follow the selected POSIX `/bin/sh` approach with standard Ubuntu/Debian tools. Avoid Bash-only syntax and additional runtime dependencies.
- Default to Friday 19:00 suspension and Monday 06:00 wake-up in the server’s configured timezone, with `/dev/rtc0` as the RTC device.
- Keep schedule settings configurable through `/etc/autowake.conf`; generate the systemd timer from that configuration during installation.
- Quote shell expansions, validate configuration before use, and propagate failures with useful diagnostics. Do not use `eval` to parse configuration.
- Keep changes focused on the requested work and update documentation when behavior changes.

## Power-management behavior

- Keep `check` and `preview` free of power-state and RTC-alarm changes.
- Arm the wake alarm successfully before invoking `systemctl suspend`. Invalid configuration or alarm setup failure must prevent suspension.
- Use `Persistent=false` and enforce the planned five-minute execution window to avoid late suspension.
- Leave scheduling disabled on initial installation. An early wake-up must leave the server awake until the next scheduled suspension.
- Use mocked power commands for automated tests. Never suspend the development host or modify its RTC alarm as part of automated verification.
- Keep manual hardware validation separate from automated checks and report whether it has actually been performed.

## Verification and documentation

- Run `sh -n` on added or modified shell scripts and validate systemd units when available.
- Test schedule calculations with fixed timestamps, including calendar boundaries and daylight-saving transitions.
- Cover alarm-before-suspend ordering, command failures, invalid configuration, execution-window boundaries, and side-effect-free previews.
- Use isolated temporary locations for installation tests rather than modifying the host’s system directories.
- Keep phase completion status current as implementation progresses. Do not claim hardware wake support from a short test alone; verify the full intended interval on the target server.
- Report changes, checks performed, and any remaining limitations clearly. Documentation-only changes require checking consistency and local links, not power-management tests.
