#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export fixture=$scratch/target
export test_arch=x86_64

# Run the real updater, redirecting only the absolute target filesystem paths.
# Package management and bootloader regeneration must never touch the test host.
sed -e "s|/etc/default/grub|$fixture/etc/default/grub|g" \
    -e "s|/sys/firmware/efi|$fixture/sys/firmware/efi|g" \
    "$root/update-kernel.sh" >"$scratch/updater.sh"
apt-get() { :; }
apt-mark() { :; }
dpkg-query() { echo 'linux-image-cloud-amd64 6.12.113-1'; }
uname() { echo "$test_arch"; }
update-grub() {
    if [ -e "$fixture/grub-failure" ]; then return 1; fi
    (
        unset GRUB_TERMINAL GRUB_TERMINAL_INPUT GRUB_TERMINAL_OUTPUT GRUB_GFXPAYLOAD_LINUX GRUB_CMDLINE_LINUX
        source "$fixture/etc/default/grub"
        for config in "$fixture"/etc/default/grub.d/*.cfg; do
            [ ! -f "$config" ] || source "$config"
        done
        printf '%s\n' "${GRUB_TERMINAL:-}" "${GRUB_GFXPAYLOAD_LINUX:-}" "${GRUB_CMDLINE_LINUX:-}"
    ) >"$fixture/effective-config"
}
export -f apt-get apt-mark dpkg-query uname update-grub
sleep() { :; }
export -f sleep
fail() { echo "FAIL: $*" >&2; exit 1; }
reset_fixture() {
    rm -rf "${fixture:?}"
    mkdir -p "$fixture/etc/default/grub.d" "$fixture/sys/firmware"
    printf '%s\n' 'GRUB_CMDLINE_LINUX="old=1 console=ttyS0,115200n8"' >"$fixture/etc/default/grub"
    test_arch=x86_64
}
run_update() { bash "$scratch/updater.sh" linux-image-cloud-amd64 >"$scratch/output" 2>&1; }

reset_fixture
run_update || fail 'BIOS kernel update failed.'
[ -f "$fixture/etc/default/grub.d/99-reinstall-vnc.cfg" ] || fail 'The successful kernel update did not configure the BIOS console.'
[ "$(sed -n '1p' "$fixture/effective-config")" = console ] || fail 'BIOS GRUB still uses a graphical terminal.'
[ "$(sed -n '2p' "$fixture/effective-config")" = text ] || fail 'BIOS kernel payload is not text mode.'
[ "$(sed -n '3p' "$fixture/effective-config")" = 'old=1 console=ttyS0,115200n8 console=tty0' ] || fail 'Existing arguments were lost without --ethx.'
run_update || fail 'A second update failed.'
[ "$(sed -n '3p' "$fixture/effective-config")" = 'old=1 console=ttyS0,115200n8 console=tty0' ] || fail 'Repeated updates duplicated the VGA console.'
echo 'PASS: BIOS text console is generated, applied, and idempotent.'

# The human explicitly requires --ethx to overwrite the old command line.
# Use the production writer and evaluate both drop-ins in GRUB filename order.
source <(sed -n '/^apply_ethx_kernel_parameters() {/,/^}/p' "$root/trans.sh")
is_have_cmd_on_disk() { return 1; }
reset_fixture
use_ethx=1
apply_ethx_kernel_parameters "$fixture"
run_update || fail '--ethx BIOS update failed.'
[ "$(sed -n '3p' "$fixture/effective-config")" = 'net.ifnames=0 biosdevname=0 console=tty0' ] || fail '--ethx no longer overwrites old parameters, or loses the VGA console.'
echo 'PASS: --ethx overwrites original parameters; the later console setting adds tty0.'

reset_fixture
printf '%s\n' 'GRUB_TERMINAL="serial"' >>"$fixture/etc/default/grub"
run_update || fail 'Serial-console BIOS update failed.'
[ "$(sed -n '1p' "$fixture/effective-config")" = 'console serial' ] || fail 'The existing GRUB serial console was disabled.'
echo 'PASS: existing serial GRUB access is retained alongside the VGA console.'

for mode in uefi arm non-grub; do
    reset_fixture
    case "$mode" in
    uefi) mkdir -p "$fixture/sys/firmware/efi" ;;
    arm) test_arch=aarch64 ;;
    non-grub) rm "$fixture/etc/default/grub" ;;
    esac
    run_update || fail "Kernel update failed on $mode."
    [ ! -e "$fixture/etc/default/grub.d/99-reinstall-vnc.cfg" ] || fail "Text-mode BIOS settings were applied to $mode."
    [ ! -e "$fixture/effective-config" ] || fail "Unnecessary GRUB regeneration on $mode."
done
echo 'PASS: UEFI, ARM and systems without GRUB are not changed.'

reset_fixture
touch "$fixture/grub-failure"
if run_update; then fail 'GRUB generation failure was reported as a successful update.'; fi
echo 'PASS: GRUB generation errors stop the update.'
