#!/bin/sh
# Run inside the target Debian/Ubuntu system, after APT sources are configured.
set -eu
export LC_ALL=C

remove_optimized_kernels() {
    installed_packages=$(dpkg-query -W -f='${db:Status-Status} ${binary:Package}\n') || return 1
    optimized_kernels=$(printf '%s\n' "$installed_packages" |
        while read -r status package; do
            [ "$status" = installed ] || continue
            case "$package" in
            linux-image-cloud-* | linux-image-*-cloud-* | linux-image-virtual* | linux-virtual* | \
                linux-image-aws* | linux-aws* | linux-image-*-aws* | \
                linux-image-azure* | linux-azure* | linux-image-*-azure* | \
                linux-image-gcp* | linux-gcp* | linux-image-*-gcp* | \
                linux-image-oracle* | linux-oracle* | linux-image-*-oracle* | \
                linux-image-ibm* | linux-ibm* | linux-image-*-ibm* | \
                linux-image-kvm* | linux-kvm* | linux-image-*-kvm*)
                echo "$package" ;;
            esac
        done)
    [ -n "$optimized_kernels" ] || return 0

    # Do not remove a bootable cloud image until its standard replacement and
    # initrd exist. APT autoremove alone can retain cloud kernels as protected.
    standard_bootable=false
    for image in /boot/vmlinuz-*; do
        case "$image" in
        *-amd64 | *-arm64 | *-generic | *-generic-64k)
            case "$image" in *-cloud-*) continue ;; esac
            release=${image##*/vmlinuz-}
            if [ -s "$image" ] && [ -s "/boot/initrd.img-$release" ]; then
                standard_bootable=true
                break
            fi ;;
        esac
    done
    if ! "$standard_bootable"; then
        echo 'No bootable standard kernel/initrd; keeping existing kernels.' >&2
        return 1
    fi
    # Package names come from dpkg, contain no shell metacharacters, and must
    # be separate APT arguments. Never purge linux-base or standard images.
    # shellcheck disable=SC2086
    DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 purge -y $optimized_kernels || return 1
    if command -v update-grub >/dev/null 2>&1; then update-grub; fi
}

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

# Accept cached/older installer requests but never install an optimized cloud
# kernel. Keep Debian architecture and Ubuntu HWE release suffixes intact.
case "$kernel_package" in
linux-image-cloud-*) kernel_package="linux-image-${kernel_package#linux-image-cloud-}" ;;
linux-image-virtual*) kernel_package="linux-image-generic${kernel_package#linux-image-virtual}" ;;
linux-virtual*) kernel_package="linux-generic${kernel_package#linux-virtual}" ;;
linux-image-aws | linux-image-azure | linux-image-gcp | linux-image-oracle | linux-image-ibm | linux-image-kvm)
    kernel_package=linux-image-generic ;;
linux-aws | linux-azure | linux-gcp | linux-oracle | linux-ibm | linux-kvm)
    kernel_package=linux-generic ;;
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
            remove_optimized_kernels
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
