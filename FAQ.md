# AutoWake FAQ

## The installer says scheduling was not enabled or started. What should I do?

This message means AutoWake was installed successfully, but its weekly timer is
still disabled:

```text
AutoWake installed. The installer did not enable or start scheduling.
After hardware validation, enable it with: systemctl enable --now autowake.timer
```

First, verify the server configuration and calculated schedule. These commands
do not suspend the server or change its RTC alarm:

```sh
sudo /usr/local/sbin/autowake check
/usr/local/sbin/autowake preview
```

Test the server's RTC wake support during a maintenance window before enabling
the weekly schedule. After hardware validation, enable the timer:

```sh
sudo systemctl enable --now autowake.timer
systemctl list-timers autowake.timer
```

With the default configuration, the next timer entry should be Friday at 19:00
in the server's configured timezone.

## Can AutoWake check or restart programs after the server wakes?

Yes. Place executable scripts in `/etc/autowake/wake.d`. AutoWake runs them in
filename order after its suspend command returns on resume.

For example, install the included `llama-server` service check:

```sh
sudo install -o root -g root -m 0755 \
    examples/wake.d/10-ensure-llama-server \
    /etc/autowake/wake.d/10-ensure-llama-server
```

The example checks for a `llama-server` process owned by `nisadmin`. When it is
not running, the hook uses the included `nohup` command with absolute paths
below `/home/nisadmin/llama.cpp`. Edit `LLAMA_SERVER`, `MODEL`, and
`RUN_AS_USER` if your installation differs. Wake hooks run as root, so only
administrators should be able to modify them.
