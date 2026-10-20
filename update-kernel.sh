#!/bin/sh
# Run inside the target Debian/Ubuntu system, after APT sources are configured.
set -eu
export LC_ALL=C

configure_bios_console() {
    # The cloud kernel has VGA text support but may lack a driver for the
    # graphical framebuffer inherited from GRUB on x86 BIOS guests.
    case "$(uname -m)" in
    x86_64 | i?86) ;;
    *) return 0 ;;
    esac
    [ ! -d /sys/firmware/efi ] || return 0
    [ -f /etc/default/grub ] || return 0
    command -v update-grub >/dev/null 2>&1 || return 0

    mkdir -p /etc/default/grub.d || return 1
    cat >/etc/default/grub.d/99-reinstall-vnc.cfg <<'EOF' || return 1
# Loaded after 99-reinstall-ethx.cfg: keep --ethx's overwrite behaviour,
# then select the local VGA console without duplicating console=tty0.
case " ${GRUB_TERMINAL:-} ${GRUB_TERMINAL_INPUT:-} ${GRUB_TERMINAL_OUTPUT:-} " in
*" serial "*) GRUB_TERMINAL="console serial" ;;
*) GRUB_TERMINAL=console ;;
esac
GRUB_GFXPAYLOAD_LINUX=text
case " ${GRUB_CMDLINE_LINUX:-} " in
*" console=tty0 "*) ;;
*) GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX:-} console=tty0" ;;
esac
EOF
    update-grub
}

kernel_package=${1:-}
case "$kernel_package" in
linux-*) ;;
*) echo "Invalid kernel meta-package: $kernel_package" >&2; exit 1 ;;
esac
case "$kernel_package" in
*[!a-z0-9.+-]*) echo "Invalid kernel meta-package: $kernel_package" >&2; exit 1 ;;
esac

update_log=$(mktemp)
trap 'rm -f "$update_log"' 0
trap 'exit 1' HUP INT TERM

for attempt in 1 2 3; do
    echo "Updating kernel meta-package: $kernel_package (attempt $attempt/3)"
    # Older APT releases ignore Error-Mode=any and may return zero when a
    # security index failed. Check their English diagnostics as well.
    if apt-get -o Acquire::Retries=3 -o APT::Update::Error-Mode=any update >"$update_log" 2>&1 &&
        ! grep -Eq '^(Err:|E:|W: Failed to fetch|W: Some index files failed)' "$update_log"; then
        cat "$update_log"
        # Run install even if the meta-package is present: a new dependency
        # pulls in the latest kernel for this release and flavour.
        if DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 install -y "$kernel_package"; then
            apt-mark manual "$kernel_package"
            dpkg-query -W -f='${Package} ${Version}\n' "$kernel_package"
            configure_bios_console
            exit 0
        fi
    else
        cat "$update_log" >&2
    fi
    if [ "$attempt" -lt 3 ]; then sleep 5; fi
done

echo "Failed to update kernel meta-package: $kernel_package" >&2
exit 1
