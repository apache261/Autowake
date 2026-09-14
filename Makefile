.PHONY: test check

test: check
	./tests/run.sh

check:
	sh -n autowake.sh install.sh uninstall.sh tests/run.sh
	@if command -v systemd-analyze >/dev/null 2>&1; then \
		tmp=$$(mktemp -d); \
		trap 'rm -rf "$$tmp"' EXIT HUP INT TERM; \
		./install.sh --root "$$tmp" >/dev/null; \
		sed -i "s|/usr/local/sbin/autowake|$$tmp/usr/local/sbin/autowake|" \
			"$$tmp/etc/systemd/system/autowake.service"; \
		systemd-analyze verify \
			"$$tmp/etc/systemd/system/autowake.service" \
			"$$tmp/etc/systemd/system/autowake.timer" >/dev/null 2>&1; \
	fi
